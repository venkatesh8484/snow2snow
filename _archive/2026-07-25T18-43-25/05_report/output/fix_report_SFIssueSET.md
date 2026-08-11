# Fix Report — `SFIssueSET.sql`

**Unit:** `SFIssueSET` (Snowflake → Snowflake remediation)
**Input:** `00_input/SFIssueSET.sql` (94 lines)
**Fixed:** `03_fix/output/SFIssueSET_fixed.sql`
**Teradata ground truth:** none (no `SFIssueSET.teradata.sql` in `00_input/`)
**Date:** 2026-07-24 (re-run after reviewer SET confirmation)
**Stage:** 5 — Report & Learn

---

## 1. Summary

`SFIssueSET.sql` is a single `INSERT INTO staging.wrk_target` whose body is a
three-branch `SELECT … UNION … SELECT … UNION … SELECT`. Each branch joins the
common flight source `synthetic_flgt_source` (`src`) to a different leg table
(marketing / operational / codeshare), filters on
`dep_stn_cd <> arr_stn_cd` and `flgt_dt > UPDATE_CUTOFF` system parameter, groups
by `(airline_cd, flgt_no, flgt_dt)`, and uses the latest-value trick
`SUBSTR(MAX(effective_dt || val), 11, N)` to pick the most-recently-effective
value for each descriptive attribute. The file is parse-clean Snowflake with no
residual Teradata constructs and a balanced 8=8 INSERT/SELECT column count per
branch. The **single decisive fix** is **SEM-05 (SET-table dedup, confirmed by
the reviewer)**: the single `INSERT … UNION … UNION` was split into 3
independent `INSERT INTO staging.wrk_target (8-col list) (SELECT … EXCEPT
SELECT * FROM staging.wrk_target)` statements, with an explicit INSERT column
list added to make the `EXCEPT` positional match unambiguous. Four semantic
questions (latest-value fixed-width key, MAX tie-break, `param_value` implicit
cast, `operating_airline_cd` width-3) remain flagged `TODO(SME)` for human
review — none is mechanically resolvable without DDL or ground truth.
Validation: **PASS** (3 statements, all compile, 8=8 columns each, no residual
Teradata; control PASS — expected for a purely semantic bug).

---

## 2. Reviewer guidance

**Source:** `07_review/output/review_SFIssueSET.md`

> *"This is a SET table in teradata. So, there should not be any duplicates. You need to handle the dedup logic in the query."*

**How it was resolved:** The reviewer's comment answered the SEM-05 SME
question ("Is `staging.wrk_target` a SET table?") that had been left open in
the prior run. SEM-05 moved from `SME` → **`FIX`**. The fix was applied in Stage 3
(`03_fix/output/SFIssueSET_fixed.sql`): the single `INSERT … UNION … UNION`
was split into 3 independent `INSERT INTO staging.wrk_target (col1, …, col8)
(SELECT … EXCEPT SELECT * FROM staging.wrk_target)` statements. The `UNION`
operators were removed entirely, and an explicit INSERT column list was added
to each statement so the `EXCEPT SELECT * FROM staging.wrk_target` positional
match is unambiguous. This reproduces Teradata SET-table dedup semantics on
Snowflake: each branch is deduped against the target independently, and rows
already present in the target are not re-inserted.

---

## 3. Rules applied

### Syntax (SFX / FNX / DTX)

| Rule | Count | Detail |
|---|---|---|
| — | 0 | No syntax, function, or datatype fixes required. The input is clean Snowflake — 0 residual-Teradata constructs. |

### Defects (DEF)

| Rule | Count | Detail |
|---|---|---|
| — | 0 | No structural defects. Column count is 8=8 per branch; UNION-consistent; no duplicate INSERT columns; paren-balanced. |

### Semantic (SEM)

