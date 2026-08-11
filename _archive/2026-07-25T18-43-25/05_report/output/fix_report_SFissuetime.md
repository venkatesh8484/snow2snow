# Fix Report — `SFissuetime.sql`

**Unit:** `SFissuetime` (Snowflake → Snowflake remediation)
**Input:** `00_input/SFissuetime.sql` (139 lines)
**Fixed:** `03_fix/output/SFissuetime_fixed.sql`
**Teradata ground truth:** none (no `SFissuetime.teradata.sql` in `00_input/`)
**Date:** 2026-07-24
**Stage:** 5 — Report & Learn

---

## 1. Summary

`SFissuetime.sql` is an `INSERT INTO staging.wrk_synthetic_flgt_leg_ins_exp`
(60 target columns) that FULL OUTER JOINs the "old" source
`wrk_synthetic_flgt_source1` (`o`) with the "new" source
`wrk_synthetic_flgt_source2` (`n`) to produce a before/after diff with a
`change_ind` flag (`A`=add, `E`=expire, `U`=update). The file is parse-clean
Snowflake with no residual Teradata constructs and a balanced 60=60
INSERT/SELECT column count. The only mechanical defect is a **cosmetic alias
mismatch** (DEF-06): the constructed `TO_TIMESTAMP_LTZ(CONCAT(TO_DATE(...),
' ', n.sched_departure_time), 'YYYY-MM-DD HH24:MI:SS.FF9')` expression at
SELECT position 42 was aliased `AS new_sched_departure_date` when its INSERT
target slot is `new_sched_departure_time`. Because `INSERT … SELECT` is
positional, the alias had no effect on execution; it was normalized to
`AS new_sched_departure_time` for reviewer clarity. Four semantic-intent
questions (timezone, implicit casts, format precision, join-key grain) are
flagged `TODO(SME)` for human review — none is mechanically resolvable without
ground truth or DDL. Validation: **PASS**.

---

## 2. Rules applied

### Syntax (SFX / FNX / DTX)

| Rule | Count | Detail |
|---|---|---|
| — | 0 | No syntax, function, or datatype fixes required. The input is clean Snowflake. |

### Defects (DEF)

| Rule | Count | Detail |
|---|---|---|
| **DEF-06** (alias ≠ target name — cosmetic) | 1 | SELECT position 42 alias `AS new_sched_departure_date` normalized to `AS new_sched_departure_time` to match the INSERT target at that position. Positional placement was already correct; no data change. |

### Semantic (SEM) — all `TODO(SME)`, no mechanical fix

| Rule | Count | Detail |
|---|---|---|
| **SEM-04** (timezone intent) | 1 | `TO_TIMESTAMP_LTZ` returns a local-session-TZ timestamp; the sibling "old" GMT columns and the separate `new_gmt_sched_departure_time` slot suggest LTZ is plausibly intended for the local-time slot, but session `TIMEZONE` must be pinned or the stored value drifts. |
| **SEM-06** (implicit casts) | 1 | `CONCAT(TO_DATE(o.sched_departure_date), ' ', n.sched_departure_time)` performs implicit date→string and time→string casts that depend on session defaults; recommend explicit `TO_CHAR(TO_DATE(...),'YYYY-MM-DD')`. |
| **SEM-06** (format precision) | 1 | Format mask `'YYYY-MM-DD HH24:MI:SS.FF9'` expects 9-digit fractional seconds; confirm `n.sched_departure_time` precision matches or relax the mask. |
| **SEM-10** (join-key grain) | 1 | FULL OUTER JOIN keys `n.act_departure_station = o.departure_station` and `n.act_arrival_station = o.arrival_station` mix `act_*` (actual) on the new side with non-`act_` names on the old side; confirm both sides are the same (actual) station grain. |

**Totals:** 1 mechanical fix (DEF-06, AUTO) + 4 semantic SME questions
(5 inline `TODO(SME)` markers — SEM-06 covers two distinct inline notes).

---

## 3. Defects repaired

| # | Rule | Lines (fixed) | Before | After | Class | Data change? |
|---|---|---|---|---|---|---|
| D1 | DEF-06 | 120 | `) AS new_sched_departure_date,` | `) AS new_sched_departure_time,` | AUTO | **No** — alias is cosmetic in positional `INSERT … SELECT`; expression already lands in slot 42 (`new_sched_departure_time`). |

No other defects (DEF-01/02/03/04/05/07) were present. The
`TO_TIMESTAMP_LTZ`/`CONCAT`/`TO_DATE` nesting is paren-balanced; column counts
match; no duplicate INSERT columns; no wrong-column-ref is provable without
ground truth.

