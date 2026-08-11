# Stage 1 — Analysis: `S_vwxxx_MapLinksRecordsToOracle.snowsql`

**Input:** `00_input/S_vwxxx_MapLinksRecordsToOracle.snowsql`
**Type:** `.snowsql` (SnowSQL client script — `SNZ-*` rules apply)
**Teradata ground truth:** **Not supplied.** No `00_input/S_vwxxx_MapLinksRecordsToOracle.teradata.sql` exists. Semantic intent is inferred from `02_rules/` and the Snowflake input alone; every inference is flagged `TODO(SME)`.
**Overall verdict:** **Parse-clean Snowflake.** No residual-Teradata constructs, no syntax errors, no defects. The only findings are `SNZ-*` KEEP items (client layer) and `SEM-*` semantic risks. A 0-mechanical-fix run is a valid outcome.

---

## 0. SnowSQL client-layer inventory (`SNZ-*`) — KEEP

Per `02_rules/07_snowsql_client.md`, every `<% ctx.env.X %>` template tag and every `PUT`/`GET` command is classified **KEEP** (preserve verbatim). They are **not** syntax defects and are **not** remediated. SQL inside `SNZ-04` stage statements is analysed normally.

| Line(s) | ID | Construct | Classification |
|---|---|---|---|
| 13–14 | SNZ-02 | `PUT file://<% ctx.env.S_vwxxxx_MapLinksRecordsToOracle_InputFile_DIR %> @<% ctx.env.LANDING_STAGE %> OVERWRITE=TRUE AUTO_COMPRESS=FALSE` | KEEP |
| 13 | SNZ-01 | `<% ctx.env.S_vwxxxx_MapLinksRecordsToOracle_InputFile_DIR %>` | KEEP |
| 14 | SNZ-01 | `<% ctx.env.LANDING_STAGE %>` | KEEP |
| 17 | SNZ-01 | `<% ctx.env.LANDING_STAGE %>` (in `COPY INTO … FROM @…`) | KEEP |
| 17 | SNZ-01 | `<% ctx.env.S_vwxxxx_MapLinksRecordsToOracle_InputFileName %>` | KEEP |
| 20 | SNZ-04 | `REMOVE @<% ctx.env.LANDING_STAGE %>/<% …InputFileName %>` | KEEP (stage DML; valid SQL, but `REMOVE` not EXPLAIN-able — see validator note) |
| 20 | SNZ-01 | `<% ctx.env.LANDING_STAGE %>`, `<% ctx.env.S_vwxxxx_MapLinksRecordsToOracle_InputFileName %>` | KEEP |
| 24 | SNZ-04 | `COPY INTO @<% ctx.env.LANDING_STAGE %>/<% …OutputFileName %> FROM ( SELECT … )` | KEEP shell; **SQL body analysed normally** (see §3/§5) |
| 24 | SNZ-01 | `<% ctx.env.LANDING_STAGE %>`, `<% ctx.env.S_vwxxxx_MapLinksRecordsToOracle_OutputFileName %>` | KEEP |
| 37–38 | SNZ-03 | `GET @<% ctx.env.LANDING_STAGE %>/<% …OutputFileName %> file://<% ctx.env.S_vwxxxx_MapLinksRecordsToOracle_OutputFileName_DIR %> OVERWRITE=TRUE` | KEEP |
| 37 | SNZ-01 | `<% ctx.env.LANDING_STAGE %>`, `<% ctx.env.S_vwxxxx_MapLinksRecordsToOracle_OutputFileName %>` | KEEP |
| 38 | SNZ-01 | `<% ctx.env.S_vwxxxx_MapLinksRecordsToOracle_OutputFileName_DIR %>` | KEEP |
| 40 | SNZ-04 | `REMOVE @<% ctx.env.LANDING_STAGE %>/<% …OutputFileName %>` | KEEP (stage DML; not EXPLAIN-able) |
| 40 | SNZ-01 | `<% ctx.env.LANDING_STAGE %>`, `<% ctx.env.S_vwxxxx_MapLinksRecordsToOracle_OutputFileName %>` | KEEP |

