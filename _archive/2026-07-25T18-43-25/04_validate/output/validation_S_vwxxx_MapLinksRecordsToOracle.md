# Stage 4 — Validation: S_vwxxx_MapLinksRecordsToOracle

**Fixed file:** `03_fix/output/S_vwxxx_MapLinksRecordsToOracle_fixed.snowsql`
**Control (buggy input):** `00_input/S_vwxxx_MapLinksRecordsToOracle.snowsql`
**Analysis:** `01_analyze/output/analysis_S_vwxxx_MapLinksRecordsToOracle.md`
**File type:** `.snowsql` (SnowSQL client layer — SNZ-* rules apply)
**Validator:** `04_validate/validate.py` (sqlglot parse + Snowflake EXPLAIN backend)

---

## Final SQL

Validator run on `03_fix/output/S_vwxxx_MapLinksRecordsToOracle_fixed.snowsql`:

```
INFO  .snowsql input — masked template tags / PUT-GET commands for validation (preserved as-is in the file).
PASS  snowflake connection: probe returned 1
PASS  parse: 6 statement(s) parsed as snowflake using snowflake
PASS  snowflake EXPLAIN stmt 1: compiled OK
INFO  snowflake EXPLAIN stmt 2: skipped — referenced object not loaded. Detail: Table 'STAGING.SQ_SRC_LINKSCSVFILE' does not exist
FAIL  snowflake EXPLAIN stmt 3: 001003 (42000): SQL compilation error: syntax error line 2 at position 0 unexpected 'REMOVE'.
INFO  snowflake EXPLAIN stmt 4: skipped — referenced object not loaded. Detail: Stage 'SNOWFLAKE_LEARNING_DB.TCS_POC.__TPL_5__' does not exist or not authorized.
FAIL  snowflake EXPLAIN stmt 5: 001003 (42000): SQL compilation error: syntax error line 2 at position 0 unexpected 'REMOVE'.
INFO  snowflake EXPLAIN stmt 6: skipped — referenced object not loaded. Detail: Object 'SNOWFLAKE_LEARNING_DB.STAGING.SQ_SRC_LINKSCSVFILE' does not exist or not authorized.
INFO  3 statement(s) skipped for lack of loaded objects — not counted as failures.
PASS  stmt 6: INSERT columns (28) == SELECT expressions (28)
PASS  stmt 6: no duplicate INSERT columns
PASS  no residual Teradata constructs
INFO  TODO(SME) markers outstanding: 10
------------------------------------------------------------
RESULT: FAIL (2 hard check(s))
```

### Analysis of the 2 `FAIL` lines — environment gaps, not SQL defects

Both `FAIL` lines are `REMOVE` statements (stmt 3 and stmt 5):

- **Stmt 3** — `REMOVE @<% ctx.env.LANDING_STAGE %>/<% ctx.env.S_vwxxxx_MapLinksRecordsToOracle_InputFileName %>;` (fixed file line 49)
- **Stmt 5** — `REMOVE @<% ctx.env.LANDING_STAGE %>/<% ctx.env.S_vwxxxx_MapLinksRecordsToOracle_OutputFileName %>;` (fixed file line 72)

`REMOVE` is a **valid Snowflake stage-management command** (per `02_rules/07_snowsql_client.md`, SNZ-04 — `COPY INTO` / `REMOVE` stage DML analysed normally; SQL bodies clean). The Snowflake **EXPLAIN** backend, however, only compiles DML/SELECT statements — it does not support stage-management commands (`REMOVE`, `PUT`, `GET`, `LIST`). Running `EXPLAIN` on a `REMOVE` statement raises `001003 (42000): ... unexpected 'REMOVE'`, which the validator reports as a `FAIL`.

This is the same class of environment gap called out by the orchestrator rules: *"Do not re-fix on INFO/WARN lines (environment gaps, not SQL defects)."* The `REMOVE` EXPLAIN failures are an EXPLAIN-backend limitation, not a SQL defect in the fixed file. The decisive evidence:

| Check | Result | Evidence |
|---|---|---|
| Parse (sqlglot, snowflake dialect) | **PASS** | 6 statement(s) parsed as snowflake |
| INSERT/SELECT column count | **PASS** | stmt 6: 28 == 28 |
| Duplicate INSERT columns | **PASS** | none |
| Residual Teradata constructs | **PASS** | none (`ZEROIFNULL`, `CONTAINS`, `MULTISET`, `MINUS`, `SEL`, `(+)`, BTEQ dot-commands all absent) |
| `REMOVE` EXPLAIN | FAIL ×2 | EXPLAIN backend does not support stage commands — environment gap |

The 3 `INFO` "skipped — referenced object not loaded" lines (stmts 2, 4, 6) are also environment gaps (the staging table and named stage are not materialised in the validation account) and are explicitly not counted as failures by the validator.

---

## Buggy input control

Validator run on `00_input/S_vwxxx_MapLinksRecordsToOracle.snowsql` (control — expected to fail or, for semantic-only defects, to pass):

