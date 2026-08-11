# Semantic explanation — `SFIssueSET.sql`

**Fixed file:** `03_fix/output/SFIssueSET_fixed.sql`
**Analysis:** `01_analyze/output/analysis_SFIssueSET.md`
**Teradata ground truth:** none supplied (no `00_input/SFIssueSET.teradata.sql`).
**Reviewer guidance:** `07_review/output/review_SFIssueSET.md` — *"This is a SET
table in teradata. So, there should not be any duplicates. You need to handle the
dedup logic in the query."* → `staging.wrk_target` is a **SET table**; SEM-05 is
confirmed and applied as a FIX.

---

## 1. Purpose

This script loads flight-leg attributes into the staging target
`staging.wrk_target` (a Teradata **SET** table, reviewer-confirmed) from a
flight-source table joined to three different leg tables — marketing,
operational, and codeshare. Each branch picks the **latest** leg attributes per
flight (by `effective_dt`) using the "latest-value trick"
(`SUBSTR(MAX(effective_dt || <value>), 11, N)`), filters to legs whose departure
station differs from the arrival station, and only loads flights newer than an
`UPDATE_CUTOFF` parameter. Because the target is a SET table, each branch must
deduplicate **against the target's existing rows** (not against the other
branches); the fixed SQL therefore emits three independent
`INSERT … (SELECT … EXCEPT SELECT * FROM staging.wrk_target)` statements — one
per leg type — rather than the buggy single `INSERT … UNION … UNION`.

The grain of one output row is: **one `(airline_cd, flgt_no, flgt_dt)` flight ×
one leg type**, carrying the latest effective `company_cd`, `direction_ind`,
`operating_airline_cd`, `operating_flgt_no`, and `operating_sfx_cd` for that
flight on that leg.

---

## 2. Clause-by-clause walk-through

The fixed SQL contains **three structurally identical `INSERT … EXCEPT`
statements**, one per leg type. They differ only in the joined leg table and its
join keys. The walk-through below describes Branch 1 (marketing) in full, then
notes the deltas for Branches 2 and 3.

### Branch 1 — marketing leg (`synthetic_mkg_flgt_leg`)

- **`INSERT INTO staging.wrk_target ( … )`** — explicit 8-column target list
  (`airline_cd, flgt_no, flgt_dt, company_cd, direction_ind,
  operating_airline_cd, operating_flgt_no, operating_sfx_cd`). The buggy input
  had **no** target column list, binding positionally to an unknown physical
  order. The explicit list makes the `EXCEPT SELECT *` positional match
  unambiguous. The assumed order matches the buggy input's SELECT projection
  order and is flagged `TODO(SME)` pending target DDL.
- **`SELECT src.airline_cd, src.flgt_no, src.flgt_dt`** — the flight identity
  keys, passed through unchanged from `synthetic_flgt_source`.
- **`SUBSTR(MAX(src.effective_dt || leg.<attr>), 11, N) AS <attr>`** (×5) — the
  **latest-value trick**. For each flight, concatenate the sortable
  `effective_dt` key with the attribute value, take `MAX` over the group (which
  selects the row with the greatest `effective_dt`), then `SUBSTR` from position
  11 onward to strip the date key and recover the winning attribute value. This
  collapses multiple effective-dated rows per flight into one row carrying the
  newest attributes. Correctness depends on `effective_dt` being a fixed-width,
  lexicographically sortable string — flagged `TODO(SME)` (SEM-02 / FN-LATEST).
- **`FROM synthetic_flgt_source src JOIN synthetic_mkg_flgt_leg leg`** — joins
  the source flight to its **marketing** leg on
  `airline_cd = marketing_airline_cd`, `flgt_no = marketing_flgt_no`,
  `flgt_dt = gmt_flgt_dt`. Join-key direction is plausible from names but
  unverifiable without Teradata ground truth — flagged `TODO(SME)` (SEM-10).
- **`WHERE leg.dep_stn_cd <> leg.arr_stn_cd`** — drops self-loops (a leg whose
  departure and arrival stations are the same).
