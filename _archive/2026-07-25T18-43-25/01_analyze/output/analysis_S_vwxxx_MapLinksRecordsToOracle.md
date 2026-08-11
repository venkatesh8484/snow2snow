# Stage 1 — Analysis: `S_vwxxx_MapLinksRecordsToOracle.snowsql`

**Input:** `00_input/S_vwxxx_MapLinksRecordsToOracle.snowsql`
**Teradata ground truth:** none supplied (no `00_input/<name>.teradata.sql`).
**Input type:** `.snowsql` — SnowSQL client layer rules (`SNZ-*`) apply.

---

## 1. Column-count check (INSERT … SELECT)

There is one `INSERT … SELECT` (lines 63–101).

| Side | Count | Duplicates | Net |
|---|---|---|---|
| INSERT target columns (lines 64–71) | 28 | none | 28 |
| SELECT expressions (lines 73–100) | 28 | none | 28 |

**Verdict: 28 = 28 — PASS.** No DEF-05 column-count mismatch. No DEF-01
duplicate columns on either side.

INSERT target list (positional):

| # | Target column | # | Target column |
|---|---|---|---|
| 1 | LINK_STN_CD | 15 | OUT_FLT_SFX_CD |
| 2 | IN_ORIGN_STN_CD | 16 | OUT_DEP_GMT_FLT_DT |
| 3 | IN_ALN_CD | 17 | OUT_DEP_GMT_FLT_TM |
| 4 | IN_FLT_NO | 18 | OUT_ARR_GMT_FLT_DT |
| 5 | IN_FLT_SFX_CD | 19 | OUT_PAX_TML_CD |
| 6 | IN_DEP_GMT_FLT_DT | 20 | OUT_GROUND_ACY_CD |
| 7 | IN_ARR_GMT_FLT_DT | 21 | OUT_SERVICE_TYP |
| 8 | IN_ARR_GMT_FLT_TM | 22 | AIRCRAFT_OWNER_CD |
| 9 | IN_PAX_TML_CD | 23 | CARRIER_AC_TYP |
| 10 | IN_GROUND_ACY_CD | 24 | MIDNIGHT_QTY |
| 11 | IN_SERVICE_TYP | 25 | BUFFER_DUR |
| 12 | OUT_DESTN_STN_CD | 26 | STD_WORKING_DUR |
| 13 | OUT_ALN_CD | 27 | TOW_TIME_DUR |
| 14 | OUT_FLT_NO | 28 | FIXED_LINK_RSN_TXT |

SELECT expression list (positional):

| # | Expression | Maps to |
|---|---|---|
| 1 | `SUBSTR(FIELD2,1,3)` | LINK_STN_CD |
| 2 | `FIELD25` | IN_ORIGN_STN_CD |
| 3 | `SUBSTR(FIELD3,1,3)` | IN_ALN_CD |
| 4 | `SUBSTR(FIELD4,1,4)` | IN_FLT_NO |
| 5 | `IFF(SUBSTR(FIELD5,1,1) IS NULL,' ',SUBSTR(FIELD5,1,1))` | IN_FLT_SFX_CD |
| 6 | `FIELD26` | IN_DEP_GMT_FLT_DT |
| 7 | `FIELD6` | IN_ARR_GMT_FLT_DT |
| 8 | `TO_TIMESTAMP(FIELD6 \|\| FIELD7,'DDMONYYHH24MI')` | IN_ARR_GMT_FLT_TM |
| 9 | `FIELD9` | IN_PAX_TML_CD |
| 10 | `FIELD18` | IN_GROUND_ACY_CD |
| 11 | `FIELD20` | IN_SERVICE_TYP |
| 12 | `FIELD27` | OUT_DESTN_STN_CD |
| 13 | `FIELD11` | OUT_ALN_CD |
| 14 | `FIELD12` | OUT_FLT_NO |
| 15 | `IFF(SUBSTR(FIELD13,1,1) IS NULL,' ',SUBSTR(FIELD13,1,1))` | OUT_FLT_SFX_CD |
| 16 | `FIELD14` | OUT_DEP_GMT_FLT_DT |
| 17 | `TO_TIMESTAMP(FIELD14 \|\| FIELD15,'DDMONYYHH24MI')` | OUT_DEP_GMT_FLT_TM |
| 18 | `FIELD28` | OUT_ARR_GMT_FLT_DT |
| 19 | `FIELD10` | OUT_PAX_TML_CD |
| 20 | `FIELD19` | OUT_GROUND_ACY_CD |
| 21 | `FIELD21` | OUT_SERVICE_TYP |
| 22 | `FIELD22` | AIRCRAFT_OWNER_CD |
| 23 | `SUBSTR(FIELD1,1,3)` | CARRIER_AC_TYP |
| 24 | `FIELD8` | MIDNIGHT_QTY |
| 25 | `FIELD16` | BUFFER_DUR |
| 26 | `FIELD17` | STD_WORKING_DUR |
| 27 | `FIELD23` | TOW_TIME_DUR |
| 28 | `FIELD24` | FIXED_LINK_RSN_TXT |

