# Validation Report — S_vwxxx_MloadLinksUpdates

**Unit:** `S_vwxxx_MloadLinksUpdates`
**Fixed file:** `03_fix/output/S_vwxxx_MloadLinksUpdates_fixed.snowsql`
**Control file:** `00_input/S_vwxxx_MloadLinksUpdates.snowsql`
**Dialect:** Snowflake (`.snowsql` input — template tags / PUT-GET masked for validation, preserved verbatim in the file per SNZ-01)
**Mechanical verdict:** **PASS**

---

## Final SQL

Validator output (`python3 04_validate/validate.py 03_fix/output/S_vwxxx_MloadLinksUpdates_fixed.snowsql`):

```
INFO  .snowsql input — masked template tags / PUT-GET commands for validation (preserved as-is in the file).
PASS  parse: 1 statement(s) parsed as snowflake using sqlglot
PASS  no residual Teradata constructs
INFO  TODO(SME) markers outstanding: 10
RESULT: PASS
```

### Mechanical checks

| Check | Result |
|---|---|
| Parse (sqlglot, snowflake) | PASS — 1 statement |
| Residual Teradata constructs | PASS — none |
| INSERT/SELECT column count | N/A — single UPDATE statement |
| Duplicate columns | N/A — UPDATE |
| `.snowsql` template tags preserved | PASS — `<% ctx.env.S_vw6122_CompareLinksRecordsWithTeradata_Current_date %>` intact |
| TODO(SME) markers | 10 outstanding (all flagged for human review; none block compilation) |

### Manual spot-check

- **JOIN keys (WHERE clause, lines 28-34):** All 6 join keys preserved in original order — `LINK_STATION_CD`, `IN_ORIGN_STATION_CD`, `IN_ALN_CD`, `IN_FLIGHT_NO`, `IN_FLIGHT_SFX_CD`, `IN_DEP_FLIGHT_DT`, plus `LINK_EFFECTIVE_DT`. Identical to buggy input. ✅
- **NOT EXISTS guard (lines 35-46):** Guard table `BASE.FLIGHT_FOLDERLINKS x` and all 9 correlation predicates preserved verbatim, including the `x.LINK_EXPIRY_DT = src.LINK_EXPIRY_DT` and `x.CURRENT_REC_IND = src.CURRENT_REC_IND` tail predicates. ✅
- **SET clause:** `LINK_EXPIRY_DT = src.LINK_EXPIRY_DT`, `CURRENT_REC_IND = src.CURRENT_REC_IND` — unchanged. ✅
- **Subquery SELECT column order:** `LINK_STATION_CD, IN_ORIGN_STATION_CD, IN_ALN_CD, IN_FLIGHT_NO, IN_FLIGHT_SFX_CD, IN_DEP_FLIGHT_DT, LINK_EFFECTIVE_DT, LINK_EXPIRY_DT, CURRENT_REC_IND` — order preserved; only the alias of the 6th column was changed (see DEF-07 below). ✅
- **CASE/IFF branch order:** Both `IFF` expressions (`TO_CHAR(...) <> '20501231'` then-else, and `ACTION_CODE = 'U'` Y/N) preserved in original branch order. ✅
- **DEF-07 alias fix (line 18):** Buggy input aliased `OLD_IN_DEP_FLIGHT_DT AS IN_DEP_GMTFLIGHT_FLIGHT_DT`, but the outer WHERE references `src.IN_DEP_FLIGHT_DT` (line 29) and the NOT EXISTS guard references `tgt.IN_DEP_FLIGHT_DT` (line 39). The mismatched alias would raise Snowflake `invalid identifier 'SRC.IN_DEP_FLIGHT_DT'` at runtime. Fixed file restores the alias to `IN_DEP_FLIGHT_DT`, aligning the subquery output to the join key. Minimal diff (alias only; outer WHERE and guard left untouched). Flagged `TODO(SME)` to confirm the intended column name. ✅
- **No dropped columns:** Subquery emits 9 columns; SET consumes 2 (`src.LINK_EXPIRY_DT`, `src.CURRENT_REC_IND`); WHERE consumes 7 join keys + 2 NOT EXISTS correlations. No column lost. ✅
- **No residual Teradata:** No `ZEROIFNULL`, `CONTAINS`, `MULTISET`, `(+)`, BTEQ dot-commands, `MINUS`, `SEL`, etc. ✅
- **Snowflake idioms:** `IFF`, `DATEADD(DAY,-1,TO_DATE(...))`, `TO_CHAR(...,'YYYYMMDD')` — all valid Snowflake. ✅
- **SNZ-01 preservation:** `<% ctx.env.S_vw6122_CompareLinksRecordsWithTeradata_Current_date %>` template tag preserved verbatim; validator masked it for parse. ✅

