# Semantic explanation — SFIssueSET

**Fixed SQL:** `03_fix/output/SFIssueSET_fixed.sql`
**Teradata ground truth:** none (no `00_input/SFIssueSET.teradata.sql`).
**Reviewer guidance:** `07_review/output/review_SFIssueSET.md` — *"This is a SET
table in teradata. So, there should not be any duplicates. You need to handle
the dedup logic in the query."* (authoritative; answers the SEM-05 SET-table
question).
**Date:** 2026-07-24.

---

## 1. Purpose

`SFIssueSET` refreshes `staging.wrk_target` — a **SET table** (confirmed by the
reviewer) — with the latest effective flight attributes from three leg sources:
the **marketing** leg (`synthetic_mkg_flgt_leg`), the **operational** leg
(`synthetic_operational_flgt_leg`), and the **codeshare** leg
(`synthetic_codeshare_flgt_leg`). The grain of one output row is one
`(airline_cd, flgt_no, flgt_dt)`; for each grain key the statement carries the
most-recent `effective_dt` snapshot of five attributes — `company_cd`,
`direction_ind`, `operating_airline_cd`, `operating_flgt_no`,
`operating_sfx_cd` — sourced from `synthetic_flgt_source` joined to the
corresponding leg table. Each of the three leg sources is inserted
**independently** with SET-table deduplication reproduced as
`EXCEPT SELECT * FROM staging.wrk_target`, so a row that already exists in the
target is silently dropped (the Teradata SET-table no-op) and rows two branches
produce in common are *not* collapsed across branches (the original Teradata had
three independent INSERTs, not one `UNION`). The `UPDATE_CUTOFF` parameter in
`synthetic_sys_param` bounds which flight dates are eligible.

---

## 2. Clause-by-clause walk-through

### 2.1 Three independent `INSERT … EXCEPT` statements (why split)

The fixed file contains **three separate** `INSERT INTO staging.wrk_target
( … ) ( SELECT <branch> EXCEPT SELECT * FROM staging.wrk_target )` statements
(Branch 1 marketing, Branch 2 operational, Branch 3 codeshare). The split is the
single decisive remediation and is driven by **SEM-05**: the reviewer confirmed
`staging.wrk_target` is a SET table. The delivered input had collapsed the three
Teradata INSERTs into one `INSERT … UNION … UNION`, which is wrong for a SET
table in two ways — `UNION` deduplicates *across* branches (collapsing rows two
branches emit in common), and a single INSERT re-inserts rows already present in
the target (Snowflake has no SET-table silent-drop). Splitting into three
independent `INSERT … EXCEPT SELECT * FROM staging.wrk_target` statements
reproduces the original Teradata semantics: each branch is deduped against the
existing target rows independently, and cross-branch duplicates are preserved
exactly as the three independent Teradata INSERTs would have done.

### 2.2 Explicit INSERT column list (8 columns)

Each `INSERT INTO staging.wrk_target` now carries an explicit column list —
`( airline_cd, flgt_no, flgt_dt, company_cd, direction_ind,
operating_airline_cd, operating_flgt_no, operating_sfx_cd )`. The list was added
as part of the SEM-05 FIX because `EXCEPT SELECT * FROM staging.wrk_target`
relies on positional column matching between the SELECT branch and the target.
With no DDL supplied, the explicit list makes the positional binding unambiguous
and protects against any future target-column reordering. The order matches the
SELECT expression order in every branch (the three branches are
expression-order-identical). This is flagged `TODO(SME)` because the target's
physical column order cannot be verified without the DDL.

### 2.3 `EXCEPT SELECT * FROM staging.wrk_target` (SET-table dedup)

