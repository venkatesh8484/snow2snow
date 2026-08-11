# Stage 4 — Validation Report: S_vwxxx_MloadLinksUpdates

**Unit:** `S_vwxxx_MloadLinksUpdates`
**Fixed file:** `03_fix/output/S_vwxxx_MloadLinksUpdates_fixed.snowsql`
**Control (buggy input):** `00_input/S_vwxxx_MloadLinksUpdates.snowsql`
**Analysis:** `01_analyze/output/analysis_S_vwxxx_MloadLinksUpdates.md`
**Date:** 2026-07-24

---

## Final SQL

Validator run on `03_fix/output/S_vwxxx_MloadLinksUpdates_fixed.snowsql`:

```
INFO  .snowsql input — masked template tags / PUT-GET commands for validation (preserved as-is in the file).
PASS  snowflake connection: probe returned 1
PASS  parse: 1 statement(s) parsed as snowflake using snowflake
INFO  snowflake EXPLAIN stmt 1: skipped — referenced object not loaded. Detail: Object 'SNOWFLAKE_LEARNING_DB.STAGING.RTR_DIRECTFLOWOFLINKSRECORDS' does not exist or not authorized.
INFO  1 statement(s) skipped for lack of loaded objects — not counted as failures.
PASS  no residual Teradata constructs
INFO  TODO(SME) markers outstanding: 6
------------------------------------------------------------
RESULT: PASS
```

**Mechanical verdict: PASS**

- Parse: PASS (1 statement parsed as Snowflake).
- Residual Teradata scan: PASS (none found).
- EXPLAIN skipped — referenced object `STAGING.RTR_DIRECTFLOWOFLINKSRECORDS` not loaded in the validation environment. This is an environment gap, not a SQL defect (per orchestrator rules: INFO lines are not failures).
- 6 `TODO(SME)` markers outstanding — these are deferred SME confirmations (SEM-03 CHAR(n) padding, SEM-06/DTX-09 date-format mask, DEF-07 column-name confirmation), not defects. They do not affect the mechanical verdict.

---

## Buggy input control

Validator run on `00_input/S_vwxxx_MloadLinksUpdates.snowsql`:

```
INFO  .snowsql input — masked template tags / PUT-GET commands for validation (preserved as-is in the file).
PASS  snowflake connection: probe returned 1
PASS  parse: 1 statement(s) parsed as snowflake using snowflake
INFO  snowflake EXPLAIN stmt 1: skipped — referenced object not loaded. Detail: Object 'SNOWFLAKE_LEARNING_DB.STAGING.RTR_DIRECTFLOWOFLINKSRECORDS' does not exist or not authorized.
INFO  1 statement(s) skipped for lack of loaded objects — not counted as failures.
PASS  no residual Teradata constructs
INFO  TODO(SME) markers outstanding: 0
------------------------------------------------------------
RESULT: PASS
```

**Control PASS — expected and NOT a re-fix trigger.**

The control PASSES because the **DEF-07** defect (alias mismatch `IN_DEP_GMTFLIGHT_FLIGHT_DT` in the subquery vs. outer reference `src.IN_DEP_FLIGHT_DT`) does **not** cause a parse error. sqlglot parses the statement fine — the alias is syntactically valid, it simply doesn't match the name used in the outer `WHERE` clause. The EXPLAIN is skipped because the referenced object (`STAGING.RTR_DIRECTFLOWOFLINKSRECORDS`) is not loaded in the validation environment, so the backend cannot perform identifier resolution.

The defect is a **runtime resolution error**: at execution time Snowflake would raise `invalid identifier 'SRC.IN_DEP_FLIGHT_DT'` because no column of that name exists in the `src` subquery (it was aliased to `IN_DEP_GMTFLIGHT_FLIGHT_DT`). The mechanical validator cannot detect this without loading the objects and performing identifier resolution. Per the orchestrator rules: *"Do not re-fix a semantic-only unit just because the control PASSes."* The manual spot-check below is the decisive evidence that the fix is correct.

---

## Manual spot-check

### 1. DEF-07 alias fix applied — PASS

| Item | Buggy input | Fixed file |
|------|-------------|------------|
| Subquery alias (line ~13) | `OLD_IN_DEP_FLIGHT_DT AS IN_DEP_GMTFLIGHT_FLIGHT_DT` | `OLD_IN_DEP_FLIGHT_DT AS IN_DEP_FLIGHT_DT` |
| Outer WHERE reference | `src.IN_DEP_FLIGHT_DT` | `src.IN_DEP_FLIGHT_DT` |
| NOT EXISTS guard | `x.IN_DEP_FLIGHT_DT = tgt.IN_DEP_FLIGHT_DT` | `x.IN_DEP_FLIGHT_DT = tgt.IN_DEP_FLIGHT_DT` |

