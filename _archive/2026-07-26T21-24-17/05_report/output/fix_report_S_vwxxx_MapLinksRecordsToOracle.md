# Fix report — `S_vwxxx_MapLinksRecordsToOracle.snowsql`

**Unit:** `S_vwxxx_MapLinksRecordsToOracle` (`.snowsql` template input — `SNZ-*` rules apply)
**Input:** `00_input/S_vwxxx_MapLinksRecordsToOracle.snowsql`
**Fixed:** `03_fix/output/S_vwxxx_MapLinksRecordsToOracle_fixed.snowsql`
**Analysis:** `01_analyze/output/analysis_S_vwxxx_MapLinksRecordsToOracle.md`
**Validation:** `04_validate/output/validation_S_vwxxx_MapLinksRecordsToOracle.md`
**Teradata ground truth:** **Not supplied.** No `00_input/S_vwxxx_MapLinksRecordsToOracle.teradata.sql` exists. Every semantic inference is flagged `TODO(SME)`.
**Overall verdict:** **PASS — 0 mechanical fixes.** Parse-clean Snowflake ETL script; the entire remediation is `TODO(SME)` markers at semantic-risk locations plus `[KEEP]` FIX-LOG lines for the SNZ client layer. No SQL logic lines changed.

---

## 1. Summary

This is a **re-run** of a parse-clean `.snowsql` ETL script that loads a CSV into a transient staging table, extracts a header record to a stage file, and `INSERT OVERWRITE`s detail rows into `STAGING.WRK_FLT_SCHED_LINKS`. The converter output was already valid Snowflake — no residual Teradata constructs, no syntax errors, no defects. The remediation therefore applied **zero mechanical fixes** and instead documented the SNZ client layer (preserved verbatim) and flagged 8 distinct semantic risks as 11 inline `TODO(SME)` markers for reviewer confirmation. A 0-fix run is a valid outcome; no fixes were invented to justify the stage.

| Metric | Value |
|---|---|
| Mechanical fixes (SFX/FNX/DTX/DEF) | **0** |
| SNZ-01 template tags preserved | 14 (7 distinct env vars) |
| SNZ-02 `PUT` preserved | 1 |
| SNZ-03 `GET` preserved | 1 |
| SNZ-04 stage DML (`COPY INTO`/`REMOVE`) preserved | 4 |
| INSERT vs SELECT column count | **28 = 28** PASS |
| Residual Teradata constructs | none |
| `TODO(SME)` markers outstanding | 11 |
| Validation (fixed) | **PASS** |
| Validation (control / buggy input) | **PASS** (expected — semantic-only unit) |

---

## 2. Rules applied

### Syntax / function / datatype (`SFX-*` / `FNX-*` / `DTX-*`)
**None.** The file is parse-clean Snowflake. No `ZEROIFNULL`, `CONTAINS`, `MULTISET`, `(+)`, BTEQ dot-commands, `MINUS`, `SEL`, `CAST(… FORMAT …)`, or other residual Teradata constructs were found. Valid Snowflake syntax used throughout: `CREATE OR REPLACE TRANSIENT TABLE`, `IFF`, `SUBSTR`, `TO_TIMESTAMP`, `INSERT OVERWRITE INTO`, `WHERE … NOT IN`.

### Defects (`DEF-*`)
**None.** No duplicate columns (DEF-01), typos (DEF-02), unbalanced parens (DEF-03), malformed function calls (DEF-04), or INSERT/SELECT count mismatch (DEF-05). The single `INSERT … SELECT` binds 28 target columns to 28 SELECT expressions by ordinal position. Aliases in the `COPY INTO @stage FROM (SELECT …)` header block are cosmetic/positional (DEF-06) — not defects.

### SnowSQL client layer (`SNZ-*`) — KEEP, preserved verbatim
Per `02_rules/07_snowsql_client.md`, every `<% ctx.env.X %>` template tag and every `PUT`/`GET`/`COPY INTO @stage`/`REMOVE` command is classified **KEEP** and preserved verbatim. They are not syntax defects and are not remediated. SQL inside `SNZ-04` stage statements was analysed normally.