---

## 4. Open `TODO(SME)` items

Five inline markers carried forward for human review (no mechanical fix
possible without DDL/ground truth):

1. **SEM-04 — Timezone intent.** Is `new_sched_departure_time` intended to
   store a **local-time** timestamp (`TIMESTAMP_LTZ`), not NTZ/TZ? Pin the
   session `TIMEZONE` so the stored value does not drift across sessions.
2. **SEM-06 — Implicit casts.** What are the source types of
   `o.sched_departure_date` and `n.sched_departure_time`? Make the casts in
   `CONCAT`/`TO_DATE` explicit (e.g.
   `TO_CHAR(TO_DATE(o.sched_departure_date),'YYYY-MM-DD')`) to remove
   session-default formatting dependence.
3. **SEM-06 — Format precision.** Does `n.sched_departure_time` carry 9-digit
   fractional seconds matching `FF9`, or should the mask be relaxed?
4. **SEM-10 — Join-key grain.** Are `n.act_departure_station` /
   `n.act_arrival_station` semantically the same **actual** grain as
   `o.departure_station` / `o.arrival_station`? A scheduled-vs-actual mismatch
   would silently change the FULL OUTER JOIN result.
5. **DEF-06 (confirmation).** Confirm the `TO_TIMESTAMP_LTZ(...)` expression is
   positionally correct in slot 42 (`new_sched_departure_time`) and only the
   alias was wrong. The logical shape (date + time → timestamp) supports this,
   but without ground truth it remains an inference.

---

## 5. Validation result

**Verdict: ✅ PASS**

| Check | Fixed file | Control (buggy input) |
|---|---|---|
| Snowflake connection probe | PASS | PASS |
| Parse (sqlglot, snowflake dialect) | PASS — 1 statement | PASS — 1 statement |
| Snowflake EXPLAIN (live compile) | PASS | PASS |
| INSERT columns == SELECT expressions | PASS — 60 == 60 | PASS — 60 == 60 |
| No duplicate INSERT columns | PASS | PASS |
| No residual Teradata constructs | PASS | PASS |
| `TODO(SME)` markers outstanding | 5 | 0 |
| **RESULT** | **PASS** | **PASS** |

**Control PASS — expected, not a re-fix trigger.** The only defect is a
cosmetic alias mismatch (DEF-06). Because `INSERT … SELECT` is positional, the
alias name has no effect on parse, compile, or execution, so the mechanical
validator correctly PASSes the buggy input. This is the documented behavior for
cosmetic-only / semantic-only defects; the decisive evidence is the manual
spot-check (alias fix applied at line 120, FIX LOG cites DEF-06), not the
control result. No hand-back to s2s-fix is warranted.

Manual spot-checks (all PASS): JOIN keys intact (6 keys preserved), CASE branch
order intact (A→E→U), no dropped columns (60=60), no residual Teradata
functions/operators, alias fix applied, `TODO(SME)` markers present.

---

## 6. Sign-off checklist

A reviewer can sign off from this document alone. Confirm each item:

- [x] **Column count balanced** — 60 INSERT == 60 SELECT (Stage 1 + Stage 4).
- [x] **No residual Teradata constructs** — validator + grep clean.
- [x] **JOIN keys preserved** — all 6 FULL OUTER JOIN keys unchanged.
- [x] **CASE branch order preserved** — `change_ind` A→E→U logic intact.
- [x] **Mechanical defect repaired** — DEF-06 alias normalized; no data change.
- [x] **Minimal diff** — only the alias text changed; no expression/JOIN/CASE
      rewrite.
- [x] **Validation PASS** — fixed file parses, EXPLAIN-compiles, count-balanced,
      no duplicates, no residual Teradata.
- [x] **Control explained** — buggy input PASSes because the defect is
      cosmetic/positional; not a re-fix trigger.
- [x] **Semantic risks flagged** — 4 SME questions (SEM-04, SEM-06×2, SEM-10)
      carried as `TODO(SME)` for human review.
- [x] **No ground truth** — no `SFissuetime.teradata.sql`; every semantic
      inference is flagged, none silently applied.
- [ ] **SME sign-off** — reviewer resolves the 5 `TODO(SME)` items above
      (timezone pin, explicit casts, FF9 precision, station grain, alias
      confirmation). Until then the semantic intent is unconfirmed.

**Stage 5 complete.** Semantic account lives in Stage 6
(`06_explain/output/semantic_SFissuetime.md`); this report does not duplicate it.