The fix restores the alias to `IN_DEP_FLIGHT_DT`, aligning the subquery column name with the outer `WHERE` and `NOT EXISTS` references. All three sites now use the same identifier — the runtime `invalid identifier` error is eliminated. Minimal diff: only the alias was changed; the outer WHERE and NOT EXISTS were left intact. A `TODO(SME)` marker confirms the intended column name for human review.

### 2. No residual Teradata constructs — PASS

The fixed file contains no `ZEROIFNULL`, `CONTAINS`, `MULTISET`, `(+)`, BTEQ dot-commands, `MINUS`, `SEL`, or any other Teradata construct. The validator's residual-Teradata scan confirms this. The `.snowsql` template tag `<% ctx.env.S_vw6122_CompareLinksRecordsWithTeradata_Current_date %>` is preserved verbatim per SNZ-01 (masked during validation, restored in the file).

### 3. JOIN keys intact — PASS

The 6-key UPDATE join predicate is unchanged between buggy and fixed:

```
tgt.LINK_STATION_CD       = src.LINK_STATION_CD
tgt.IN_ORIGN_STATION_CD   = src.IN_ORIGN_STATION_CD
tgt.IN_ALN_CD             = src.IN_ALN_CD
tgt.IN_FLIGHT_NO          = src.IN_FLIGHT_NO
tgt.IN_FLIGHT_SFX_CD      = src.IN_FLIGHT_SFX_CD
tgt.IN_DEP_FLIGHT_DT      = src.IN_DEP_FLIGHT_DT
tgt.LINK_EFFECTIVE_DT     = src.LINK_EFFECTIVE_DT
```

All 7 join keys (including `LINK_EFFECTIVE_DT`) are preserved in original order. The `NOT EXISTS` anti-join against `BASE.FLIGHT_FOLDERLINKS` is unchanged — all 9 guard predicates (7 join keys + `LINK_EXPIRY_DT` + `CURRENT_REC_IND`) are intact and in the same order.

### 4. SET clause and CASE/IFF branches intact — PASS

- `SET LINK_EXPIRY_DT = src.LINK_EXPIRY_DT` — unchanged.
- `SET CURRENT_REC_IND = src.CURRENT_REC_IND` — unchanged.
- `IFF(TO_CHAR(OLD_LINK_EXPIRY_DT,'YYYYMMDD') <> '20501231', OLD_LINK_EXPIRY_DT, DATEADD(DAY,-1,TO_DATE(...)))` — branch order and logic unchanged.
- `IFF(ACTION_CODE = 'U','Y','N')` — unchanged.
- `WHERE ACTION_CODE IN ('U','B')` — unchanged.

### 5. No dropped columns — PASS

This is an `UPDATE` statement (not an `INSERT … SELECT`), so there is no INSERT/SELECT column-count check. The subquery projects exactly the columns referenced by the outer `SET` and `WHERE` clauses: `LINK_STATION_CD`, `IN_ORIGN_STATION_CD`, `IN_ALN_CD`, `IN_FLIGHT_NO`, `IN_FLIGHT_SFX_CD`, `IN_DEP_FLIGHT_DT`, `LINK_EFFECTIVE_DT`, `LINK_EXPIRY_DT`, `CURRENT_REC_IND` — 9 columns, all consumed. No columns dropped or added.

### 6. Template tags preserved (SNZ-01) — PASS

The `<% ctx.env.S_vw6122_CompareLinksRecordsWithTeradata_Current_date %>` template tag is preserved verbatim in the fixed file. The validator masked it during parsing and restored it afterward.

---

## Summary

| Check | Result |
|-------|--------|
| Parse (fixed) | PASS |
| Residual Teradata (fixed) | PASS |
| EXPLAIN (fixed) | SKIPPED — object not loaded (environment gap, not a defect) |
| DEF-07 alias fix applied | PASS |
| JOIN keys intact | PASS |
| NOT EXISTS anti-join intact | PASS |
| SET / IFF branches intact | PASS |
| No dropped columns | PASS |
| Template tags preserved (SNZ-01) | PASS |
| Control PASS expected? | YES — DEF-07 is a runtime resolution error, not a parse error |

**Mechanical verdict: PASS**

The fixed file parses cleanly as Snowflake, contains no residual Teradata constructs, and the DEF-07 alias mismatch is corrected. The control PASSes as expected — the defect is a runtime identifier-resolution error that the mechanical validator cannot detect without loaded objects; the manual spot-check confirms the fix is correct. No hand-back to s2s-fix required.