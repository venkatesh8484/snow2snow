# Stage 4 — Validation Report: S_vwxxx_MloadLinksInserts

**Unit:** `S_vwxxx_MloadLinksInserts`
**Fixed file:** `03_fix/output/S_vwxxx_MloadLinksInserts_fixed.snowsql`
**Control (buggy input):** `00_input/S_vwxxx_MloadLinksInserts.snowsql`
**Analysis:** `01_analyze/output/analysis_S_vwxxx_MloadLinksInserts.md`
**Date:** 2026-07-24

---

## Final SQL

Validator command:
`python3 04_validate/validate.py 03_fix/output/S_vwxxx_MloadLinksInserts_fixed.snowsql`

```
INFO  .snowsql input — masked template tags / PUT-GET commands for validation (preserved as-is in the file).
PASS  snowflake connection: probe returned 1
PASS  parse: 1 statement(s) parsed as snowflake using snowflake
INFO  snowflake EXPLAIN stmt 1: skipped — referenced object not loaded. Detail: Object 'SNOWFLAKE_LEARNING_DB.STAGING.EXPFINALYSEINSERTS' does not exist or not authorized.
INFO  1 statement(s) skipped for lack of loaded objects — not counted as failures.
PASS  stmt 1: INSERT columns (33) == SELECT expressions (33)
PASS  stmt 1: no duplicate INSERT columns
PASS  no residual Teradata constructs
INFO  TODO(SME) markers outstanding: 18
------------------------------------------------------------
RESULT: PASS
```

**Mechanical verdict: PASS**

Notes on non-blocking lines (per orchestrator rules, these are environment gaps, not SQL defects):
- `INFO .snowsql input — masked template tags / PUT-GET commands` — expected; the `.snowsql` client layer (`SNZ-*`) preserves `<% %>` tags and `PUT`/`GET` commands as-is. The validator masks them before parsing. Not a defect.
- `INFO snowflake EXPLAIN stmt 1: skipped — referenced object not loaded` — the target table `SNOWFLAKE_LEARNING_DB.STAGING.EXPFINALYSEINSERTS` is not provisioned in this environment. EXPLAIN is skipped and not counted as a failure. Not a defect.
- `INFO TODO(SME) markers outstanding: 18` — expected for a semantic-only unit. The 18 markers document SEM-03 (CHAR padding) and SEM-06 (implicit cast) assumptions that require DDL to resolve; they are not failures.

---

## Buggy input control

Validator command:
`python3 04_validate/validate.py 00_input/S_vwxxx_MloadLinksInserts.snowsql`

```
INFO  .snowsql input — masked template tags / PUT-GET commands for validation (preserved as-is in the file).
PASS  snowflake connection: probe returned 1
PASS  parse: 1 statement(s) parsed as snowflake using snowflake
INFO  snowflake EXPLAIN stmt 1: skipped — referenced object not loaded. Detail: Object 'SNOWFLAKE_LEARNING_DB.STAGING.EXPFINALYSEINSERTS' does not exist or not authorized.
INFO  1 statement(s) skipped for lack of loaded objects — not counted as failures.
PASS  stmt 1: INSERT columns (33) == SELECT expressions (33)
PASS  stmt 1: no duplicate INSERT columns
PASS  no residual Teradata constructs
INFO  TODO(SME) markers outstanding: 0
------------------------------------------------------------
RESULT: PASS
```

**Control verdict: PASS — expected for a semantic-only unit.**

The control PASSES because the buggy input is **mechanically clean**: it parses as Snowflake, the INSERT/SELECT column counts match (33 = 33), there are no duplicate columns, and no residual Teradata constructs. The bugs in this unit are purely **semantic**:

- **SEM-03** — CHAR(n) padding drift in the 33-key NOT EXISTS anti-join. Teradata blank-pads `CHAR(n)` and ignores trailing spaces in `=` comparison; Snowflake `VARCHAR` does not. Without DDL for `BASE.FLT_FOLDER_LINKS`, the mechanical validator cannot detect this drift.
- **SEM-06** — implicit cast drift. SELECT aliases carry `_SMALLINT` and `_DATE` suffixes (e.g. `NEW_IN_FLT_NO_SMALLINT`, `NEW_IN_DEP_FLTDT_DATE`); the NOT EXISTS predicates compare these against the target columns. The validator has no DDL to confirm type compatibility.