### Open SME items (do not block PASS)

1. **DEF-07 (line 18):** Confirm intended column name is `IN_DEP_FLIGHT_DT` (not `IN_DEP_GMTFLIGHT_FLIGHT_DT`).
2. **DEF-07 (line 1 vs 32):** Confirm `BASE.FLIGHT_FOLDERLINKS` (NOT EXISTS guard) is a distinct table and not a typo for the UPDATE target `BASE.FLT_FOLDERLINKS`. Not corrected — DEF-07 forbids guessing a table rename.
3. **SEM-06 / DTX-09 (line 18):** Confirm the orchestrator injects `Current_date` in `DDMONYY` form (e.g. `24JUL26`) to match the `TO_DATE(...,'DDMONYY')` mask.
4. **SEM-03 (lines 24-30, 34-40):** Verify key columns are not `CHAR(n)`; if any are, wrap joins in `RTRIM` to replicate Teradata blank-padding semantics.
5. **SEM-06 / SEM-08 (line 17):** Confirm intended NULL handling when `OLD_LINK_EXPIRY_DT` is NULL — `TO_CHAR(NULL,'YYYYMMDD') <> '20501231'` yields NULL, routing the row to the `DATEADD` else-branch.

---

## Buggy input control

Validator output (`python3 04_validate/validate.py 00_input/S_vwxxx_MloadLinksUpdates.snowsql`):

```
INFO  .snowsql input — masked template tags / PUT-GET commands for validation (preserved as-is in the file).
PASS  parse: 1 statement(s) parsed as snowflake using sqlglot
PASS  no residual Teradata constructs
RESULT: PASS
```

**Control PASS is expected and is NOT a re-fix trigger.** The defect in the buggy input is a **DEF-07 alias mismatch** (`OLD_IN_DEP_FLIGHT_DT AS IN_DEP_GMTFLIGHT_FLIGHT_DT` vs the outer reference `src.IN_DEP_FLIGHT_DT`). This is a **runtime resolution error** — Snowflake would raise `invalid identifier 'SRC.IN_DEP_FLIGHT_DT'` at execution time — not a parse error. sqlglot's parser does not resolve identifiers against the subquery's output schema, so it parses the buggy input cleanly. The mechanical validator therefore correctly PASSes the control; the decisive evidence is the manual spot-check above, which confirms the fixed file aligns the alias to the join key while the buggy input does not. Per the s2s-validate policy, a passing control on a semantic/runtime-only defect is expected and does not warrant handing back to s2s-fix.

---

## Verdict

**PASS** — The fixed file parses as Snowflake, contains no residual Teradata constructs, preserves all join keys / SET columns / NOT EXISTS predicates / IFF branch order, and remediates the DEF-07 alias mismatch that would have caused a runtime `invalid identifier` error in the buggy input. The 10 outstanding `TODO(SME)` markers are human-review items (column-name confirmation, CHAR-key padding, NULL handling, template-tag date format, guard-table identity) and do not block compilation. No hand-back to s2s-fix.