- **`AND src.flgt_dt > (SELECT param_value FROM synthetic_sys_param WHERE param_id = 'UPDATE_CUTOFF')`**
  — only loads flights newer than the configured cutoff. `param_value` is
  implicitly cast string→date; Snowflake's strict casting may error or mismatch
  depending on the stored format — flagged `TODO(SME)` (SEM-06 / DTX-10).
- **`GROUP BY src.airline_cd, src.flgt_no, src.flgt_dt`** — one output row per
  flight; the `MAX` aggregates resolve the latest attributes within each group.
- **`EXCEPT SELECT * FROM staging.wrk_target`** — the **SET-table dedup**. Only
  rows not already present in the target (full-row equality) are inserted,
  reproducing Teradata SET semantics. This is the critical SEM-05 fix.

### Branch 2 — operational leg (`synthetic_operational_flgt_leg`)

Identical structure to Branch 1, but joins `synthetic_operational_flgt_leg leg`
on `airline_cd = operating_airline_cd`, `flgt_no = operating_flgt_no`,
`flgt_dt = gmt_flgt_dt`. Same `WHERE`, `GROUP BY`, and `EXCEPT` dedup against the
target.

### Branch 3 — codeshare leg (`synthetic_codeshare_flgt_leg`)

Identical structure, but joins `synthetic_codeshare_flgt_leg cs` on
`airline_cd = codeshare_airline_cd`, `flgt_no = codeshare_flgt_no`,
`flgt_dt = gmt_flgt_dt`. Same `WHERE`, `GROUP BY`, and `EXCEPT` dedup against the
target.

### What the buggy input would have done instead

The buggy input was a **single** `INSERT INTO staging.wrk_target` followed by
three `SELECT … UNION … SELECT … UNION … SELECT` branches (no `EXCEPT`, no
explicit column list). That shape is wrong in two ways:

1. **Wrong dedup axis.** `UNION` (not `UNION ALL`) de-duplicates **across** the
   three branches — a marketing-leg row and a codeshare-leg row that happen to be
   identical would collapse to one. In Teradata the three INSERTs were
   independent; each was deduped **against the target's existing rows** (SET
   semantics), never against each other.
2. **Re-inserts existing rows.** Even with `UNION ALL`, a plain `INSERT` would
   re-insert rows already present in the target, violating SET-table "drop rows
   already present" semantics. Teradata's SET table silently drops full-row
   duplicates on INSERT; Snowflake's default `CREATE TABLE` keeps them.

The fixed SQL restores the intended semantics by splitting into three
independent `INSERT … EXCEPT SELECT * FROM staging.wrk_target` statements and
removing the `UNION` operators entirely.

---

## 3. Semantic checks table

