# Stage 5 — Fix Report: `SFissuetime.sql`

**Unit:** `SFissuetime.sql`
**Input:** `00_input/SFissuetime.sql` (139 lines)
**Fixed file:** `03_fix/output/SFissuetime_fixed.sql`
**Analysis:** `01_analyze/output/analysis_SFissuetime.md`
**Validation:** `04_validate/output/validation_SFissuetime.md`
**Teradata ground truth:** none supplied (no `SFissuetime.teradata.sql`).
**Reviewer guidance:** none — no `07_review/output/review_SFissuetime.md`.
**Date:** 2026-07-27.

---

## 1. Input summary

A single `INSERT INTO staging.wrk_synthetic_flgt_leg_ins_exp` (60 target
columns) `SELECT … FROM staging.wrk_synthetic_flgt_source1 o FULL OUTER JOIN
staging.wrk_synthetic_flgt_source2 n ON …`. The SELECT builds an SCD-2 old/new
diff: 30 `old_*` columns from `o`, 29 `new_*` columns from `n`, one synthesized
`TO_TIMESTAMP_LTZ(CONCAT(TO_DATE(o.sched_departure_date), ' ',
n.sched_departure_time), 'YYYY-MM-DD HH24:MI:SS.FF9')` timestamp at position
42, and a final `change_ind` CASE ('A'/'E'/'U'). The single defect is a
**cosmetic DEF-06 alias** at SELECT position 42: the expression is aliased
`AS new_sched_departure_date`, but position 42 of the INSERT list is
`new_sched_departure_time` (line 45). `INSERT … SELECT` is positional, so the
alias is inert — only the label is wrong.

- **Statement shape:** 1 INSERT (unchanged).
- **Column-count check:** 60 = 60 — no DEF-05.

---

## 2. Findings by class

| Class | Count | Findings |
|---|---|---|
| **AUTO** | 1 | DEF-06 alias normalize at SELECT pos 42 (`new_sched_departure_date` → `new_sched_departure_time`) |
| **FIX** | 0 | — |
| **SME** | 4 | SEM-04 (LTZ session-TZ); SEM-06/DTX-10 (implicit casts + FF9 precision); SEM-10 (act_* vs non-act_ join-key grain); SEM-03 (CHAR padding) |
| **KEEP** | 0 | `.sql` input — no SNZ constructs |

---

## 3. Fixes applied (rule IDs + line numbers)

| Rule | Source line(s) | Change |
|---|---|---|
| **DEF-06** | 110 | Alias `AS new_sched_departure_date` → `AS new_sched_departure_time` to match the INSERT target column at SELECT position 42 (line 45). `INSERT … SELECT` is positional, so only the alias label changes; the `TO_TIMESTAMP_LTZ(...)` expression stays in its slot. Minimal diff = 1 token. |

No syntax (SFX/FNX/DTX) fixes were required — the input parsed clean on
Snowflake with 0 residual-Teradata constructs. The only change is the cosmetic
DEF-06 alias normalization.

---

## 4. Defects repaired

1. **DEF-06 (line 110)** — alias ≠ target column name. Normalized the alias to
   the target name for readability. Not a data change (positional binding).

No DEF-01/02/03/04/05/07 findings.

---

## 5. Open `TODO(SME)` items

10 `TODO(SME)` markers carried forward (all blocked on missing DDL / Teradata
ground truth):

1. **SEM-04** — `TO_TIMESTAMP_LTZ` returns a timestamp with local session time
   zone; confirm `new_sched_departure_time` is meant to hold a local-time
   (LTZ) timestamp and pin session `TIMEZONE`.
2. **SEM-06/DTX-10** — implicit date/time casts in `CONCAT`/`TO_DATE`; confirm
   source types of `o.sched_departure_date` and `n.sched_departure_time`.
3. **SEM-06** — `FF9` format precision vs `n.sched_departure_time` precision;
   confirm or relax the mask.
4. **SEM-10** — `n.act_departure_station`/`n.act_arrival_station` vs
   `o.departure_station`/`o.arrival_station` join-key grain (actual vs
   scheduled?); confirm both sides are the same grain.
5. **SEM-03** — `CHAR(n)` padding drift on join keys; confirm no CHAR(n)
   comparison drift (no DDL supplied).
6. **SEM-08** — `''` vs NULL on `change_ind` CASE inputs; confirm `IS NULL` is
   the intended test (no empty-string hazard).

---

## 6. Validation result

- **Fixed file:** `python3 04_validate/validate.py 03_fix/output/SFissuetime_fixed.sql`
  → **PASS**. 1 statement parsed; 60 = 60 columns; no duplicate INSERT columns;
  no residual Teradata constructs; 10 `TODO(SME)` markers outstanding.
- **Control (buggy input):** `python3 04_validate/validate.py 00_input/SFissuetime.sql`
  → **PASS** (60 = 60, no residual Teradata, 0 TODO markers). **This control
  PASS is EXPECTED** — the only defect is a cosmetic DEF-06 alias issue, which
  is positional-inert (an INSERT…SELECT alias name does not change which source
  column lands in which target column; binding is by position). The mechanical
  validator therefore PASSes both the buggy input and the fixed file. Per the
  standing lesson (*"A control PASS on a cosmetic-only defect is expected"*),
  the decisive evidence is the manual spot-check, not the control's mechanical
  result. **Not a re-fix trigger.**

---

## 7. Residual-construct count

**0.** No residual Teradata constructs in the fixed file.

---

## 8. Open `TODO(SME)` count

**10.**

---

## 9. Sign-off checklist

- [x] 1 INSERT statement preserved; writes 60 columns to the target.
- [x] INSERT column order matches SELECT expression order (60 = 60).
- [x] No duplicate INSERT columns.
- [x] No residual Teradata constructs.
- [x] `QUALIFY` (none present) — n/a.
- [x] JOIN keys and CASE-branch order preserved exactly.
- [x] DEF-06 alias corrected; positional binding verified so no semantic drift.
- [x] 10 `TODO(SME)` markers carried forward for reviewer sign-off.
- [x] Validation PASS; control PASS expected (cosmetic/positional-inert DEF-06).

**Verdict: PASS — ready for reviewer sign-off.** The single DEF-06 alias fix is
a 1-token cosmetic change with no data impact; the 4 open SME items are all
blocked on missing DDL / Teradata ground truth and must not be rewritten
without reviewer confirmation. See the Stage-6 semantic doc
`06_explain/output/semantic_SFissuetime.md` for the clause-by-clause
walk-through.