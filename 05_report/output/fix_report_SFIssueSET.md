# Stage 5 — Fix Report: `SFIssueSET.sql`

**Unit:** `SFIssueSET.sql`
**Input:** `00_input/SFIssueSET.sql`
**Fixed file:** `03_fix/output/SFIssueSET_fixed.sql`
**Analysis:** `01_analyze/output/analysis_SFIssueSET.md`
**Validation:** `04_validate/output/validation_SFIssueSET.md`
**Teradata ground truth:** none supplied (no `00_input/SFIssueSET.teradata.sql`).
**Reviewer guidance:** `staging.wrk_target` confirmed as a **SET table** per
`02_rules/06_lessons_learned.md` (reviewer verbatim: *"This is a SET table in
teradata. So, there should not be any duplicates. You need to handle the dedup
logic in the query."*). This closes the SEM-05 SME question and moves it to FIX.
**Date:** 2026-07-27.

---

## 1. Input summary

A single `INSERT INTO staging.wrk_target` (line 1, no explicit target column
list) followed by a 3-branch `UNION` (lines 30, 60). Each branch joins
`synthetic_flgt_source` to one of three leg tables (marketing / operational /
codeshare), aggregates with the `SUBSTR(MAX(effective_dt || val), 11, N)`
"latest-value trick", and filters by a scalar `param_value` subquery. The
target `staging.wrk_target` is a **SET table** (reviewer-confirmed). The buggy
Snowflake collapses three independent Teradata INSERTs into one
`INSERT … UNION … UNION`, which (a) re-inserts rows already present in the
target and (b) de-duplicates **across** branches via `UNION` — the wrong dedup
axis for a SET table.

- **Statement shape:** 1 INSERT (buggy) → 3 INSERTs (fixed).
- **Columns per branch:** 8 (identical projection order across all 3 branches).
- **Column-count check:** 8 = 8 per branch — no DEF-05.

---

## 2. Findings by class

| Class | Count | Findings |
|---|---|---|
| **AUTO** | 0 | — |
| **FIX** | 1 | SEM-05 SET-table dedup split (reviewer-confirmed SET) |
| **SME** | 6 | SEM-02/FN-LATEST key width; SEM-06/DTX-10 implicit `param_value` cast; SEM-03 `CHAR(n)` padding; SEM-04 TZ; SEM-10 join-key direction; SEM-05(sub) target column order |
| **KEEP** | 0 | `.sql` input — no SNZ constructs |

---

## 3. Fixes applied (rule IDs + line numbers)

| Rule | Source line(s) | Change |
|---|---|---|
| **SEM-05** | 1, 32, 64 | Split the single `INSERT … UNION … UNION` into 3 independent `INSERT INTO staging.wrk_target (airline_cd, flgt_no, flgt_dt, company_cd, direction_ind, operating_airline_cd, operating_flgt_no, operating_sfx_cd) ( SELECT … EXCEPT SELECT * FROM staging.wrk_target )` statements. `UNION` operators removed entirely. Explicit 8-column INSERT target list added so the `EXCEPT SELECT *` positional match is unambiguous. Reviewer source: `02_rules/06_lessons_learned.md` (SET-table confirmation). |

No syntax (SFX/FNX/DTX) or defect (DEF) fixes were required — the input parsed
clean on Snowflake with 0 residual-Teradata constructs. The only change is the
SEM-05 SET-table dedup split.

---

## 4. Defects repaired

None. No DEF-* defect fired (no duplicate columns, no count mismatch, no
malformed calls, no alias defects). The single repair is a semantic-equivalence
fix (SEM-05), not a defect repair.

---

## 5. Open `TODO(SME)` items

8 `TODO(SME)` markers carried forward (all blocked on missing DDL / Teradata
ground truth):

1. **SEM-05(sub)** — target column order unknown (no DDL); confirm the explicit
   INSERT list matches the physical column order.
2. **SEM-02/FN-LATEST** — `SUBSTR(MAX(effective_dt || val), 11, N)` needs a
   fixed-width, lexicographically sortable key (×3 branches).
3. **SEM-06/DTX-10** — `param_value` implicit string→date cast in the scalar
   subquery comparison (×3 branches).
4. **SEM-03** — `operating_airline_cd` uses `SUBSTR(…,11,3)` (width 3) while
   all other values use `SUBSTR(…,11,99)`; confirm declared width.
5. **SEM-04** — `flgt_dt` / `gmt_flgt_dt` / `effective_dt` TIMESTAMP vs
   TIMESTAMP_TZ vs DATE; confirm to pin NTZ/TZ.
6. **SEM-10** — join-key direction (marketing/operational/codeshare); confirm
   against Teradata ground truth.

---

## 6. Validation result

- **Fixed file:** `python3 04_validate/validate.py 03_fix/output/SFIssueSET_fixed.sql`
  → **PASS**. 3 statements parsed; 8 = 8 columns ×3; no duplicate INSERT
  columns; no residual Teradata constructs; 8 `TODO(SME)` markers outstanding.
- **Control (buggy input):** `python3 04_validate/validate.py 00_input/SFIssueSET.sql`
  → **PASS** (1 statement, no residual Teradata, 0 TODO markers). **This control
  PASS is EXPECTED** — the defect is purely semantic (SEM-05 SET-table dedup);
  the buggy `INSERT … UNION … UNION` parses perfectly. The mechanical validator
  cannot detect a SET-table dedup violation without the target DDL. Per the
  standing lesson (*"A parse PASS is not correctness"*), the decisive evidence
  is the SEM-05 inventory and the reviewer's SET-table confirmation, not the
  control's mechanical result. **Not a re-fix trigger.**

---

## 7. Residual-construct count

**0.** No residual Teradata constructs (`ZEROIFNULL`, `CONTAINS`, `MULTISET`,
`(+)`, BTEQ dot-commands, `MINUS`, `SEL`, …) in the fixed file.

---

## 8. Open `TODO(SME)` count

**8.**

---

## 9. Sign-off checklist

- [x] 3 INSERT statements preserved; each writes 8 columns to the target.
- [x] INSERT column order matches SELECT expression order in all 3 statements.
- [x] No duplicate INSERT columns.
- [x] No residual Teradata constructs.
- [x] `QUALIFY` (none present) — n/a.
- [x] JOIN keys and CASE-branch order preserved exactly.
- [x] SEM-05 fix applied per reviewer-confirmed SET-table fact; reviewer source
      recorded in the FIX LOG.
- [x] 8 `TODO(SME)` markers carried forward for reviewer sign-off.
- [x] Validation PASS; control PASS expected (semantic-only).

**Verdict: PASS — ready for reviewer sign-off.** The single SEM-05 fix is
auditable to the reviewer's SET-table confirmation; the 6 open SME items are
all blocked on missing DDL / Teradata ground truth and must not be rewritten
without reviewer confirmation. See the Stage-6 semantic doc
`06_explain/output/semantic_SFIssueSET.md` for the clause-by-clause walk-through.