**Counts:** 9 distinct `<% ctx.env.* %>` template tags (SNZ-01), 1 `PUT` (SNZ-02), 1 `GET` (SNZ-03), 2 `REMOVE` + 2 `COPY INTO @stage` (SNZ-04). All preserved verbatim; not remediated.

> **Validator note (environment gap, not a defect):** `REMOVE`/`PUT`/`GET` are stage-management commands. The Snowflake `EXPLAIN` backend supports DML/SELECT only and reports `001003 (42000): … unexpected 'REMOVE'` on `EXPLAIN … REMOVE @stage/…`. This is an environment gap, not a SQL defect — the control (buggy input) fails identically on the same statements. Do **not** re-fix. Document in the validation report.

---

## 1. Column-count check (INSERT … SELECT)

Only one `INSERT … SELECT` in the file (the `INSERT OVERWRITE INTO STAGING.WRK_FLT_SCHED_LINKS` block, lines 43–72).

**INSERT target columns (28):**
`LINK_STN_CD, IN_ORIGN_STN_CD, IN_ALN_CD, IN_FLT_NO, IN_FLT_SFX_CD, IN_DEP_GMT_FLT_DT, IN_ARR_GMT_FLT_DT, IN_ARR_GMT_FLT_TM, IN_PAX_TML_CD, IN_GROUND_ACY_CD, IN_SERVICE_TYP, OUT_DESTN_STN_CD, OUT_ALN_CD, OUT_FLT_NO, OUT_FLT_SFX_CD, OUT_DEP_GMT_FLT_DT, OUT_DEP_GMT_FLT_TM, OUT_ARR_GMT_FLT_DT, OUT_PAX_TML_CD, OUT_GROUND_ACY_CD, OUT_SERVICE_TYP, AIRCRAFT_OWNER_CD, CARRIER_AC_TYP, MIDNIGHT_QTY, BUFFER_DUR, STD_WORKING_DUR, TOW_TIME_DUR, FIXED_LINK_RSN_TXT`

**SELECT expressions (28):**
`SUBSTR(FIELD2,1,3), FIELD25, SUBSTR(FIELD3,1,3), SUBSTR(FIELD4,1,4), IFF(SUBSTR(FIELD5,1,1) IS NULL,' ',SUBSTR(FIELD5,1,1)), FIELD26, FIELD6, TO_TIMESTAMP(FIELD6 || FIELD7,'DDMONYYHH24MI'), FIELD9, FIELD18, FIELD20, FIELD27, FIELD11, FIELD12, IFF(SUBSTR(FIELD13,1,1) IS NULL,' ',SUBSTR(FIELD13,1,1)), FIELD14, TO_TIMESTAMP(FIELD14 || FIELD15,'DDMONYYHH24MI'), FIELD28, FIELD10, FIELD19, FIELD21, FIELD22, SUBSTR(FIELD1,1,3), FIELD8, FIELD16, FIELD17, FIELD23, FIELD24`

| Side | Count | Duplicates | Net |
|---|---|---|---|
| INSERT target cols | 28 | none | 28 |
| SELECT expressions | 28 | none | 28 |

**Verdict: 28 = 28. No count mismatch. No DEF-05.**

---

## 2. Syntax errors / residual-Teradata constructs

Scanned for every construct in `02_rules/01_syntax_fixes.md` and `03_function_fixes.md`:
`CONTAINS`/`OVERLAPS`, `ZEROIFNULL`/`NULLIFZERO`, `SEL`, `SET`/`MULTISET`, `PRIMARY INDEX`, `COLLECT STATS`, BTEQ directives, `(+)` joins, `MINUS`, `TOP`, `CAST(… FORMAT …)`.

| Line | Construct | Rule | Finding |
|---|---|---|---|
| — | — | — | **None found.** The file is parse-clean Snowflake. |

