# Stage 6 — Semantic Explanation: `SFIssueSET.sql`

**Fixed SQL:** `03_fix/output/SFIssueSET_fixed.sql`
**Analysis:** `01_analyze/output/analysis_SFIssueSET.md`
**Teradata ground truth:** none (`00_input/SFIssueSET.teradata.sql` not present).
**Target dialect:** Snowflake.
**Date:** 2026-07-24.

> Semantic intent is inferred from the SQL itself plus naming conventions.
> Every inference is flagged `TODO(SME)`. No Teradata original is available to
> prove equivalence, so each `SEM-*` finding is classified **SME** rather than
> **Yes**.

---

## 1. Purpose

This statement builds a flight-issue staging table, `staging.wrk_target`, at the
grain of **one row per `(airline_cd, flgt_no, flgt_dt)`** — i.e. one row per
airline / flight-number / flight-date triple. It reads the common flight source
`synthetic_flgt_source` (`src`) and enriches each flight with the **latest
effective** descriptive attributes (company code, direction indicator, and the
operating airline / flight-number / suffix triplet) drawn from **three leg
sources unioned together**: the marketing leg table
(`synthetic_mkg_flgt_leg`), the operational leg table
(`synthetic_operational_flgt_leg`), and the codeshare leg table
(`synthetic_codeshare_flgt_leg`). The three branches are joined by `UNION`, so
the output is the de-duplicated union of marketing-, operational-, and
codeshare-derived flight attributes. Only legs that actually move (departure
station differs from arrival station) and only flights dated after the
`UPDATE_CUTOFF` system parameter are retained. The "latest effective" value for
each attribute is selected per group via the `SUBSTR(MAX(effective_dt || val),
11, N)` latest-value trick.

---

## 2. Clause-by-clause walk-through

### 2.1 The single `INSERT INTO staging.wrk_target`

The whole statement is one `INSERT` whose body is a three-branch `SELECT …
UNION … SELECT … UNION … SELECT`. There is **no explicit INSERT column list**,
so the eight SELECT expressions per branch must line up positionally with the
columns of `staging.wrk_target` (DDL not supplied — see SEM-05). All three
branches expose the same eight columns in the same order:
`airline_cd, flgt_no, flgt_dt, company_cd, direction_ind,
operating_airline_cd, operating_flgt_no, operating_sfx_cd`.

### 2.2 Branch 1 — marketing leg (`synthetic_mkg_flgt_leg`, alias `leg`)

Joins `synthetic_flgt_source src` to `synthetic_mkg_flgt_leg leg` on the
**marketing** carrier / flight-number / flight-date keys
(`src.airline_cd = leg.marketing_airline_cd`,
`src.flgt_no = leg.marketing_flgt_no`,
`src.flgt_dt = leg.gmt_flgt_dt`). This branch attributes each source flight
using the marketing-carrier view of the leg.

### 2.3 Branch 2 — operational leg (`synthetic_operational_flgt_leg`, alias `leg`)

Same shape as branch 1 but joins on the **operating** carrier / flight-number /
flight-date keys (`src.airline_cd = leg.operating_airline_cd`,
`src.flgt_no = leg.operating_flgt_no`, `src.flgt_dt = leg.gmt_flgt_dt`). This
branch attributes each source flight using the operating-carrier view of the
leg.

### 2.4 Branch 3 — codeshare leg (`synthetic_codeshare_flgt_leg`, alias `cs`)

Same shape again but joins on the **codeshare** carrier / flight-number /
flight-date keys (`src.airline_cd = cs.codeshare_airline_cd`,
`src.flgt_no = cs.codeshare_flgt_no`, `src.flgt_dt = cs.gmt_flgt_dt`). This
branch attributes each source flight using the codeshare-carrier view of the
leg. (Note: branch 3 reads `company_cd`, `direction_ind`,
`operating_airline_cd`, `operating_flgt_no`, `operating_sfx_cd` from the `cs`
alias, whereas branches 1–2 read them from `leg`.)

### 2.5 WHERE filters (identical in all three branches)

1. **`leg.dep_stn_cd <> leg.arr_stn_cd`** (branch 3 uses `cs.dep_stn_cd <>
   cs.arr_stn_cd`) — excludes same-station (cancellation / ground-only) legs;
   only genuine point-to-point legs survive.
2. **`src.flgt_dt > (SELECT param_value FROM synthetic_sys_param WHERE
   param_id = 'UPDATE_CUTOFF')`** — keeps only flights whose date is after the
   `UPDATE_CUTOFF` parameter value. The comparison relies on an implicit
   string→date cast of `param_value` (see SEM-06).

### 2.6 GROUP BY (identical in all three branches)

`GROUP BY src.airline_cd, src.flgt_no, src.flgt_dt` — collapses each branch's
joined rows to one row per `(airline_cd, flgt_no, flgt_dt)`. The five
non-key columns are produced by the latest-value trick below.

### 2.7 The latest-value trick — `SUBSTR(MAX(src.effective_dt || <val>), 11, N)`