---

## 2. Syntax errors / residual-Teradata constructs

| # | Line | Construct | Rule | Why invalid / action | Class |
|---|---|---|---|---|---|
| — | — | — | — | **No residual-Teradata syntax constructs found.** No `ZEROIFNULL`, `CONTAINS`, `OVERLAPS`, `SEL`, `SET`/`MULTISET`, `PRIMARY INDEX`, `COLLECT STATS`, BTEQ directives, `(+)` joins, `MINUS`, `TOP`, or `FORMAT`-casts. The file is parse-clean Snowflake SQL (once SNZ template tags are masked). | — |

No `SFX-*`, `FNX-*`, or `DTX-*` rules fire. The SQL body uses only valid
Snowflake functions (`SUBSTR`, `IFF`, `TO_TIMESTAMP`, `COALESCE`-equivalent
`IFF(... IS NULL, ...)`).

---

## 3. Defects (DEF-*)

| # | Line | Defect | Rule | Class |
|---|---|---|---|---|
| — | — | No DEF-01..DEF-07 defects detected. Parentheses are balanced, function calls are well-formed, no duplicate columns, INSERT/SELECT counts match (28=28), no malformed `CAST`. | — | — |

---

## 4. Semantic risks (SEM-*)

| # | Line(s) | Risk | Rule | Present? | Notes | Class |
|---|---|---|---|---|---|---|
| SEM-01 | — | Integer division | SEM-01 | **No.** No `/` arithmetic division in the file. | — | — |
| SEM-02 | — | QUALIFY / dedup ordering | SEM-02 | **No.** No `QUALIFY` or `ROW_NUMBER()` dedup. | — | — |
| SEM-03 | — | CHAR(n) padding & comparison | SEM-03 | **No.** All staging columns are `VARCHAR(n)`; no `CHAR(n)` comparisons. | — | — |
| SEM-04 | 8, 17 | Timestamp / timezone | SEM-04 | **Yes.** Two `TO_TIMESTAMP(FIELD6 \|\| FIELD7,'DDMONYYHH24MI')` calls (lines 80, 88) produce `TIMESTAMP_NTZ` by default. Target columns are named `*_GMT_FLT_TM` (GMT flight time), so NTZ is plausibly correct, but the session `TIMEZONE` and the intended TZ of these timestamps must be confirmed. No `TIMESTAMP_TZ` / `TIMESTAMP_LTZ` used. | **SME** |
| SEM-05 | 63 | SET-table dedup | SEM-05 | **Yes — SME question.** Single `INSERT OVERWRITE INTO STAGING.WRK_FLT_SCHED_LINKS`. `INSERT OVERWRITE` replaces the whole target, so SET-vs-MULTISET dedup is **not** in play for this statement (overwrite truncates first). However, no `CREATE TABLE` DDL for `STAGING.WRK_FLT_SCHED_LINKS` is supplied in this script, so the target's SET/MULTISET nature is unknown. Because `OVERWRITE` semantics make dedup irrelevant here, this is flagged for awareness only — **not** a blocking gate. | **SME** (low priority) |
| SEM-06 | 80, 88 | Implicit cast / NULL in comparison | SEM-06 | **Yes.** `TO_TIMESTAMP(FIELD6 \|\| FIELD7,'DDMONYYHH24MI')` relies on implicit string concatenation of two `VARCHAR` CSV fields. If `FIELD7` is NULL or empty, `FIELD6 \|\| FIELD7` yields `FIELD6` alone (or NULL if either side is NULL under `||`? — Snowflake `||` returns NULL if any operand is NULL), and `TO_TIMESTAMP` will either error or produce a wrong value. The `IFF(... IS NULL,' ',...)` pattern is used for the suffix fields (5, 13) but **not** for the date+time concatenation fields (6+7, 14+15). Confirm NULL handling for `FIELD6`/`FIELD7`/`FIELD14`/`FIELD15`. | **SME** |
| SEM-06b | 78, 86 | `IFF(x IS NULL,' ',x)` empty-string vs NULL | SEM-08 | **Yes.** `IFF(SUBSTR(FIELD5,1,1) IS NULL,' ',SUBSTR(FIELD5,1,1))` substitutes a single space `' '` for NULL, not an empty string. This matches a likely Teradata intent (pad with space), but confirm whether the target `IN_FLT_SFX_CD` / `OUT_FLT_SFX_CD` expects `' '` vs `''` vs NULL. | **SME** |
| SEM-07 | — | NULL ordering | SEM-07 | **No.** No `ORDER BY` feeding `QUALIFY`/`TOP`. | — | — |
| SEM-08 | 78, 86 | Empty string vs NULL | SEM-08 | **Yes** (see SEM-06b above). | **SME** |
| SEM-09 | — | Aggregate of empty set | SEM-09 | **No.** No aggregates. | — | — |
| SEM-10 | — | Join-key grain mismatch | SEM-10 | **No.** No joins; single-table SELECT from `STAGING.Sq_Src_LinksCSVFile`. | — | — |