| SEM ID | Risk | Present? | Corrected how? | Equivalent to Teradata? |
|---|---|---|---|---|
| **SEM-05** | SET-table dedup | **Yes — confirmed** | Split the single `INSERT … UNION … UNION` into 3 independent `INSERT INTO staging.wrk_target (col list) (SELECT … EXCEPT SELECT * FROM staging.wrk_target)` statements; removed `UNION`; added explicit 8-column target list. | **Yes** (reviewer-confirmed SET; `EXCEPT` reproduces "drop rows already present"). Target column order is `TODO(SME)` pending DDL. |
| SEM-02 | Dedup / `MAX` ordering (FN-LATEST) | Yes | No SQL change — flagged `TODO(SME)`. The `SUBSTR(MAX(effective_dt \|\| <val>), 11, N)` trick assumes `effective_dt` is a fixed-width, lexicographically sortable string. If it is `DATE`/`TIMESTAMP`, Snowflake's implicit cast may not be zero-padded, so `MAX` can pick the wrong row. Candidate fix: `TO_CHAR(src.effective_dt,'YYYY-MM-DD') \|\| <val>`. | **SME** — pending DDL / data-type confirmation. |
| SEM-03 | `CHAR(n)` padding & comparison | Maybe | No SQL change — flagged `TODO(SME)`. Join/`EXCEPT` keys (`airline_cd`, `flgt_no`, `company_cd`, `*_stn_cd`, etc.) may be `CHAR(n)`. Teradata blank-pads and ignores trailing spaces in `=`; Snowflake does not, so join/`EXCEPT` matching can drift. Candidate fix: `TRIM`/`RTRIM` on keys. | **SME** — pending DDL. |
| SEM-04 | Timestamp / timezone | Maybe | No SQL change — flagged `TODO(SME)`. `flgt_dt` / `gmt_flgt_dt` / `effective_dt` may be `TIMESTAMP` vs `TIMESTAMP_TZ` vs `DATE`; an NTZ/TZ mismatch shifts values. | **SME** — pending DDL. |
| SEM-06 | Implicit cast / NULL in comparison | Yes | No SQL change — flagged `TODO(SME)`. `src.flgt_dt > (SELECT param_value …)` is an implicit string→date cast; `effective_dt \|\| <val>` is an implicit date→string cast. Both depend on session defaults / stored format. Candidate fix: `TO_DATE(param_value, '<fmt>')` and `TO_CHAR(effective_dt, 'YYYY-MM-DD')`. | **SME** — pending DDL / format confirmation. |
| SEM-10 | Lookup join direction | Maybe | No SQL change — flagged `TODO(SME)`. The three branches join marketing / operational / codeshare leg tables; join-key direction is plausible from names but unverifiable without Teradata ground truth. | **SME** — pending ground-truth spot-check. |
| SEM-01 | Integer division | No | n/a — no `/` division present. | n/a |
| SEM-07 | `NULL` ordering | No | n/a — no `ORDER BY` feeding `QUALIFY`/`TOP`; `MAX` ignores NULLs by default. | n/a |
| SEM-08 | Empty string vs NULL | No | n/a — no `''` / `NULLIF(x,'')` present. | n/a |
| SEM-09 | Aggregate of empty set | No | n/a — `MAX` over an empty group returns NULL by design; no downstream division depends on it. | n/a |

---

## 4. Divergences from the original

There is no Teradata ground-truth file, so "the original" here means the **buggy
Snowflake input**. The fixed SQL intentionally diverges from it in these ways:

1. **Three independent `INSERT … EXCEPT` statements replace one
   `INSERT … UNION … UNION`.** This is the SEM-05 fix. The buggy input's
   cross-branch `UNION` dedup and lack of `EXCEPT` against the target both
   violated Teradata SET-table semantics. The fixed SQL restores per-branch
   dedup against the target's existing rows. This is **intentional and
   reviewer-confirmed**, not a bit-identical port.
2. **Explicit 8-column `INSERT` target list added.** The buggy input bound
   positionally to an unknown physical column order. The explicit list makes
   the `EXCEPT SELECT *` positional match unambiguous. The assumed order
   (`airline_cd, flgt_no, flgt_dt, company_cd, direction_ind,
   operating_airline_cd, operating_flgt_no, operating_sfx_cd`) matches the
   buggy input's SELECT projection order and is flagged `TODO(SME)` pending
   target DDL.
3. **No other changes.** Column order within each SELECT, JOIN keys, CASE
   branches (none present), `WHERE` predicates, `GROUP BY` keys, and the
   `SUBSTR(MAX(...), 11, N)` latest-value trick are all preserved exactly from
   the buggy input. Formatting and comments are preserved where no rule forced
   a change.

---

## 5. Open SME questions

Each `TODO(SME)` below is a decision for a human reviewer. None blocks
compilation; all block final semantic sign-off.

1. **SEM-05 (sub) — target column order.** Is the assumed
   `airline_cd, flgt_no, flgt_dt, company_cd, direction_ind,
   operating_airline_cd, operating_flgt_no, operating_sfx_cd` order the actual
   physical column order of `staging.wrk_target`? If not, the explicit `INSERT`
   column list and the `EXCEPT SELECT *` positional match must be reordered to
   match the target DDL. **Decision needed:** confirm or correct the column
   order against `staging.wrk_target` DDL.
2. **SEM-02 / FN-LATEST — `effective_dt` sortability.** Is `effective_dt` a
   fixed-width, lexicographically sortable string (e.g. `YYYY-MM-DD`)? If it is
   `DATE`/`TIMESTAMP`, the `MAX(effective_dt || <val>)` trick can pick the wrong
   row because Snowflake's implicit cast may not be zero-padded. **Decision
   needed:** confirm `effective_dt` data type; if not a sortable string, apply
   `TO_CHAR(src.effective_dt,'YYYY-MM-DD') || <val>` (and adjust the `SUBSTR`
   offset accordingly).