| ID | Construct | Count | Action |
|---|---|---|---|
| SNZ-01 | `<% ctx.env.* %>` template placeholders (7 distinct env vars) | 14 | KEEP — preserved verbatim |
| SNZ-02 | `PUT file://… @stage OVERWRITE=TRUE AUTO_COMPRESS=FALSE` | 1 | KEEP — preserved verbatim |
| SNZ-03 | `GET @stage/… file://… OVERWRITE=TRUE` | 1 | KEEP — preserved verbatim |
| SNZ-04 | `COPY INTO @stage FROM (SELECT …)` / `REMOVE @stage/…` | 4 | KEEP shell; SQL bodies analysed (clean) |

### Semantic (`SEM-*`) — flagged, not fixed
No rule forces a mechanical change; each risk is flagged inline as `TODO(SME)` for reviewer confirmation. With no Teradata ground truth, none were applied.

| Rule | Line(s) | Risk | Action |
|---|---|---|---|
| SEM-04 / FNX-14 | 27 | `FIELD2 AS CURRENT_DATE` shadows the `CURRENT_DATE` keyword as an alias | `TODO(SME)` — confirm alias intent vs function |
| SEM-06 / SEM-08 | 31, 34 | `TO_TIMESTAMP(FIELD6 \|\| FIELD7,'DDMONYYHH24MI')` has no NULL guard on the concat, unlike the suffix slots | `TODO(SME)` — confirm NULL handling for FIELD6/7/14/15 |
| OBS-01 (proposed) | 31, 34 | `'DDMONYYHH24MI'` mask is locale-dependent (`MON` case-sensitive) | `TODO(SME)` — confirm CSV date format and locale |
| SEM-05 | 43–72 | Target `WRK_FLT_SCHED_LINKS` DDL not supplied; `INSERT OVERWRITE` makes SET/MULTISET dedup irrelevant | `TODO(SME)` — awareness only, not a gate |
| SEM-03 / DTX-03 | 43–72 | Target column types (CHAR(n) vs VARCHAR) unknown → blank-padding drift risk | `TODO(SME)` — confirm DDL |
| SEM-08 | 43–72 | `IFF(… IS NULL,' ',…)` substitutes a single space, not `''` or NULL | `TODO(SME)` — confirm `' '` vs `''` vs NULL intent |
| SEM-06 / DTX-10 | 43–72 | Implicit string→timestamp cast in `TO_TIMESTAMP` with no `TRY_TO_TIMESTAMP` guard | `TODO(SME)` — confirm source data contract |

No SEM-01 (integer division), SEM-02 (QUALIFY/dedup ordering), SEM-07 (NULL ordering), SEM-09 (empty-set aggregate), or SEM-10 (join direction) risks are present — the script has no divisions, no `QUALIFY`/`ROW_NUMBER`, no `ORDER BY`, no aggregates, and no joins.

---

## 3. Defects repaired
**None.** No `DEF-*` defects were found or repaired.

---

## 4. Open `TODO(SME)` items (11 markers)

All are deferred reviewer confirmations (semantic/typing), not mechanical defects. They do not affect the PASS verdict.