For each attribute column the statement concatenates `src.effective_dt` (the
row's effective timestamp/date) with the attribute value, takes `MAX` over the
group, then strips the date prefix with `SUBSTR(..., 11, N)`. The intent is:
**"pick the attribute value from the row whose `effective_dt` is greatest
within the group."** The `11` offset assumes the date prefix occupies exactly
10 characters (e.g. `YYYY-MM-DD`); the `N` is the retained value width (`99`
for free-text columns, `3` for `operating_airline_cd`).

This idiom is correct **only if** the concatenated key is fixed-width and
lexicographically sortable:

- `effective_dt` must render as a zero-padded ISO string
  (`TO_CHAR(effective_dt,'YYYY-MM-DD')`), not a raw DATE/TIMESTAMP whose
  implicit cast may contain spaces/colons and sort wrongly.
- The value must be right-padded (`LPAD(val::VARCHAR, N, ' ')`) so that
  variable-width values do not corrupt the `MAX` ordering.

Neither formatting is present in the fixed SQL (see SEM-02 / FN-LATEST).

### 2.8 `UNION` dedup behaviour

Two `UNION` operators join the three branches. `UNION` (not `UNION ALL`)
**de-duplicates across branches**: if the same `(airline_cd, flgt_no, flgt_dt,
company_cd, …)` row is produced by more than one branch, only one copy reaches
the target. This is a cross-branch dedup that is independent of any SET-table
dedup the target itself may perform (see SEM-05). Whether the original Teradata
logic intended cross-branch dedup, separate INSERTs into a SET table, or
`UNION ALL` cannot be determined without the Teradata original or the target
DDL.

---

## 3. Semantic checks table

| SEM ID | Risk | Present? | Corrected how? | Equivalent to Teradata? |
|---|---|---|---|---|
| SEM-01 | Integer division | **No** — there is no `/` arithmetic anywhere in the statement. | n/a | n/a |
| SEM-02 | `QUALIFY` / dedup ordering (tie-break non-determinism) | **Yes** — the `SUBSTR(MAX(effective_dt \|\| val), 11, N)` latest-value trick is a string-`MAX` dedup whose winner is non-deterministic when `effective_dt` ties within a group, and whose ordering is only correct for a fixed-width, lexicographically sortable key. | **Not corrected (SME).** No `TO_CHAR`/`LPAD` fixed-width formatting was added; the body is unchanged. Flagged `TODO(SME)` at each `SUBSTR(MAX(...))`. | **SME** — no Teradata ground truth; cannot confirm the original idiom or that ties are impossible. |
| SEM-03 | `CHAR(n)` padding & comparison | **No** — no `=`/`<>` predicate compares CHAR-padded columns; the join keys are equality on `airline_cd`/`flgt_no`/`flgt_dt` and the only `<>` is on station codes. No evidence of CHAR-padding drift. | n/a | n/a |
| SEM-04 | Timestamp / timezone | **No** — no `TIMESTAMP`/`TIMESTAMP_TZ` literal or conversion is present. `effective_dt` and `flgt_dt` are used as dates/strings only; timezone is not in scope of this statement. | n/a | n/a |
| SEM-05 | SET-table dedup | **Yes** — a single `INSERT INTO staging.wrk_target` with three `UNION` branches all writing to one target is a SET-dedup **signal**. No `CREATE TABLE staging.wrk_target` DDL is supplied, so SET vs MULTISET cannot be decided from the SQL alone. | **Not corrected (SME).** Per SEM-05 the structure is preserved as-is; SET is never assumed. Flagged `TODO(SME)` at the `INSERT` and at each `UNION`. | **SME** — cannot confirm whether the original used separate INSERTs into a SET table, `UNION ALL`, or cross-branch `UNION`. |
| SEM-06 | Implicit cast / NULL in comparison | **Yes** — `src.flgt_dt > (SELECT param_value …)` compares a date column to a string parameter value, relying on an implicit string→date cast. | **Not corrected (SME).** No `TO_DATE(param_value,'YYYY-MM-DD')` was added; the body is unchanged. Flagged `TODO(SME)` at each `param_value` subquery. | **SME** — cannot confirm `param_value` is an ISO date string; Snowflake is stricter than Teradata and may error or silently mismatch. |
| SEM-07 | `NULL` ordering | **No** — there is no `ORDER BY` feeding a `QUALIFY`/`TOP`. The dedup is via `MAX` over a concatenated string, not via `ROW_NUMBER`/`QUALIFY`, so NULL-position defaults do not apply. | n/a | n/a |
| SEM-08 | Empty string vs NULL | **No** — no `''` literal, no `NULLIF(x,'')`, no empty-string predicate is present. | n/a | n/a |
| SEM-09 | Aggregate of empty set / `SUM` NULL | **No** — the only aggregate is `MAX` over a non-null concatenation; there is no `SUM`/`AVG`/division over an empty set. | n/a | n/a |
| SEM-10 | Exchange-rate / lookup join direction | **No** — there is no exchange-rate or lookup-direction alias ambiguity; each branch's join keys are named consistently with their leg table's role (marketing / operational / codeshare). | n/a | n/a |

**Summary:** 3 of 10 SEM risks are present (SEM-02, SEM-05, SEM-06); all 3 are
classified **SME** because no Teradata ground truth or target DDL is available.
The remaining 7 are not present, for the reasons above.

---

## 4. Divergences from the original

**None.** The SQL body is byte-for-byte unchanged from the input — no
mechanical syntax, function, type, or defect fixes were required (the file
parses clean on Snowflake). The only additions are `FIX LOG` and `TODO(SME)`
**comments**, which do not affect parsing or execution. All semantic risks are
left for SME decision; no assumption has been baked into the code.

---

## 5. Open SME questions

Each is phrased as a decision the reviewer must make. All are also present as
`TODO(SME)` markers in `03_fix/output/SFIssueSET_fixed.sql`.

1. **[SEM-05] Is `staging.wrk_target` a SET table?** If yes, each `UNION` branch
   must be ported as a separate
   `INSERT INTO staging.wrk_target (SELECT … EXCEPT SELECT * FROM staging.wrk_target)`
   — never a single cross-branch `UNION`. Do **not** assume SET.
2. **[SEM-05] Should the three branches be `UNION ALL` or separate INSERTs?**
   Confirm the intended set-semantics. `UNION` de-duplicates across branches;
   if the original used separate INSERTs (SET-table dedup) or `UNION ALL`, the
   current `UNION` is wrong.
3. **[SEM-02 / FN-LATEST] Is `src.effective_dt` a DATE or a TIMESTAMP, and what
   are the max display widths of the concatenated value columns?** The
   latest-value trick needs a fixed-width key — format as
   `TO_CHAR(effective_dt,'YYYY-MM-DD') || LPAD(val::VARCHAR, N, ' ')` before
   `MAX`. Confirm the type and the per-column `N` for `LPAD`.
4. **[SEM-02] Is `effective_dt` unique per `(airline_cd, flgt_no, flgt_dt)`
   group, or can ties occur?** If ties are possible, `MAX(effective_dt || val)`
   picks the lexicographically larger *value*, not necessarily the intended
   row; a deterministic tie-break is needed.
5. **[SEM-06 / DTX-10] Is `synthetic_sys_param.param_value` a date-formatted
   string (e.g. `YYYY-MM-DD`)?** Should the comparison be
   `src.flgt_dt > TO_DATE(param_value, 'YYYY-MM-DD')` to make the cast explicit
   and avoid Snowflake's stricter implicit-cast behaviour?
6. **[consistency] Is the width-3 truncation on `operating_airline_cd`
   (`SUBSTR(..., 11, 3)`) intentional?** All other value columns use
   `SUBSTR(..., 11, 99)`. Likely intentional (airline codes are 2–3 chars) but
   unconfirmable without ground truth.

---

## 6. Inline anchors

Each `MATCH text` below appears verbatim in `03_fix/output/SFIssueSET_fixed.sql`.
`06_explain/annotate.py` will inject each `note` as a `-- SEM ▸ <note>` comment
above the first SQL line containing the match text.

```anchors
INSERT INTO staging.wrk_target :: SEM-05: Is staging.wrk_target a SET table? If yes, each branch must be a separate INSERT … EXCEPT; never a single cross-branch UNION.
SUBSTR(MAX(src.effective_dt || leg.company_cd), 11, 99) :: SEM-02/FN-LATEST: Latest-value trick needs fixed-width key (TO_CHAR(effective_dt,'YYYY-MM-DD') || LPAD(val,N,' ')) before MAX.
SUBSTR(MAX(src.effective_dt || leg.operating_airline_cd), 11, 3) :: SEM-02/consistency: width-3 truncation on operating_airline_cd — confirm intentional vs other columns' width 99.
JOIN   synthetic_mkg_flgt_leg leg :: Branch 1: marketing-leg attribution — joins src to marketing carrier/flight/date keys.
JOIN   synthetic_operational_flgt_leg leg :: Branch 2: operational-leg attribution — joins src to operating carrier/flight/date keys.
JOIN   synthetic_codeshare_flgt_leg cs :: Branch 3: codeshare-leg attribution — joins src to codeshare carrier/flight/date keys; attributes read from cs alias.
leg.dep_stn_cd <> leg.arr_stn_cd :: WHERE filter: excludes same-station (ground-only/cancellation) legs; only point-to-point legs survive.
SELECT param_value :: SEM-06: param_value implicit string→date cast — confirm ISO format and consider TO_DATE(param_value,'YYYY-MM-DD').
GROUP BY :: Grain: one output row per (airline_cd, flgt_no, flgt_dt); five non-key columns resolved by the latest-value trick.
UNION :: SEM-05: UNION (not UNION ALL) de-duplicates across the three branches — confirm this matches original set-semantics.
```