**Additional semantic observations (no rule ID yet — propose for review):**

| # | Line | Observation | Class |
|---|---|---|---|
| OBS-01 | 80, 88 | `TO_TIMESTAMP(FIELD6 \|\| FIELD7,'DDMONYYHH24MI')` — the format mask `'DDMONYYHH24MI'` assumes `FIELD6` is a date like `01JAN23` and `FIELD7` is a time like `1430`. `TO_TIMESTAMP` in Snowflake accepts this mask, but `MON` is case-sensitive locale-dependent. Confirm the CSV date format and locale. No Teradata ground truth to verify against. | **SME** |
| OBS-02 | 80, 88 | `FIELD6` is used twice: once as `IN_ARR_GMT_FLT_DT` (pos 7, line 79, raw string) and once concatenated with `FIELD7` into `IN_ARR_GMT_FLT_TM` (pos 8, line 80). Similarly `FIELD14` is used as `OUT_DEP_GMT_FLT_DT` (pos 16) and in the timestamp concat (pos 17). This is intentional (date string reused inside the timestamp), not a defect — but confirm against ground truth. | **SME** |
| OBS-03 | 63 | `INSERT OVERWRITE INTO` is valid Snowflake syntax (truncates then inserts). No change needed. | — |

---

## 5. SnowSQL client layer inventory (SNZ-*)

This is a `.snowsql` file. Per `02_rules/07_snowsql_client.md`, every template
tag and `PUT`/`GET` command is classified **KEEP** — preserve verbatim, never
rewrite, never report as a syntax defect.

### SNZ-01 — Template placeholders (`<% ctx.env.X %>`)

| # | Line | Tag | Class |
|---|---|---|---|
| 1 | 11 | `<% ctx.env.S_vwxxxx_MapLinksRecordsToOracle_InputFile_DIR %>` | KEEP |
| 2 | 12 | `<% ctx.env.LANDING_STAGE %>` | KEEP |
| 3 | 15 | `<% ctx.env.LANDING_STAGE %>` | KEEP |
| 4 | 15 | `<% ctx.env.S_vwxxxx_MapLinksRecordsToOracle_InputFileName %>` | KEEP |
| 5 | 18 | `<% ctx.env.LANDING_STAGE %>` | KEEP |
| 6 | 18 | `<% ctx.env.S_vwxxxx_MapLinksRecordsToOracle_InputFileName %>` | KEEP |
| 7 | 23 | `<% ctx.env.LANDING_STAGE %>` | KEEP |
| 8 | 23 | `<% ctx.env.S_vwxxxx_MapLinksRecordsToOracle_OutputFileName %>` | KEEP |
| 9 | 34 | `<% ctx.env.LANDING_STAGE %>` | KEEP |
| 10 | 34 | `<% ctx.env.S_vwxxxx_MapLinksRecordsToOracle_OutputFileName %>` | KEEP |
| 11 | 36 | `<% ctx.env.LANDING_STAGE %>` | KEEP |
| 12 | 36 | `<% ctx.env.S_vwxxxx_MapLinksRecordsToOracle_OutputFileName_DIR %>` | KEEP |
| 13 | 39 | `<% ctx.env.LANDING_STAGE %>` | KEEP |
| 14 | 39 | `<% ctx.env.S_vwxxxx_MapLinksRecordsToOracle_OutputFileName %>` | KEEP |

