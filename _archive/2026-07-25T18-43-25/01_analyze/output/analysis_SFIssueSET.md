# Stage 1 — Analysis: SFIssueSET.sql

**Input:** `00_input/SFIssueSET.sql`
**Teradata ground truth:** none (no `00_input/SFIssueSET.teradata.sql`).
**Reviewer guidance:** `07_review/output/review_SFIssueSET.md` — **authoritative**.
**Date:** 2026-07-24 (re-analysis after reviewer confirmation).

---

## 0. Reviewer guidance (authoritative — changes this analysis)

> *"This is a SET table in teradata. So, there should not be any duplicates. You need to handle the dedup logic in the query."*
> — `07_review/output/review_SFIssueSET.md`

**Effect on this analysis:** The SEM-05 SET-table question is now **ANSWERED**.
`staging.wrk_target` is confirmed to be a **SET table**. Per SEM-05, the finding
moves from `SME` → **`FIX`**: the single `INSERT … UNION … UNION` must be split
into 3 independent `INSERT INTO staging.wrk_target ( SELECT … EXCEPT SELECT *
FROM staging.wrk_target )` statements. This is the single decisive change from
the prior run.

---

## 1. Column-count check

| Item | Count | Notes |
|---|---|---|
| INSERT target column list | **0 (implicit)** | `INSERT INTO staging.wrk_target` has no explicit column list — binding is positional to the target table's column order. |
| SELECT expressions per branch | **8** | `airline_cd, flgt_no, flgt_dt, company_cd, direction_ind, operating_airline_cd, operating_flgt_no, operating_sfx_cd` |
| Branches | **3** | Branch 1 (lines 2–30, `synthetic_mkg_flgt_leg`), Branch 2 (lines 34–62, `synthetic_operational_flgt_leg`), Branch 3 (lines 66–94, `synthetic_codeshare_flgt_leg`) |
| UNION consistency | **OK** | All 3 branches expose the same 8 expressions in the same order with the same aliases. |
| Duplicates (INSERT side) | none | No explicit list. |
| Duplicates (SELECT side) | none | 8 distinct expressions per branch. |
| Net | **8 = 8** | No DEF-05 column-count mismatch. |

**SET-table confirmation:** Reviewer confirms `staging.wrk_target` is a SET
table. This is recorded here because the column-count check is where SET
semantics first bite — a SET table silently drops full-row duplicates on insert,
so the *effective* row count after the INSERT depends on what is already in the
target, not just on the SELECT expression count.

---

## 2. Syntax errors / residual-Teradata constructs

The file **parses clean** on Snowflake. No residual Teradata constructs are
present. Specifically scanned and **not found**:

| Rule | Construct | Present? |
|---|---|---|
| SFX-01 | `PERIOD … CONTAINS` | No |
| SFX-03 | `QUALIFY` (keep) | N/A — none present |
| SFX-04 | `SEL` | No |
| SFX-05 | `CREATE SET/MULTISET TABLE` | No (INSERT-only script; no DDL) |
| SFX-06 | `PRIMARY INDEX` | No |
| SFX-07 | `COLLECT STATS` | No |
| SFX-08 | BTEQ dot-commands | No |
| SFX-09 | `LOCKING ROW FOR ACCESS` | No |
| SFX-10 | `(+)` outer joins | No |
| SFX-11 | Unbalanced parens | No |
| SFX-12 | Trailing/missing comma | No |
| SFX-13 | `TOP n` | No |
| SFX-14 | `MINUS` | No — uses `UNION` (Snowflake-legal) |
| SFX-15 | `CAST … FORMAT` | No |
| FNX-01 | `ZEROIFNULL` | No |
| FNX-03 | date±int arithmetic | No |
| FNX-08 | `CAST … FORMAT` | No |
| DTX-01..10 | Teradata types / `CHARACTER SET` / `INTERVAL` | No |

**Verdict:** 0 syntax errors, 0 residual-Teradata constructs. The file is
mechanically valid Snowflake. As the lessons-learned file states: *"A parse PASS
is not correctness."* All findings below are semantic.

---

## 3. Defects (DEF-*)