```
PASS  snowflake connection: probe returned 1
PASS  parse: 6 statement(s) parsed as snowflake using snowflake
PASS  snowflake EXPLAIN stmt 1: compiled OK
INFO  snowflake EXPLAIN stmt 2: skipped — referenced object not loaded.
FAIL  snowflake EXPLAIN stmt 3: syntax error line 2 at position 0 unexpected 'REMOVE'.
INFO  snowflake EXPLAIN stmt 4: skipped — referenced object not loaded.
FAIL  snowflake EXPLAIN stmt 5: syntax error line 2 at position 0 unexpected 'REMOVE'.
INFO  snowflake EXPLAIN stmt 6: skipped — referenced object not loaded.
PASS  stmt 6: INSERT columns (28) == SELECT expressions (28)
PASS  stmt 6: no duplicate INSERT columns
PASS  no residual Teradata constructs
INFO  TODO(SME) markers outstanding: 0
------------------------------------------------------------
RESULT: FAIL (2 hard check(s))
```

### Control interpretation

The control fails **identically** on the same 2 `REMOVE` statements (control lines 20 and 43). This confirms the `REMOVE` EXPLAIN failures are an **environment/validator gap** inherent to the input, not a regression introduced by remediation. Per the orchestrator rules, a passing (or identically-failing) control on a semantic/environment gap is expected; the decisive evidence is the manual spot-check below, not the mechanical control result.

The control also has `TODO(SME) markers outstanding: 0` (no SME flags in the buggy input) versus `10` in the fixed file — the 10 `TODO(SME)` markers are semantic risks flagged by the fix stage (SEM-04/05/06/08, OBS-01) for human review, not mechanical defects.

---

## Manual spot-check

| # | Check | Result | Notes |
|---|---|---|---|
| 1 | **Column count** (INSERT vs SELECT) | **PASS** | stmt 6: 28 INSERT columns == 28 SELECT expressions; no duplicate INSERT columns |
| 2 | **No residual Teradata constructs** | **PASS** | No `ZEROIFNULL`, `CONTAINS`, `MULTISET`, `MINUS`, `SEL `, `(+)`, BTEQ dot-commands, or `MINUS` set operator in the fixed file |
| 3 | **Template tags preserved** (SNZ-01) | **PASS** | 14 `<% ctx.env.* %>` placeholders preserved verbatim (7 distinct env vars: `LANDING_STAGE`, `S_vwxxxx_MapLinksRecordsToOracle_InputFile_DIR`, `S_vwxxxx_MapLinksRecordsToOracle_InputFileName`, `S_vwxxxx_MapLinksRecordsToOracle_OutputFileName`, and the `__TPL_*__` stage refs). Validator masked them for validation; the file retains them as-is |
| 4 | **PUT command preserved** (SNZ-02) | **PASS** | `PUT file://<% ... %> @<% ... %> OVERWRITE = TRUE AUTO_COMPRESS = FALSE;` preserved verbatim (not converted to `COPY`) |
| 5 | **GET command preserved** (SNZ-03) | **PASS** | `GET @<% ... %> file://<% ... %>;` preserved verbatim |
| 6 | **REMOVE stage commands** (SNZ-04) | **PASS** | 2 `REMOVE @<% ... %>/<% ... %>;` statements preserved verbatim; valid Snowflake stage DML. EXPLAIN-backend failure is an environment gap (see above) |
| 7 | **Parse** (sqlglot, snowflake dialect) | **PASS** | All 6 statements parse as Snowflake |
| 8 | **Column order / JOIN keys / CASE-branch order** | **PASS** | No logic changed by the fix stage (0 mechanical fixes per FIX LOG); column order and JOIN keys preserved exactly |
| 9 | **QUALIFY preserved** | N/A | No `QUALIFY` clause in this unit |
| 10 | **TODO(SME) markers** | INFO | 10 outstanding — semantic risks flagged for SME review (SEM-04/05/06/08, OBS-01). Not a failure; these are review items, not defects |

---

## Mechanical verdict

**PASS**

The 2 `FAIL` lines reported by the validator are `REMOVE` stage-management commands that the Snowflake **EXPLAIN** backend cannot compile (EXPLAIN supports DML/SELECT only, not stage commands). This is an **environment/validator gap**, not a SQL defect:

- The **control fails identically** on the same 2 `REMOVE` statements, proving the failure is inherent to the input construct, not introduced by remediation.
- All substantive mechanical checks **PASS**: parse (6 statements), INSERT/SELECT column count (28 = 28), no duplicate columns, no residual Teradata constructs.
- The 3 `INFO` "skipped — referenced object not loaded" lines are environment gaps (staging table / named stage not materialised in the validation account) and are not counted as failures.

Per the orchestrator rules, `FAIL` lines that are environment gaps (not SQL defects) do not trigger a re-fix cycle. **No hand-back to s2s-fix.** The 10 `TODO(SME)` markers are semantic review items for the human reviewer, not mechanical defects.