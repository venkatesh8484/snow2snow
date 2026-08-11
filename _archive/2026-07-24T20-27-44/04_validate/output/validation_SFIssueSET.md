# Stage 4 — Validation Report: SFIssueSET

**Unit:** `SFIssueSET`
**Fixed SQL:** `03_fix/output/SFIssueSET_fixed.sql`
**Buggy input (control):** `00_input/SFIssueSET.sql`
**Validator:** `04_validate/validate.py` (sqlglot parse + Snowflake EXPLAIN + residual-Teradata regex scan + INSERT/SELECT alignment)
**Date:** 2026-07-24

---

## 1. Summary

| Check | Fixed SQL | Buggy input (control) |
|---|---|---|
| Parse (sqlglot, Snowflake dialect) | ✅ PASS — 3 statements parsed | ✅ PASS — 1 statement parsed |
| Snowflake EXPLAIN (live compile) | ✅ PASS — 3/3 statements compiled OK | ✅ PASS — 1/1 statement compiled OK |
| INSERT/SELECT column alignment | ✅ PASS (no explicit column lists; SELECT-only INSERTs) | ✅ PASS (same shape) |
| Duplicate INSERT columns | ✅ PASS (no explicit column lists) | ✅ PASS |
| Residual Teradata constructs | ✅ PASS — none found | ✅ PASS — none found |
| TODO(SME) markers (informational) | 4 | 0 |
| **Overall RESULT** | **PASS** | **PASS** (control) |

**Verdict:** The fixed SQL **PASSES** all mechanical validator checks.

> **Note on the control:** The buggy input *also* passes the mechanical
> validator. This is expected and correct: the defects in `SFIssueSET` are
> **semantic** (SEM-05 single-INSERT-UNION collapse, SEM-06 implicit string
> cast, latest-value concatenation trick), not syntax/parse errors. The
> validator is a *mechanical* gate (parse + compile + residual-scan); it cannot
> detect semantic drift. The control therefore does not fail the validator,
> which is why the manual spot-checks below are the decisive evidence that the
> fix is correct.

---

## 2. Validator output — fixed SQL

```
$ python3 04_validate/validate.py 03_fix/output/SFIssueSET_fixed.sql
PASS  snowflake connection: probe returned 1
PASS  parse: 3 statement(s) parsed as snowflake using snowflake
PASS  snowflake EXPLAIN stmt 1: compiled OK
PASS  snowflake EXPLAIN stmt 2: compiled OK
PASS  snowflake EXPLAIN stmt 3: compiled OK
PASS  no residual Teradata constructs
INFO  TODO(SME) markers outstanding: 4
------------------------------------------------------------
RESULT: PASS
```

Backend used: **Snowflake (live EXPLAIN)** — a Snowflake connection was
available, so each of the 3 statements was compiled against the real engine via
`EXPLAIN` (syntax + object resolution + type checking, no execution). All three
compiled OK.

### Parse errors / warnings (sqlglot)
None. sqlglot parsed all 3 statements cleanly as Snowflake.

### Snowflake EXPLAIN errors
None. All 3 statements compiled against the live Snowflake engine.

---

## 3. Validator output — buggy input (control)

```
$ python3 04_validate/validate.py 00_input/SFIssueSET.sql
PASS  snowflake connection: probe returned 1
PASS  parse: 1 statement(s) parsed as snowflake using snowflake
PASS  snowflake EXPLAIN stmt 1: compiled OK
PASS  no residual Teradata constructs
INFO  TODO(SME) markers outstanding: 0
------------------------------------------------------------
RESULT: PASS
```

**Control interpretation:** The buggy input parses and compiles — it is
syntactically valid Snowflake. Its bugs are semantic (see §4), which the
mechanical validator is not designed to catch. The control therefore does not
FAIL the validator; this is the expected behaviour for a semantically-drifted
unit and is documented here as evidence. The fix is validated by the manual
spot-checks in §4, not by the control failing.

---

## 4. Manual spot-checks

### 4.1 Structural shape (SEM-05 fix)