| Rule | Line | Finding | Class |
|---|---|---|---|
| DEF-01 | — | No duplicate INSERT columns (no explicit list). | — |
| DEF-05 | — | INSERT col count (8 implicit) = SELECT expr count (8) per branch; UNION-consistent. | — |
| DEF-02/03/04/06/07 | — | None observed. | — |

**Verdict:** 0 structural defects.

---

## 4. Semantic risks (SEM-*) — CRITICAL section

| # | Rule | Line(s) | Finding | Class | Detail |
|---|---|---|---|---|---|
| 1 | **SEM-05** | 1 (`INSERT INTO staging.wrk_target`) + `UNION` at 32, 64 | **SET-table dedup — CONFIRMED SET by reviewer.** The delivered file is a single `INSERT … UNION … UNION` writing 3 branches into one target. This is **wrong for a SET table**. | **FIX** | See §4.1 below. |
| 2 | SEM-02 / FN-LATEST | 5–10, 37–42, 69–74 | Latest-value trick `SUBSTR(MAX(src.effective_dt \|\| <val>), 11, …)` needs a **fixed-width, lexicographically sortable** key. `effective_dt \|\| val` is only safe if `effective_dt` is a fixed-width string and `val` is left-padded to a constant width. | SME | Confirm `effective_dt` type and the max width of each `val` column. Correct pattern: `TO_CHAR(effective_dt,'YYYY-MM-DD') \|\| LPAD(val::VARCHAR,n,' ')` before `MAX`. |
| 3 | SEM-02 | 5–10, 37–42, 69–74 | `MAX` tie-break non-determinism: if two rows share the same `effective_dt` (and the value is not fixed-width), `MAX` can pick the wrong row. | SME | Resolved together with #2 once widths are confirmed. |
| 4 | SEM-06 / DTX-10 | 22–27, 54–59, 86–91 | `src.flgt_dt > (SELECT param_value …)` — `param_value` is a string column compared to `flgt_dt` (a date). Relies on an implicit string→date cast. Snowflake is stricter than Teradata; this may error or silently mismatch. | SME | Confirm `param_value` format; make the cast explicit (`TO_DATE(param_value,'<fmt>')`). |
| 5 | SEM-03 (width consistency) | 7, 39, 71 | `operating_airline_cd` uses `SUBSTR(…, 11, 3)` (width 3) while all other values use `SUBSTR(…, 11, 99)`. If `operating_airline_cd` can exceed 3 chars, the width-3 slice truncates; if it is always ≤3, this is correct. | SME | Confirm the declared width of `operating_airline_cd` in the source DDL. |

### 4.1 SEM-05 — SET-table dedup (the decisive finding)

**Status:** CONFIRMED SET by reviewer (`07_review/output/review_SFIssueSET.md`).
**Class:** **FIX** (was `SME` in the prior run).

**What the current file does (wrong):**
A single `INSERT INTO staging.wrk_target` wraps three `SELECT … GROUP BY …`
branches with `UNION` (lines 32, 64). On a SET table this is incorrect in two
ways:

1. **`UNION` de-duplicates *across source branches*.** A Teradata SET table
   deduplicates a new row **against the rows already in the target**, not
   against rows from a sibling INSERT branch. `UNION` (not `UNION ALL`) silently
   collapses rows that two branches produce in common, so a row that branch 1
   and branch 3 both emit is inserted only once — but for the wrong reason
   (cross-branch dedup, not target-dedup). The original Teradata had three
   **independent** `INSERT` statements; each was deduped against the target
   independently.
2. **A single INSERT re-inserts rows already present in the target.** On a
   Teradata SET table, inserting a row that already exists is a silent no-op
   (the duplicate is dropped). The delivered Snowflake `INSERT … UNION` does
   **not** replicate that no-op: it inserts every row the UNION produces,
   including rows that are already in `staging.wrk_target`. On Snowflake (which
   has no SET-table dedup), this creates duplicates — the exact thing the
   reviewer flagged.

**Required fix (per SEM-05):** Port each independent INSERT branch as a
**separate** statement:

```sql
INSERT INTO staging.wrk_target
( SELECT <branch 1> EXCEPT SELECT * FROM staging.wrk_target );

INSERT INTO staging.wrk_target
( SELECT <branch 2> EXCEPT SELECT * FROM staging.wrk_target );

INSERT INTO staging.wrk_target
( SELECT <branch 3> EXCEPT SELECT * FROM staging.wrk_target );
```

Never merge separate SET-table INSERTs into a single `UNION`. The `EXCEPT
SELECT * FROM staging.wrk_target` clause reproduces the SET-table "drop rows
already present" semantics on Snowflake, and doing it per-branch preserves the
independent-dedup behavior of the original three Teradata INSERTs.

> **Note for Stage 3:** The `EXCEPT SELECT * FROM staging.wrk_target` form
> requires the target column order to match the SELECT order exactly. Since
> there is no explicit INSERT column list, Stage 3 should add an explicit
> column list to each `INSERT INTO staging.wrk_target (col1, …, col8)` to make
> the `EXCEPT` positional match unambiguous. Flag this as part of the SEM-05
> FIX, not a separate finding.

---

## 5. Classification summary

| Class | Count | Findings |
|---|---|---|
| AUTO | 0 | (file parses clean; no mechanical rule fires) |
| **FIX** | **1** | **SEM-05** — split the single `INSERT … UNION … UNION` into 3 independent `INSERT … EXCEPT SELECT * FROM staging.wrk_target` statements. |
| SME | 4 | SEM-02/FN-LATEST (fixed-width key), SEM-02 (MAX tie-break), SEM-06/DTX-10 (param_value cast), SEM-03 (operating_airline_cd width-3) |

**Change from prior run:** SEM-05 moved from `SME` → `FIX` due to the reviewer's
confirmation that `staging.wrk_target` is a SET table. All other findings are
unchanged. Prior run was 0 AUTO / 0 FIX / 5 SME; this run is 0 AUTO / 1 FIX / 4
SME.

---

## 6. Table dependency inventory

| Table | Role | Notes |
|---|---|---|
| `staging.wrk_target` | **Target (SET — confirmed)** | Reviewer confirms SET table. No DDL supplied; SET status comes from reviewer guidance. |
| `synthetic_flgt_source` | Source (`src`) | Joined in all 3 branches; provides `airline_cd, flgt_no, flgt_dt, effective_dt`. |
| `synthetic_mkg_flgt_leg` | Source (`leg`) | Branch 1 (marketing leg). |
| `synthetic_operational_flgt_leg` | Source (`leg`) | Branch 2 (operational leg). |
| `synthetic_codeshare_flgt_leg` | Source (`cs`) | Branch 3 (codeshare leg). |
| `synthetic_sys_param` | Source (scalar subquery) | `param_value` for `param_id = 'UPDATE_CUTOFF'`; implicit string→date cast risk (SEM-06/DTX-10). |

---

## 7. Reviewer guidance section

**Source:** `07_review/output/review_SFIssueSET.md`

> *"This is a SET table in teradata. So, there should not be any duplicates. You need to handle the dedup logic in the query."*

**How this changes the analysis:**

- **SEM-05** was previously classified `SME` because SET vs MULTISET cannot be
  decided from an INSERT-only script without the target's `CREATE TABLE` DDL
  (per the SEM-05 rule and the mode instructions: *"Never silently assume
  SET-table semantics"*). The reviewer's comment is the missing DDL
  confirmation.
- With SET confirmed, SEM-05 becomes a **FIX**: the single `INSERT … UNION …
  UNION` must be split into 3 independent `INSERT INTO staging.wrk_target
  ( SELECT … EXCEPT SELECT * FROM staging.wrk_target )` statements (§4.1).
- No other finding's classification changes. The four remaining SME items
  (fixed-width key, MAX tie-break, param_value cast, operating_airline_cd width)
  still require human confirmation of source DDL / data types.

---

## 8. One-line verdict

**Parse-clean, 0 mechanical fixes; 1 FIX (SEM-05 SET-table split — confirmed by
reviewer) and 4 open SME items (latest-value key width, MAX tie-break,
param_value cast, operating_airline_cd width).**