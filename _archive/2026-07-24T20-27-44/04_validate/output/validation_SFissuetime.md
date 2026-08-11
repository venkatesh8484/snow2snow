# Stage 4 — Validation: `SFissuetime.sql`

**Validator:** `04_validate/validate.py` (sqlglot Snowflake dialect + live
Snowflake EXPLAIN when credentials are available)
**Fixed file:** `03_fix/output/SFissuetime_fixed.sql`
**Buggy input (control):** `00_input/SFissuetime.sql`
**Teradata ground truth:** none supplied (no `00_input/SFissuetime.teradata.sql`)

---

## Final SQL

Run: `python3 04_validate/validate.py 03_fix/output/SFissuetime_fixed.sql`

```
PASS  snowflake connection: probe returned 1
PASS  parse: 1 statement(s) parsed as snowflake using snowflake
PASS  snowflake EXPLAIN stmt 1: compiled OK
PASS  stmt 1: INSERT columns (60) == SELECT expressions (60)
PASS  stmt 1: no duplicate INSERT columns
PASS  no residual Teradata constructs
INFO  TODO(SME) markers outstanding: 9
------------------------------------------------------------
RESULT: PASS
```

**Result: PASS** (exit code 0). All hard checks pass:

| # | Check | Result | Detail |
|---|---|---|---|
| 1 | Parse (sqlglot, Snowflake dialect) | ✅ PASS | 1 statement parsed |
| 1b | Snowflake EXPLAIN (live engine compile) | ✅ PASS | stmt 1 compiled OK |
| 2 | INSERT/SELECT column alignment | ✅ PASS | 60 INSERT columns == 60 SELECT expressions |
| 3 | Duplicate INSERT columns | ✅ PASS | none |
| 4 | Residual Teradata constructs | ✅ PASS | none found |
| 5 | TODO(SME) markers (informational) | ℹ️ INFO | 9 outstanding (all SME-flagged, no AUTO/FIX changes to SQL body) |

### Manual spot-check

| Check | Result | Evidence |
|---|---|---|
| JOIN keys intact | ✅ PASS | 6 predicates, identical order/operands to buggy input: `operating_airline_cd`, `operating_flgt_no`, `operating_sfx_cd`, `sched_departure_date`, `act_departure_station=departure_station`, `act_arrival_station=arrival_station` (fixed lines 173–179 vs buggy 133–139) |
| CASE branch order preserved | ✅ PASS | `WHEN o.… IS NULL THEN 'A'` → `WHEN n.… IS NULL THEN 'E'` → `ELSE 'U'` (fixed lines 161–164 vs buggy 124–131) — order unchanged |
| No dropped columns | ✅ PASS | 60 INSERT cols == 60 SELECT exprs; positional alignment matches analysis (positions 1, 30, 31, 35, 36, 42, 60 all accounted for) |
| No residual Teradata function/operator | ✅ PASS | grep for `ZEROIFNULL`, `NULLIFZERO`, `CONTAINS`, `OVERLAPS PERIOD`, `MULTISET`, `PRIMARY INDEX`, `COLLECT STAT`, `LOCKING`, `(+)`, `MINUS`, `SEL`, `OREPLACE`, `OTRANSLATE`, `FORMAT '` (excluding comment lines) → none |
| Minimal diff | ✅ PASS | Only additions: FIX LOG header block + 9 `TODO(SME)` inline comments. SQL statement body byte-for-byte identical to input (no columns swapped, no expressions rewritten) |

### SME findings carried forward (informational, not validation failures)

These are semantic risks the fix stage correctly flagged as `TODO(SME)` rather
than auto-changing, because no Teradata ground truth or target DDL is supplied:

- **DEF-07 / SEM-10** — INSERT position 42 (`new_sched_departure_time`) is fed
  `n.sched_arrival_time`; likely copy-paste defect (should be
  `n.sched_departure_time`). Flagged, NOT swapped per DEF-07.
- **DTX-04 / SEM-04** — `new_sched_departure_date` (pos 35) yields
  `TIMESTAMP_LTZ` while sibling `old_sched_departure_date` (pos 4) is a plain
  DATE → type drift / session-TZ sensitivity. Flagged.
- **SEM-03** — string join keys may be `CHAR(n)` → blank-padding drift risk.
  Flagged.
- **SEM-06** — `sched_departure_date` join key type alignment between sources.
  Flagged.

---

## Buggy input control

Run: `python3 04_validate/validate.py 00_input/SFissuetime.sql`

```
PASS  snowflake connection: probe returned 1
PASS  parse: 1 statement(s) parsed as snowflake using snowflake
PASS  snowflake EXPLAIN stmt 1: compiled OK
PASS  stmt 1: INSERT columns (60) == SELECT expressions (60)
PASS  stmt 1: no duplicate INSERT columns
PASS  no residual Teradata constructs
INFO  TODO(SME) markers outstanding: 0
------------------------------------------------------------
RESULT: PASS
```

**Result: PASS (control did NOT fail).**

### Interpretation of the control outcome

The buggy input **passes the mechanical validator**. This is expected and does
**not** indicate a validator defect: the issues in `SFissuetime.sql` are
**purely semantic/defect-level**, not structural. Specifically:

- The file parses cleanly as Snowflake (no syntax errors, no residual Teradata
  constructs).
- INSERT/SELECT column counts already align (60 = 60) — the count-mismatch
  detector (DEF-05) has nothing to catch.
- The real bugs are a **likely wrong source column** (pos 42:
  `new_sched_departure_time` ← `n.sched_arrival_time`) and **type drift**
  (`TIMESTAMP_LTZ` into a `…_date` slot). These require semantic judgment +
  target DDL / Teradata ground truth, which the mechanical validator
  intentionally does not perform (per ICM: scripts do the non-AI work; AI does
  the semantic work in Stages 1, 3, 5, 6).

The control therefore confirms that the validator's hard checks (parse, count
alignment, duplicates, residual-Teradata) are **not** the right tool to catch
this file's issues — which is exactly why the analysis stage classified every
finding as **SME** and the fix stage added `TODO(SME)` annotations rather than
mutating the SQL. The validator's role here is to prove the fixed file is
**structurally sound and executable on Snowflake**, which it does.

---

## Summary

| File | Parse | EXPLAIN | Col count | Dupes | Residual TD | TODO(SME) | Overall |
|---|---|---|---|---|---|---|---|
| `03_fix/output/SFissuetime_fixed.sql` | ✅ | ✅ | 60=60 ✅ | none ✅ | none ✅ | 9 (info) | **PASS** |
| `00_input/SFissuetime.sql` (control) | ✅ | ✅ | 60=60 ✅ | none ✅ | none ✅ | 0 | PASS (semantic bugs not mechanically detectable) |

**Validation verdict: PASS.** The fixed SQL is structurally valid, executable on
Snowflake (EXPLAIN compiles), column-aligned, free of residual Teradata
constructs, and preserves JOIN keys / CASE order / column order exactly. All
semantic concerns are carried as `TODO(SME)` for human review — no unreviewed
assumptions were baked into the SQL.