| Property | Buggy input | Fixed SQL | OK? |
|---|---|---|---|
| `INSERT INTO` statements | 1 | 3 | ✅ Split back into 3 independent INSERTs |
| `UNION` set operators | 2 | 0 | ✅ UNION collapse removed |
| `SELECT` blocks (`AS company_cd`) | 3 | 3 | ✅ All three branches preserved |

The buggy input collapsed three Teradata SET-table INSERTs into one
`INSERT ... SELECT ... UNION ... UNION ... SELECT`. Per **SEM-05**, the fix
splits this back into three independent `INSERT INTO staging.wrk_target
SELECT ...` statements, because `UNION` de-duplicates *across* branches whereas
each Teradata SET-table INSERT de-duplicates only against rows already in the
target. ✅ Correct.

### 4.2 JOIN keys preserved

All 9 JOIN-key predicates are byte-identical between input and fixed output:

| # | Predicate | Match |
|---|---|---|
| 1 | `ON  src.airline_cd = leg.marketing_airline_cd` | ✅ |
| 2 | `AND src.flgt_no    = leg.marketing_flgt_no` | ✅ |
| 3 | `AND src.flgt_dt    = leg.gmt_flgt_dt` | ✅ |
| 4 | `ON  src.airline_cd = leg.operating_airline_cd` | ✅ |
| 5 | `AND src.flgt_no    = leg.operating_flgt_no` | ✅ |
| 6 | `AND src.flgt_dt    = leg.gmt_flgt_dt` | ✅ |
| 7 | `ON  src.airline_cd = cs.codeshare_airline_cd` | ✅ |
| 8 | `AND src.flgt_no    = cs.codeshare_flgt_no` | ✅ |
| 9 | `AND src.flgt_dt    = cs.gmt_flgt_dt` | ✅ |

### 4.3 Column order preserved

Each of the three SELECT blocks emits columns in the identical order in both
files:

1. `airline_cd`
2. `flgt_no`
3. `flgt_dt`
4. `company_cd`
5. `direction_ind`
6. `operating_airline_cd`
7. `operating_flgt_no`
8. `operating_sfx_cd`

The aliased columns (`company_cd … operating_sfx_cd`) appear in the same
sequence in every block. ✅ No columns dropped, no reordering.

### 4.4 CASE-branch order

No `CASE` expressions are present in this unit. N/A.

### 4.5 Residual Teradata constructs

Regex scan (validator + manual `grep`) for `ZEROIFNULL`, `NULLIFZERO`,
`CONTAINS`, `MULTISET`, `PRIMARY INDEX`, `COLLECT STAT`, `LOCKING`, `(+)`,
`MINUS`, `SEL` (shorthand), `OREPLACE`, `OTRANSLATE`, `FORMAT '…'`:
**none found** in the fixed SQL. ✅

### 4.6 TODO(SME) markers

4 outstanding `TODO(SME)` markers in the fixed SQL, all carried over from the
Stage-3 fix log as required assumptions (SET-table dedup wrapping, LPAD widths,
`effective_dt` type/format, `param_value` cast). These are informational and
require human review, not validator failures.

---

## 5. Conclusion

| Gate | Result |
|---|---|
| Mechanical validator (fixed SQL) | **PASS** |
| Control (buggy input) | PASS (expected — defects are semantic, not mechanical) |
| Manual spot-checks (JOIN keys, column order, no dropped columns, no residual TD, SEM-05 split) | **PASS** |

**The fixed SQL `03_fix/output/SFIssueSET_fixed.sql` is mechanically valid
Snowflake and structurally faithful to the input.** The remediation correctly
applies SEM-05 (split the UNION-collapsed INSERT back into three independent
INSERTs) and SEM-06/FN-LATEST (explicit casts + fixed-width concatenation key
for the latest-value trick) without altering JOIN keys, column order, or
introducing residual Teradata constructs.

The 4 `TODO(SME)` items are genuine open assumptions that require human
confirmation (SET-table dedup semantics, LPAD widths vs. source DDL,
`effective_dt` type, `param_value` cast) and are flagged for the reviewer —
they are not validator failures.