Each branch's `SELECT … GROUP BY …` result is fed to `EXCEPT SELECT * FROM
staging.wrk_target`. This removes from the branch result any row that already
exists in the target — the Snowflake equivalent of the Teradata SET-table
"silent drop of full-row duplicates on INSERT." Because the `EXCEPT` is applied
**per branch** (three separate statements), the dedup is against the target
only, never across branches. This is the exact behavior of three independent
Teradata SET-table INSERTs.

### 2.4 Branch 1 — marketing leg (`synthetic_mkg_flgt_leg`)

`synthetic_flgt_source src` is joined to `synthetic_mkg_flgt_leg leg` on
`src.airline_cd = leg.marketing_airline_cd AND src.flgt_no =
leg.marketing_flgt_no AND src.flgt_dt = leg.gmt_flgt_dt`. This is the marketing
carrier view of the flight: the airline that *sells* the flight under its own
code. The join keys are the marketing airline code, marketing flight number, and
GMT flight date.

### 2.5 Branch 2 — operational leg (`synthetic_operational_flgt_leg`)

Same source `synthetic_flgt_source src` is joined to
`synthetic_operational_flgt_leg leg` on `src.airline_cd =
leg.operating_airline_cd AND src.flgt_no = leg.operating_flgt_no AND
src.flgt_dt = leg.gmt_flgt_dt`. This is the operating carrier view: the airline
that *physically operates* the flight. The join keys switch to the operating
airline code and operating flight number.

### 2.6 Branch 3 — codeshare leg (`synthetic_codeshare_flgt_leg`)

`synthetic_flgt_source src` is joined to `synthetic_codeshare_flgt_leg cs` on
`src.airline_cd = cs.codeshare_airline_cd AND src.flgt_no =
cs.codeshare_flgt_no AND src.flgt_dt = cs.gmt_flgt_dt`. This is the codeshare
view: a partner airline marketing the flight under a codeshare agreement. The
join keys are the codeshare airline code and codeshare flight number.

### 2.7 WHERE filters

Every branch applies two predicates:

- `leg.dep_stn_cd <> leg.arr_stn_cd` (or `cs.dep_stn_cd <> cs.arr_stn_cd` in
  Branch 3) — excludes grounded/cancelled legs where departure and arrival
  stations are identical (a no-op flight).
- `src.flgt_dt > ( SELECT param_value FROM synthetic_sys_param WHERE param_id =
  'UPDATE_CUTOFF' )` — bounds eligible flight dates to those after the
  `UPDATE_CUTOFF` parameter. This is a scalar subquery into a parameter table.
  The comparison is a date column against a string `param_value`, relying on an
  implicit string→date cast (SEM-06/DTX-10, flagged `TODO(SME)`).

### 2.8 GROUP BY

`GROUP BY src.airline_cd, src.flgt_no, src.flgt_dt` — collapses to the grain key
`(airline_cd, flgt_no, flgt_dt)`. All five attribute columns are aggregates (the
latest-value trick below), so the group key is exactly the output grain.

### 2.9 Latest-value trick (`SUBSTR(MAX(effective_dt || val), 11, N)`)

For each attribute column the statement computes the most-recent
`effective_dt` snapshot using the pattern
`SUBSTR(MAX(src.effective_dt || leg.<attr>), 11, N)`. The trick concatenates the
`effective_dt` (as a string) with the attribute value, takes the
lexicographic `MAX` (which sorts by `effective_dt` first, then by the value as a
tie-breaker), and strips the first 10 characters (the `effective_dt` prefix)
with `SUBSTR(…, 11, N)`, leaving the winning attribute value. This is correct
**only if** `effective_dt` is a fixed-width, lexicographically sortable string
(e.g. `YYYY-MM-DD`) and each attribute value is left-padded to a constant width
so the `MAX` tie-break is deterministic. The fixed file preserves the original
expression verbatim and flags the fixed-width requirement as `TODO(SME)`
(SEM-02/FN-LATEST). Note `operating_airline_cd` uses width `3`
(`SUBSTR(…, 11, 3)`) while all other attributes use width `99` — this width-3
truncation is also flagged `TODO(SME)` for confirmation against the source DDL.

---

## 3. Semantic checks table

| SEM ID | Risk | Present? | Corrected how? | Equivalent to Teradata? |
|---|---|---|---|---|
| **SEM-05** | SET-table dedup | **Yes** (confirmed SET by reviewer) | Split the single `INSERT … UNION … UNION` into 3 independent `INSERT INTO staging.wrk_target (cols) ( SELECT … EXCEPT SELECT * FROM staging.wrk_target )` statements; added explicit INSERT column list for positional EXCEPT match; removed `UNION` operators. | **Yes** — `EXCEPT SELECT * FROM staging.wrk_target` reproduces the SET-table "drop rows already present" no-op, and per-branch execution preserves the original three-independent-INSERT semantics. Reviewer-confirmed SET. |
| SEM-02 | `QUALIFY` / dedup ordering (latest-value trick tie-break) | **Yes** | Not corrected (SME). The `SUBSTR(MAX(effective_dt \|\| val), 11, N)` pattern needs a fixed-width, lexicographically sortable key (`TO_CHAR(effective_dt,'YYYY-MM-DD') \|\| LPAD(val::VARCHAR,n,' ')`). Flagged `TODO(SME)`. | **SME** — depends on `effective_dt` type and value display widths. |
| SEM-06 | Implicit cast / NULL in comparison | **Yes** | Not corrected (SME). `src.flgt_dt > (SELECT param_value …)` compares a date column to a string `param_value`; relies on implicit string→date cast. Flagged `TODO(SME)`. | **SME** — confirm `param_value` format; make cast explicit (`TO_DATE(param_value,'YYYY-MM-DD')`). |
| SEM-01 | Integer division | No | — | N/A — no `INT / INT` present. |
| SEM-03 | `CHAR(n)` padding & comparison | No (as a join/predicate risk) | — | N/A — no explicit `CHAR(n)` join predicate observed. The `operating_airline_cd` width-3 truncation is a width-consistency concern, not a CHAR-padding comparison; flagged under SEM-02/FN-LATEST. |
| SEM-04 | Timestamp / timezone | No | — | N/A — no `TIMESTAMP`/TZ-sensitive comparison; `flgt_dt` and `effective_dt` are date-valued. |
| SEM-07 | `NULL` ordering | No | — | N/A — no `ORDER BY` feeding `QUALIFY`/`TOP`. |
| SEM-08 | Empty string vs NULL | No | — | N/A — no `NULLIF(x,'')` or empty-string predicate. |
| SEM-09 | Aggregate of empty set / `SUM` NULL | No | — | N/A — only `MAX` of a concatenated string; no `SUM`/division downstream. |
| SEM-10 | Exchange-rate / lookup join direction | No | — | N/A — no exchange-rate/lookup join; join keys are carrier/flight/date, direction is explicit in each branch's join condition. |

---

## 4. Divergences from the original

The single structural divergence is the **SEM-05 SET-table split**, confirmed by
the reviewer:

1. **One `INSERT … UNION … UNION` → three independent `INSERT … EXCEPT SELECT *
   FROM staging.wrk_target` statements.** The delivered input collapsed the
   three Teradata INSERTs into a single `INSERT` wrapping three `SELECT`
   branches with `UNION`. On a SET table this is wrong: `UNION` deduplicates
   *across* branches (collapsing rows two branches emit in common) and a single
   INSERT re-inserts rows already in the target (Snowflake has no SET-table
   silent-drop). The fix restores the original three-independent-INSERT
   semantics by splitting into three statements, each deduped against the target
   via `EXCEPT`.
2. **`UNION` operators removed.** The cross-branch dedup they imposed is not
   part of the Teradata semantics and is eliminated by the split.
3. **Explicit INSERT column list added** to each statement
   (`airline_cd, flgt_no, flgt_dt, company_cd, direction_ind,
   operating_airline_cd, operating_flgt_no, operating_sfx_cd`). This makes the
   `EXCEPT SELECT * FROM staging.wrk_target` positional match unambiguous
   without the target DDL.
4. **Each branch body is preserved verbatim** — the SELECT expressions, JOIN
   conditions, WHERE filters, and GROUP BY are unchanged from the input. The
   only change is the wrapping `INSERT … EXCEPT` structure and the column list.

This is a **structural** change driven entirely by SEM-05 (SET-table dedup),
confirmed by the reviewer. No syntax, function, datatype, or defect fixes were
applied — the input parsed clean with 0 residual-Teradata constructs.

---

## 5. Open SME questions

1. **[SEM-05]** Confirm the target `staging.wrk_target` physical column order
   matches the explicit INSERT list
   `(airline_cd, flgt_no, flgt_dt, company_cd, direction_ind,
   operating_airline_cd, operating_flgt_no, operating_sfx_cd)`. No DDL was
   supplied; the list mirrors the SELECT expression order in every branch.
2. **[SEM-02/FN-LATEST]** Is `effective_dt` a `DATE` or `TIMESTAMP`? What are the
   display widths of each attribute value (`company_cd`, `direction_ind`,
   `operating_airline_cd`, `operating_flgt_no`, `operating_sfx_cd`) for `LPAD`?
   The latest-value trick `SUBSTR(MAX(effective_dt || val), 11, N)` needs a
   fixed-width, lexicographically sortable key — recommend
   `TO_CHAR(effective_dt,'YYYY-MM-DD') || LPAD(val::VARCHAR,n,' ')` before `MAX`.
3. **[SEM-02]** Is `effective_dt` unique per `(airline_cd, flgt_no, flgt_dt)`
   group, or can ties occur? If ties are possible, the `MAX` tie-break is
   non-deterministic without a fixed-width value suffix.
4. **[SEM-06/DTX-10]** Is `param_value` in `synthetic_sys_param` a
   date-formatted string (e.g. `'YYYY-MM-DD'`)? Should the comparison be
   `src.flgt_dt > TO_DATE(param_value, 'YYYY-MM-DD')` to make the cast explicit?
5. **[SEM-02/width consistency]** Is the width-3 truncation on
   `operating_airline_cd` (`SUBSTR(…, 11, 3)` vs `SUBSTR(…, 11, 99)` for all
   other attributes) intentional? Confirm the declared width of
   `operating_airline_cd` in the source DDL — if it can exceed 3 chars, the
   truncation drops data.

---

## 6. Inline anchors

```anchors
INSERT INTO staging.wrk_target :: SEM-05: SET table (confirmed by reviewer) — 3 independent INSERT…EXCEPT statements reproduce SET-table dedup.
( airline_cd, flgt_no, flgt_dt, company_cd, direction_ind, operating_airline_cd, operating_flgt_no, operating_sfx_cd ) :: SEM-05: Explicit INSERT column list added for unambiguous EXCEPT positional match (no DDL supplied — TODO(SME)).
EXCEPT :: SEM-05: EXCEPT SELECT * FROM staging.wrk_target deduplicates each branch against existing target rows (SET-table "drop rows already present" semantics).
SELECT * FROM staging.wrk_target :: SEM-05: Target dedup — each branch is deduped against the target independently, not cross-branch via UNION.
JOIN   synthetic_mkg_flgt_leg leg :: Branch 1 — marketing carrier view; joins src to leg on marketing_airline_cd / marketing_flgt_no / gmt_flgt_dt.
JOIN   synthetic_operational_flgt_leg leg :: Branch 2 — operating carrier view; joins src to leg on operating_airline_cd / operating_flgt_no / gmt_flgt_dt.
JOIN   synthetic_codeshare_flgt_leg cs :: Branch 3 — codeshare view; joins src to cs on codeshare_airline_cd / codeshare_flgt_no / gmt_flgt_dt.
leg.dep_stn_cd <> leg.arr_stn_cd :: WHERE filter — excludes no-op legs where departure station equals arrival station.
cs.dep_stn_cd <> cs.arr_stn_cd :: WHERE filter (Branch 3) — same dep<>arr exclusion on the codeshare leg alias.
SELECT param_value :: SEM-06: param_value implicit string→date cast in the UPDATE_CUTOFF scalar subquery — confirm format, consider TO_DATE(param_value,'YYYY-MM-DD').
WHERE  param_id = 'UPDATE_CUTOFF' :: UPDATE_CUTOFF parameter bounds eligible flight dates to those after the cutoff.
GROUP BY :: Grain key (airline_cd, flgt_no, flgt_dt) — collapses to one output row per flight per date.
SUBSTR(MAX(src.effective_dt || leg.company_cd), 11, 99) :: SEM-02/FN-LATEST: Latest-value trick — needs fixed-width key (TO_CHAR(effective_dt,'YYYY-MM-DD') || LPAD(val,n,' ')) before MAX.
SUBSTR(MAX(src.effective_dt || leg.operating_airline_cd), 11, 3) :: SEM-02/width: operating_airline_cd uses width 3 while others use 99 — confirm declared width (TODO(SME)).
```