**14 template-tag occurrences** (7 distinct env vars). All KEEP.

### SNZ-02 — `PUT` command

| # | Line | Command | Class |
|---|---|---|---|
| 1 | 10–13 | `PUT file://<% ... %> @<% ... %> OVERWRITE = TRUE AUTO_COMPRESS = FALSE;` | KEEP |

### SNZ-03 — `GET` command

| # | Line | Command | Class |
|---|---|---|---|
| 1 | 35–37 | `GET @<% ... %>/<% ... %> file://<% ... %> OVERWRITE = TRUE;` | KEEP |

### SNZ-04 — Stage DML (valid Snowflake SQL — analysed normally)

| # | Line | Statement | Notes |
|---|---|---|---|
| 1 | 14–16 | `COPY INTO STAGING.Sq_Src_LinksCSVFile FROM @<% ... %>/<% ... %> FILE_FORMAT=(...)` | Valid SQL; the `@stage`/`<% %>` parts are KEEP, the rest is normal SQL. No issues. |
| 2 | 18 | `REMOVE @<% ... %>/<% ... %>;` | Valid SQL. No issues. |
| 3 | 22–33 | `COPY INTO @<% ... %>/<% ... %> FROM (SELECT FIELD2 AS CURRENT_DATE, FIELD3 AS SCHEDULE_NAME, FIELD5 AS PERIOD_START, FIELD6 AS PERIOD_END FROM STAGING.Sq_Src_LinksCSVFile WHERE FIELD1='LINKS') FILE_FORMAT=(...) SINGLE=TRUE OVERWRITE=TRUE;` | Valid SQL. Inner SELECT analysed: no SFX/FNX/DEF/SEM issues. **Note:** `FIELD2 AS CURRENT_DATE` — `CURRENT_DATE` is a reserved-ish Snowflake function name used as a column alias here. Inside a `COPY INTO ... FROM (SELECT ...)` it is a column alias in the output file, not a SQL function call, so it parses. Low risk; flag for awareness. |
| 4 | 39 | `REMOVE @<% ... %>/<% ... %>;` | Valid SQL. No issues. |

---

## 6. Classification summary

| Class | Count | Items |
|---|---|---|
| AUTO | 0 | — |
| FIX | 0 | — |
| SME | 5 | SEM-04 (timestamp TZ), SEM-05 (target SET/MULTISET — low, OVERWRITE), SEM-06 (NULL in `||` concat), SEM-06b/SEM-08 (`' '` vs NULL vs `''` for suffix), OBS-01 (date format mask/locale) |
| KEEP | 16 | 14 SNZ-01 template tags + 1 SNZ-02 PUT + 1 SNZ-03 GET |

**No mechanical fixes (AUTO/FIX) are required.** The SQL body is parse-clean
Snowflake. All findings are semantic SME questions or SnowSQL client-layer
KEEP items.

---

## 7. Table dependency inventory

| Role | Table / Stage | Type | Notes |
|---|---|---|---|
| Target (CREATE) | `STAGING.Sq_Src_LinksCSVFile` | Transient table | Created in-script (lines 1–9). 28 `VARCHAR` columns `FIELD1`..`FIELD28`. |
| Source (SELECT) | `STAGING.Sq_Src_LinksCSVFile` | Table | Read by the header-extract `COPY INTO` (line 26) and the detail `INSERT … SELECT` (line 101). |
| Target (INSERT) | `STAGING.WRK_FLT_SCHED_LINKS` | Table | Target of `INSERT OVERWRITE` (line 63). **No DDL supplied in this script** — SET/MULTISET unknown (SEM-05, low priority due to OVERWRITE). |
| Stage | `@<% ctx.env.LANDING_STAGE %>` | Named stage | Used by `PUT`, `COPY INTO`, `REMOVE`, `GET`. Resolved by orchestrator (SNZ-01). |

---

## 8. Verdict

**Parse-clean `.snowsql` ETL script — 0 mechanical fixes needed; 5 SME semantic
questions (timestamp TZ, NULL-in-concatenation, space-vs-NULL suffix, date
format mask, target SET/MULTISET awareness) and 16 SnowSQL client-layer KEEP
items (14 template tags, 1 PUT, 1 GET). Column count 28 = 28 PASS. No Teradata
ground truth supplied; every semantic inference is flagged `TODO(SME)`.**