3. **SEM-06 / DTX-10 — `param_value` cast.** Is `param_value` a `VARCHAR`
   holding a date in a known format, and is `flgt_dt` a `DATE`? If so, the
   implicit `src.flgt_dt > (SELECT param_value …)` cast may error or mismatch on
   Snowflake. **Decision needed:** confirm types and stored format; if needed,
   wrap as `TO_DATE(param_value, '<fmt>')`. The same question applies to the
   `effective_dt || <val>` implicit date→string cast.
4. **SEM-03 — `CHAR(n)` padding.** Are any of the join/`EXCEPT` keys
   (`airline_cd`, `flgt_no`, `company_cd`, `*_stn_cd`, `operating_*`) declared
   `CHAR(n)` in source or target? If so, Teradata blank-pads and ignores
   trailing spaces in `=`, while Snowflake does not, so join/`EXCEPT` matching
   can drift. **Decision needed:** confirm key column types; if `CHAR(n)`, wrap
   keys in `TRIM`/`RTRIM`.
5. **SEM-04 — timestamp/timezone.** Are `flgt_dt`, `gmt_flgt_dt`, and
   `effective_dt` `TIMESTAMP`, `TIMESTAMP_TZ`, or `DATE`? An NTZ/TZ mismatch
   shifts values. **Decision needed:** confirm timestamp types and session
   `TIMEZONE`; pin types to match the source.
6. **SEM-10 — join-key direction.** Are the marketing / operational / codeshare
   join keys (`marketing_airline_cd`/`marketing_flgt_no`,
   `operating_airline_cd`/`operating_flgt_no`,
   `codeshare_airline_cd`/`codeshare_flgt_no`) the correct sides of each join
   relative to `synthetic_flgt_source`? **Decision needed:** spot-check against
   Teradata ground truth (or source DDL) that each branch joins on the intended
   keys.

---

## 6. Inline anchors

```anchors
MATCH INSERT INTO staging.wrk_target :: SEM-05 ▸ SET-table dedup: 3 independent INSERT…EXCEPT statements replace the buggy single INSERT…UNION…UNION. Each branch dedups against the target's existing rows (EXCEPT SELECT *), reproducing Teradata SET semantics. Reviewer-confirmed SET.
MATCH SUBSTR(MAX(src.effective_dt || leg.company_cd), 11, 99) :: SEM-02 / FN-LATEST ▸ Latest-value trick: MAX(effective_dt || value) picks the newest effective row, then SUBSTR strips the date key. Correctness assumes effective_dt is a fixed-width sortable string — TODO(SME) pending DDL.
MATCH src.airline_cd = leg.marketing_airline_cd :: SEM-10 ▸ Marketing-leg join direction is plausible from names but unverifiable without Teradata ground truth — TODO(SME).
MATCH src.airline_cd = leg.operating_airline_cd :: SEM-10 ▸ Operational-leg join direction is plausible from names but unverifiable without Teradata ground truth — TODO(SME).
MATCH src.airline_cd = cs.codeshare_airline_cd :: SEM-10 ▸ Codeshare-leg join direction is plausible from names but unverifiable without Teradata ground truth — TODO(SME).
MATCH src.flgt_dt > ( :: SEM-06 / DTX-10 ▸ Implicit param_value string→date cast; Snowflake strict casting may error/mismatch depending on stored format. Candidate fix: TO_DATE(param_value,'<fmt>') — TODO(SME).
MATCH WHERE param_id = 'UPDATE_CUTOFF' :: SEM-06 ▸ Cutoff parameter lookup; param_value type/format unconfirmed — TODO(SME).
MATCH EXCEPT :: SEM-05 ▸ EXCEPT SELECT * FROM staging.wrk_target dedups each branch against existing target rows, restoring Teradata SET-table "drop rows already present" semantics.
MATCH leg.dep_stn_cd <> leg.arr_stn_cd :: Self-loop filter: drops legs whose departure and arrival stations are identical.
MATCH GROUP BY :: One output row per (airline_cd, flgt_no, flgt_dt); MAX aggregates resolve the latest effective attributes within each flight group.
```