1. **SEM-05** — Target `STAGING.WRK_FLT_SCHED_LINKS` DDL not supplied; SET vs MULTISET unknown (INSERT OVERWRITE makes dedup irrelevant — awareness only).
2. **SEM-03 / DTX-03** — Target column types (CHAR(n) vs VARCHAR) unknown; blank-padding drift risk on downstream joins/anti-joins.
3. **SEM-08** — `IFF(SUBSTR(FIELD5,1,1) IS NULL,' ',…)` substitutes a single space for NULL on `IN_FLT_SFX_CD`.
4. **SEM-04** — `TO_TIMESTAMP(...,'DDMONYYHH24MI')` yields `TIMESTAMP_NTZ`; target `IN_ARR_GMT_FLT_TM` is GMT-named. Confirm NTZ vs TZ/LTZ intent.
5. **SEM-06** — `FIELD6 || FIELD7` concat has no NULL guard (Snowflake `||` returns NULL if any operand is NULL).
6. **OBS-01** — `'DDMONYYHH24MI'` mask is locale-dependent. Confirm CSV date format and locale.
7. **SEM-08** — `IFF(SUBSTR(FIELD13,1,1) IS NULL,' ',…)` substitutes a single space for NULL on `OUT_FLT_SFX_CD`.
8. **SEM-04** — `TO_TIMESTAMP(...,'DDMONYYHH24MI')` yields `TIMESTAMP_NTZ`; target `OUT_DEP_GMT_FLT_TM` is GMT-named.
9. **SEM-06** — `FIELD14 || FIELD15` concat has no NULL guard.
10. **OBS-01** — `'DDMONYYHH24MI'` mask is locale-dependent (second occurrence).
11. **SEM-06 / DTX-10** — Implicit string→timestamp cast in `TO_TIMESTAMP` with no `TRY_TO_TIMESTAMP` guard.

---

## 5. Validation result

**Mechanical: PASS.** Run via `04_validate/validate.py` (sqlglot parse + Snowflake compile checks) on the fixed file:

```
INFO  .snowsql input — masked template tags / PUT-GET commands for validation (preserved as-is in the file).
PASS  parse: 6 statement(s) parsed as snowflake using sqlglot
PASS  stmt 6: INSERT columns (28) == SELECT expressions (28)
PASS  stmt 6: no duplicate INSERT columns
PASS  no residual Teradata constructs
INFO  TODO(SME) markers outstanding: 11
RESULT: PASS
```

| Check | Result |
|---|---|
| Parse (sqlglot, snowflake dialect) | PASS — 6 statements |
| INSERT/SELECT column count (stmt 6) | PASS — 28 == 28 |
| Duplicate INSERT columns (stmt 6) | PASS — none |
| Residual Teradata constructs | PASS — none |
| `.snowsql` template tags / `PUT`/`GET` preserved (SNZ-01) | PASS — masked for validation, untouched in file |
| `TODO(SME)` markers outstanding | INFO — 11 (expected; deferred SME confirmations) |

### Control (buggy input)
The buggy input also PASSes the mechanical validator (parse + 6 statements, 28=28, no residual Teradata). **This is expected and is NOT a re-fix trigger.** This is a semantic-only unit — the open items are SEM-* risks and unknown-target-DDL questions that the mechanical validator cannot detect without loaded objects/DDL. The decisive evidence is the SEM-* inventory and manual spot-check, not the control's mechanical result. (Reinforces the standing lesson: *"A parse PASS is not correctness."*)

### Validator environment note
`REMOVE`/`PUT`/`GET` are stage-management commands. The Snowflake `EXPLAIN` backend supports DML/SELECT only and reports `001003 (42000): … unexpected 'REMOVE'` on `EXPLAIN … REMOVE @stage/…`. This is an **environment gap**, not a SQL defect — the control fails identically on the same statements. No re-fix is warranted; the SNZ layer is preserved verbatim per `07_snowsql_client.md`.

---

## 6. Sign-off checklist

- [x] No residual Teradata constructs remain.
- [x] Column order, JOIN keys, and CASE/IFF branch order preserved exactly (no joins/CASE present; IFF branch order unchanged).
- [x] INSERT vs SELECT column count matches (28 = 28).
- [x] `.snowsql` extension preserved; SNZ-01/02/03/04 constructs preserved verbatim.
- [x] Minimal diff — 0 SQL logic lines changed; only `TODO(SME)` markers and FIX-LOG `[KEEP]` lines added.
- [x] Validation PASS on fixed file; control PASS explained (semantic-only unit).
- [ ] **SME sign-off required** on the 11 open `TODO(SME)` items (target DDL, timestamp NULL-guard, locale mask, NTZ vs GMT intent, empty-string vs NULL suffix guard).

**Stage-6 semantic doc:** see `06_explain/output/semantic_S_vwxxx_MapLinksRecordsToOracle.md` for the clause-by-clause walk-through and the SEM-04/06/08 SME questions. This report references it; it does not duplicate it.