**No SFX-* / FNX-* / DTX-* findings.** The script uses valid Snowflake syntax throughout: `CREATE OR REPLACE TRANSIENT TABLE`, `IFF`, `SUBSTR`, `TO_TIMESTAMP`, `INSERT OVERWRITE INTO`, `WHERE … NOT IN`.

---

## 3. Defects (`DEF-*`)

| Line | Defect | Rule | Classification |
|---|---|---|---|
| — | — | — | **None found.** |

No duplicate columns (DEF-01), no typos (DEF-02), no unbalanced parens (DEF-03), no malformed function calls (DEF-04), no count mismatch (DEF-05). Aliases in the `COPY INTO @stage FROM (SELECT …)` header block (lines 27–30) are cosmetic and positional (DEF-06) — not defects.

---

## 4. Semantic risks (`SEM-*`)

These parse fine but may change results. With no Teradata ground truth, each is flagged `TODO(SME)`.

| Line(s) | Risk | Rule | Detail | Classification |
|---|---|---|---|---|
| 27 | `CURRENT_DATE` used as a column alias | SEM-04 / FNX-14 | `SELECT FIELD2 AS CURRENT_DATE, …` shadows the Snowflake `CURRENT_DATE` keyword/function inside this `COPY INTO @stage FROM (SELECT …)` block. Snowflake allows it as an alias, but it is fragile and could confuse downstream consumers / re-derivation. Confirm against Teradata ground truth whether the alias was intended (likely a header label, not the function). | SME |
| 31 | `TO_TIMESTAMP(FIELD6 \|\| FIELD7,'DDMONYYHH24MI')` — NULL guard asymmetry | SEM-06 / SEM-08 | The suffix slots are guarded with `IFF(SUBSTR(FIELDx,1,1) IS NULL,' ',…)`, but the date+time concatenation `FIELD6 \|\| FIELD7` has **no** NULL guard. Snowflake `\|\|` returns NULL if any operand is NULL, so a NULL `FIELD7` makes the whole timestamp NULL (or errors in `TO_TIMESTAMP`). Asymmetric with the suffix handling. Flag `TODO(SME)` — do not add a guard without confirming the source data contract. | SME |
| 31 | `'DDMONYYHH24MI'` format mask — locale-dependent | (proposed OBS-01) | `MON` is case-sensitive and locale-dependent in Snowflake `TO_TIMESTAMP`. With no Teradata ground truth, the CSV date format and session locale cannot be verified. Flag `TODO(SME)`. Consider proposing a formal `OBS-01` rule in `02_rules/05_semantic_rules.md` for locale-dependent date masks. | SME |
| 34 | `TO_TIMESTAMP(FIELD14 \|\| FIELD15,'DDMONYYHH24MI')` — same NULL-guard asymmetry | SEM-06 / SEM-08 | Identical pattern to line 31. No NULL guard on `FIELD14`/`FIELD15`. | SME |
| 34 | `'DDMONYYHH24MI'` format mask — locale-dependent | (proposed OBS-01) | Same as line 31. | SME |
| 43–72 | `INSERT OVERWRITE INTO STAGING.WRK_FLT_SCHED_LINKS` — SET-table? | SEM-05 | Single `INSERT OVERWRITE` into `STAGING.WRK_FLT_SCHED_LINKS`. `INSERT OVERWRITE` truncates-then-inserts, so SET-vs-MULTISET dedup is **not** in play for this statement (overwrite semantics replace, not dedup). However, the target's `CREATE TABLE` DDL is **not** supplied, so the target type (SET/MULTISET, column types, CHAR vs VARCHAR) cannot be confirmed. Raise SME question on target DDL. **Not** a SET-dedup signal (overwrite, not append). | SME |
| 43–72 | Target column types unknown (CHAR padding drift) | SEM-03 / DTX-03 | Target columns `*_CD`, `*_TYP`, `*_TXT` may be `CHAR(n)` in the real DDL. Teradata blank-pads `CHAR(n)` and ignores trailing spaces in `=`; Snowflake does not pad. With no DDL, cannot confirm. Affects downstream joins/anti-joins against this target. Flag `TODO(SME)`. | SME |
| 43–72 | `IFF(SUBSTR(FIELDx,1,1) IS NULL,' ',SUBSTR(FIELDx,1,1))` — empty-string vs NULL | SEM-08 | The suffix guard substitutes a single space `' '` for NULL. Snowflake treats `' '` and `''` as real strings, not NULL. Confirm against Teradata whether the original used `''` or `' '` and whether the target column is `CHAR(1)` (padded) or `VARCHAR`. Flag `TODO(SME)`. | SME |
| 43–72 | Implicit string→timestamp cast in `TO_TIMESTAMP` | SEM-06 / DTX-10 | `TO_TIMESTAMP(FIELD6 \|\| FIELD7, 'DDMONYYHH24MI')` relies on `FIELD6`/`FIELD7` being well-formed strings matching the mask. No `TRY_TO_TIMESTAMP` guard; a malformed CSV cell errors the whole row. Confirm source data contract. Flag `TODO(SME)`. | SME |