The mechanical validator has no rule that detects CHAR padding or type mismatch without DDL, so a passing control is the **expected** outcome for a semantic-only unit. Per the orchestrator rules: *"Do not re-fix a semantic-only unit just because the control PASSes — the decisive evidence is the SEM-* inventory and manual spot-check, not the control's mechanical result."* The control PASS is **not** a re-fix trigger.

---

## Manual spot-check

| # | Check | Result | Evidence |
|---|-------|--------|----------|
| 1 | INSERT columns == SELECT expressions | **PASS** | Validator: `33 == 33`. INSERT block lists 33 columns (`LINK_STATION_CD` … `CURRENT_REC_IND`). |
| 2 | No duplicate INSERT columns | **PASS** | Validator: `no duplicate INSERT columns`. Manual scan of the 33-name list confirms all unique. |
| 3 | No residual Teradata constructs | **PASS** | Validator: `no residual Teradata constructs`. Manual `grep` for `ZEROIFNULL`, `CONTAINS`, `MULTISET`, `(+)`, BTEQ dot-commands, `MINUS`, `SEL` → none found. |
| 4 | JOIN / anti-join keys intact | **PASS** | The NOT EXISTS anti-join (lines ~103-146) preserves all 31 explicit key predicates against `BASE.FLT_FOLDER_LINKS T`, matching each target column to its `S.NEW_*` source alias (e.g. `T.IN_ORIGN_STATION_CD = S.NEW_IN_ORIGN_STATION_CD`, `T.IN_FLT_NO = S.NEW_IN_FLT_NO_SMALLINT`, `T.IN_DEP_FLTDT = S.NEW_IN_DEP_FLTDT_DATE`, … `T.LINK_EXPIRY_DT = S.NEW_LINK_EXPIRY_DT`). Key order and predicate set are unchanged from the input. |
| 5 | CASE-branch order preserved | **PASS** | No `CASE` expressions in this unit (it is a straight INSERT…SELECT…NOT EXISTS). N/A — nothing to reorder. |
| 6 | No dropped columns | **PASS** | All 33 INSERT columns have a corresponding SELECT expression; validator confirms `33 == 33`. |
| 7 | `.snowsql` template tags / PUT-GET preserved | **PASS** | Validator masked `<% %>` tags and `PUT`/`GET` commands for parsing; they remain as-is in the fixed file per `SNZ-*`. |
| 8 | TODO(SME) markers documented | **PASS** | 18 `TODO(SME)` markers present, all referencing SEM-03 / SEM-06 assumptions that require DDL to resolve. No SQL changed for these — they are inline annotations for SME review. |

---

## Semantic defect inventory (decisive evidence)

Because the control PASSes mechanically, the decisive evidence for this unit is the SEM-* inventory from the analysis and the manual spot-check, not the control's mechanical result:

- **SEM-03 (CHAR(n) padding drift)** — The 33-key NOT EXISTS anti-join compares `CHAR(n)`-typed key columns (`*_CD`, `*_TYP`, `*_TXT`, `*_IND`) between `BASE.FLT_FOLDER_LINKS` and the staging source. Teradata blank-pads `CHAR(n)` and ignores trailing spaces in `=`; Snowflake `VARCHAR` does not blank-pad. If the target columns are `CHAR(n)` in Snowflake, the anti-join may fail to suppress rows that Teradata would suppress. Flagged `TODO(SME)` — requires DDL for `BASE.FLT_FOLDER_LINKS` to confirm. No SQL changed (minimal diff); the fix log documents the assumption.
- **SEM-06 (implicit cast drift)** — SELECT aliases carry `_SMALLINT` and `_DATE` suffixes, indicating the source columns have been cast/typed differently from the target. The NOT EXISTS predicates compare these directly against target columns. Without DDL, type compatibility cannot be confirmed mechanically. Flagged `TODO(SME)`.

Both are **semantic-only** defects that the mechanical validator cannot detect without DDL. They are documented for SME review and do not constitute a hard failure of the fixed file.

---

## Mechanical verdict

**PASS**

- Fixed file: all mechanical checks PASS (parse, 33=33 columns, no duplicates, no residual Teradata).
- Control: PASS — expected for a semantic-only unit; not a re-fix trigger.
- Manual spot-check: all 8 checks PASS.
- Non-blocking `INFO` lines (EXPLAIN skipped, `.snowsql` masking, TODO count) are environment gaps / expected annotations, not SQL defects.

No hand-back to s2s-fix. The unit is mechanically valid; the SEM-03 / SEM-06 assumptions are captured as `TODO(SME)` for human review with DDL.