| Rule | Count | Class | Detail |
|---|---|---|---|
| **SEM-05** (SET-table dedup) | 1 | **FIX** | Reviewer confirmed `staging.wrk_target` is a SET table. Split the single `INSERT … UNION … UNION` into 3 independent `INSERT INTO staging.wrk_target (col list) (SELECT … EXCEPT SELECT * FROM staging.wrk_target)` statements. Added explicit INSERT column list. Removed `UNION` operators. |
| **SEM-02 / FN-LATEST** (latest-value fixed-width key) | 1 | TODO(SME) | `SUBSTR(MAX(effective_dt || val), 11, N)` needs a fixed-width, lexicographically sortable key. Confirm `effective_dt` type and value display widths; correct pattern is `TO_CHAR(effective_dt,'YYYY-MM-DD') || LPAD(val::VARCHAR, N, ' ')` before `MAX`. |
| **SEM-02** (MAX tie-break) | 1 | TODO(SME) | If two rows share the same `effective_dt` (and the value is not fixed-width), `MAX` can pick the wrong row. Resolved together with the fixed-width key above. |
| **SEM-06 / DTX-10** (param_value implicit cast) | 1 | TODO(SME) | `src.flgt_dt > (SELECT param_value …)` compares a date to a string; relies on implicit string→date cast. Confirm `param_value` format; make cast explicit (`TO_DATE(param_value,'YYYY-MM-DD')`). |
| **SEM-03** (operating_airline_cd width-3) | 1 | TODO(SME) | `operating_airline_cd` uses `SUBSTR(…, 11, 3)` while all other values use `SUBSTR(…, 11, 99)`. Confirm the declared width of `operating_airline_cd` in the source DDL. |

**Totals:** 1 semantic FIX (SEM-05) + 4 semantic SME questions
(8 inline `TODO(SME)` markers outstanding — SEM-05 target column order ×3,
SEM-02/FN-LATEST ×3, SEM-06/DTX-10 ×3, SEM-03 ×3; some markers are shared across
the 3 branches).

---

## 4. Defects repaired

No structural defects (DEF-*) were repaired. The SEM-05 SET-table split is a
**semantic** fix, not a defect repair. The input had no duplicate INSERT
columns, no column-count mismatch (8=8 per branch), no unbalanced parens, and
no residual Teradata constructs.

| # | Rule | Lines (fixed) | Before | After | Class | Data change? |
|---|---|---|---|---|---|---|
| S1 | SEM-05 | 1, 32, 64 | Single `INSERT INTO staging.wrk_target SELECT … UNION … SELECT … UNION … SELECT` | 3 independent `INSERT INTO staging.wrk_target (col1,…,col8) (SELECT … EXCEPT SELECT * FROM staging.wrk_target)` | FIX | **Yes** — reproduces Teradata SET-table dedup: each branch is deduped against the target independently; rows already present are not re-inserted. `UNION` cross-branch dedup removed. |

---

## 5. Open `TODO(SME)` items

Eight inline markers carried forward for human review (no mechanical fix
possible without DDL/ground truth). Each appears in all 3 branches unless
noted:

1. **SEM-05 — Target column order.** Confirm the explicit INSERT column list
   `(airline_cd, flgt_no, flgt_dt, company_cd, direction_ind,
   operating_airline_cd, operating_flgt_no, operating_sfx_cd)` matches the
   physical column order of `staging.wrk_target`. No DDL was supplied; the list
   was inferred from the SELECT expression order. The `EXCEPT SELECT * FROM
   staging.wrk_target` clause depends on this match being exact.
2. **SEM-02 / FN-LATEST — Latest-value fixed-width key.** Is `src.effective_dt`
   a DATE or a TIMESTAMP, and what are the max display widths of the
   concatenated value columns? The latest-value trick needs a fixed-width key —
   format as `TO_CHAR(effective_dt,'YYYY-MM-DD') || LPAD(val::VARCHAR, N, ' ')`
   before `MAX`. Confirm the type and the per-column `N` for `LPAD`.
3. **SEM-02 — MAX tie-break.** Is `effective_dt` unique per
   `(airline_cd, flgt_no, flgt_dt)` group, or can ties occur? If ties are
   possible, `MAX(effective_dt || val)` picks the lexicographically larger
   *value*, not necessarily the intended row; a deterministic tie-break is
   needed.
4. **SEM-06 / DTX-10 — param_value implicit cast.** Is
   `synthetic_sys_param.param_value` a date-formatted string (e.g.
   `YYYY-MM-DD`)? Should the comparison be
   `src.flgt_dt > TO_DATE(param_value, 'YYYY-MM-DD')` to make the cast explicit
   and avoid Snowflake's stricter implicit-cast behaviour?