**No SEM-01 (integer division), SEM-02 (QUALIFY/dedup ordering), SEM-07 (NULL ordering), SEM-09 (empty-set aggregate), SEM-10 (join direction) risks present** — there are no divisions, no `QUALIFY`/`ROW_NUMBER`, no `ORDER BY`, no aggregates, and no joins in this script.

---

## 5. Classification summary

| Classification | Count | Items |
|---|---|---|
| AUTO | 0 | — |
| FIX | 0 | — |
| SME | 8 | SEM-04/FNX-14 (CURRENT_DATE alias), SEM-06/08 ×2 (NULL-guard asymmetry on timestamp concat), OBS-01 ×2 (locale-dependent date mask), SEM-05 (target DDL unknown), SEM-03/DTX-03 (CHAR padding), SEM-08 (empty-string vs NULL in suffix guard), SEM-06/DTX-10 (implicit cast in TO_TIMESTAMP) |
| KEEP | 9 SNZ-01 + 1 SNZ-02 + 1 SNZ-03 + 4 SNZ-04 | Client layer — preserved verbatim, not remediated |

**Mechanical fixes required: 0.** This is a parse-clean `.snowsql` ETL script. The entire remediation is `TODO(SME)` markers at semantic-risk locations plus `[KEEP]` lines in the FIX LOG for SNZ constructs. Zero SQL logic lines should change.

---

## 6. Table dependency inventory

| Role | Table / Stage | Lines | Notes |
|---|---|---|---|
| Created (transient staging) | `STAGING.Sq_Src_LinksCSVFile` | 1–11 | 28-column VARCHAR staging table for raw CSV load |
| Source (read) | `STAGING.Sq_Src_LinksCSVFile` | 28–31, 64–72 | Read by the header-extract `COPY INTO @stage FROM (SELECT …)` and by the `INSERT OVERWRITE … SELECT` |
| Target (written, overwrite) | `STAGING.WRK_FLT_SCHED_LINKS` | 43–72 | `INSERT OVERWRITE INTO` — truncate-then-insert. **DDL not supplied** → target column types/SET-vs-MULTISET unknown (SME) |
| Stage (client) | `@<% ctx.env.LANDING_STAGE %>` | 13–40 | SnowSQL stage; PUT/COPY/REMOVE/GET operate here. SNZ-01/02/03/04 — KEEP |

**One-line verdict:** Parse-clean Snowflake ETL script (CSV → transient staging → header extract to stage → detail `INSERT OVERWRITE` into `WRK_FLT_SCHED_LINKS`). No mechanical fixes; 8 SME-flagged semantic risks (timestamp NULL-guard asymmetry, locale-dependent date mask, unknown target DDL/CHAR-padding, empty-string-vs-NULL suffix guard) plus the SNZ client layer preserved verbatim. Awaiting SME/DDL confirmation.