5. **SEM-03 — operating_airline_cd width-3.** Is the width-3 truncation on
   `operating_airline_cd` (`SUBSTR(…, 11, 3)`) intentional? All other value
   columns use `SUBSTR(…, 11, 99)`. Likely intentional (airline codes are 2–3
   chars) but unconfirmable without the source DDL.

---

## 6. Validation result

**Verdict: ✅ PASS**

| Check | Fixed file | Control (buggy input) |
|---|---|---|
| Snowflake connection probe | PASS | PASS |
| Parse (sqlglot, snowflake dialect) | PASS — 3 statements | PASS — 1 statement |
| Snowflake EXPLAIN (live compile) | PASS | PASS |
| INSERT columns == SELECT expressions | PASS — 8 == 8 (×3) | PASS — 8 == 8 (×3 branches) |
| No duplicate INSERT columns | PASS | PASS |
| No residual Teradata constructs | PASS | PASS |
| `TODO(SME)` markers outstanding | 8 | 0 |
| **RESULT** | **PASS** | **PASS** |

**Control PASS — expected, not a re-fix trigger.** The bug in the delivered
file is purely **semantic** (SET-table dedup semantics), not syntactic. The
single `INSERT … UNION … UNION` parses and EXPLAIN-compiles cleanly on
Snowflake — the mechanical validator has no rule that detects a SET-table
dedup violation without the target DDL. This is the documented behavior for
semantic-only defects: *"A parse PASS is not correctness."* The decisive
evidence is the SEM-05 inventory and the reviewer's SET-table confirmation, not
the control's mechanical result. No hand-back to s2s-fix is warranted.

Manual spot-checks (all PASS): 3 independent INSERT statements (one per
branch), explicit column list present and identical across all 3, `EXCEPT
SELECT * FROM staging.wrk_target` present in all 3, `UNION` operators removed,
JOIN keys preserved per branch (marketing / operational / codeshare), GROUP BY
grain unchanged `(airline_cd, flgt_no, flgt_dt)`, latest-value trick
preserved verbatim, WHERE filters intact, no residual Teradata functions or
operators, `TODO(SME)` markers present.

---

## 7. Sign-off checklist

A reviewer can sign off from this document alone. Confirm each item:

- [x] **Column count balanced** — 8 INSERT == 8 SELECT per branch (Stage 1 + Stage 4).
- [x] **No residual Teradata constructs** — validator + grep clean.
- [x] **JOIN keys preserved** — all 3 branch join keys (marketing / operational / codeshare) unchanged.
- [x] **GROUP BY grain preserved** — `(airline_cd, flgt_no, flgt_dt)` unchanged.
- [x] **Latest-value trick preserved** — `SUBSTR(MAX(effective_dt || val), 11, N)` unchanged in all 3 branches.
- [x] **WHERE filters preserved** — `dep_stn_cd <> arr_stn_cd` and `flgt_dt > UPDATE_CUTOFF` intact.
- [x] **SEM-05 SET-table fix applied** — single `INSERT … UNION … UNION` split into 3 independent `INSERT … EXCEPT` statements; explicit column list added; `UNION` removed.
- [x] **Minimal diff** — only the INSERT structure changed (split + column list + EXCEPT); SELECT bodies are byte-for-byte unchanged.
- [x] **Validation PASS** — fixed file parses, EXPLAIN-compiles, count-balanced, no duplicates, no residual Teradata.
- [x] **Control explained** — buggy input PASSes because the bug is semantic (SET-table dedup), not syntactic; not a re-fix trigger.
- [x] **Semantic risks flagged** — 4 SME questions (SEM-02/FN-LATEST, SEM-02 tie-break, SEM-06/DTX-10, SEM-03 width) carried as `TODO(SME)` for human review.
- [x] **No ground truth** — no `SFIssueSET.teradata.sql`; every semantic inference is flagged, none silently applied.
- [ ] **SME sign-off** — reviewer resolves the 8 `TODO(SME)` items above (target column order, fixed-width key, MAX tie-break, param_value cast, operating_airline_cd width). Until then the semantic intent is unconfirmed.

**Stage 5 complete.** Semantic account lives in Stage 6
(`06_explain/output/semantic_SFIssueSET.md`; archived copy:
`_archive/2026-07-24T21-48-55/06_explain/output/semantic_SFIssueSET.md`); this
report does not duplicate it.