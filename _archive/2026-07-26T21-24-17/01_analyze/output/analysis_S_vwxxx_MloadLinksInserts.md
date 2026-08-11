# Stage 1 — Analysis: `S_vwxxx_MloadLinksInserts.snowsql`

**Input:** `00_input/S_vwxxx_MloadLinksInserts.snowsql`
**Input type:** `.snowsql` (SnowSQL client layer applies — `02_rules/07_snowsql_client.md`)
**Teradata ground truth:** **Not supplied** (no `00_input/S_vwxxx_MloadLinksInserts.teradata.sql`).
All semantic inferences are therefore flagged `TODO(SME)` and derived from
`02_rules/` + the Snowflake input alone.

**Unit summary:** A single `INSERT … SELECT … WHERE NOT EXISTS` anti-join that
loads new flight-folder-link rows from `STAGING.ExpFinalyseInserts` into
`BASE.FLT_FOLDER_LINKS`, suppressing rows already present on all 33 key columns.

---

## 0. SnowSQL client-layer inventory (SNZ-*)

Per `02_rules/07_snowsql_client.md`, every `<% ctx.env.X %>` template tag
(SNZ-01) and every `PUT`/`GET` command (SNZ-02/03) must be inventoried and
classified `KEEP` — never `AUTO`/`FIX`/`SME`, never reported as a syntax defect.

| Line | Construct | ID | Classification |
|---|---|---|---|
| — | (none) | — | — |

**SNZ inventory is empty.** This `.snowsql` file contains no `<% %>` template
tags, no `PUT`/`GET` commands, and no `COPY INTO @stage` / `REMOVE` / `LIST`
stage DML (SNZ-04). The `.snowsql` extension is still preserved on the fixed
output for validator masking-path consistency (per the 2026-07-24 lesson for
this same unit: dropping the extension would silently change which validation
branch runs).

---

## 1. Column-count check (INSERT target vs SELECT expressions)

| Side | Count | Duplicates | Net (after dedupe) |
|---|---|---|---|
| INSERT target columns | 33 | none | 33 |
| SELECT expressions | 33 | none | 33 |

**Verdict: 33 = 33 — counts match, no duplicates on either side.** No DEF-05
mismatch. The SELECT aliases (`NEW_*`) are cosmetic — `INSERT … SELECT` binds
by ordinal position (DEF-06), so alias-vs-target-name drift does not affect
correctness, only readability.

### INSERT target ↔ SELECT expression positional map

| # | INSERT target | SELECT expression | Notes |
|---|---|---|---|
| 1 | `LINK_STATION_CD` | `NEW_LINK_STATION_CD` | |
| 2 | `IN_ORIGN_STATION_CD` | `NEW_IN_ORIGN_STATION_CD` | |
| 3 | `IN_ALN_CD` | `NEW_IN_ALN_CD` | |
| 4 | `IN_FLT_NO` | `NEW_IN_FLT_NO_SMALLINT` | `_SMALLINT` suffix → SEM-06 |
| 5 | `IN_FLT_SFX_CD` | `NEW_IN_FLT_SFX_CD` | |
| 6 | `IN_DEP_FLTDT` | `NEW_IN_DEP_FLTDT_DATE` | `_DATE` suffix → SEM-06 |
| 7 | `IN_ARR_FLTDT` | `NEW_IN_ARR_FLTDT_DATE` | `_DATE` suffix → SEM-06 |
| 8 | `IN_ARR_FLTTM` | `NEW_IN_ARR_FLTTM_DATE` | `_DATE` suffix on a `_TM` target → SEM-06 |
| 9 | `IN_PAX_TML_CD` | `NEW_IN_PAX_TML_CD` | |
| 10 | `IN_GROUND_ACY_CD` | `NEW_IN_GROUND_ACY_CD` | |
| 11 | `IN_SERVICE_TYP` | `NEW_IN_SERVICE_TYP` | |
| 12 | `IN_FLT_LEG_SEQ_NO` | `NEW_IN_FLT_LEG_SEQ_NO` | |
| 13 | `OUT_DESTATION_STATION_CD` | `NEW_OUT_DESTATION_STATION_CD` | |
| 14 | `OUT_ALN_CD` | `NEW_OUT_ALN_CD` | |
| 15 | `OUT_FLT_NO` | `NEW_OUT_FLT_NO_SMALLINT` | `_SMALLINT` suffix → SEM-06 |
| 16 | `OUT_FLT_SFX_CD` | `NEW_OUT_FLT_SFX_CD` | |
| 17 | `OUT_DEP_FLTDT` | `NEW_OUT_DEP_FLTDT_DATE` | `_DATE` suffix → SEM-06 |
| 18 | `OUT_DEP_FLTTM` | `NEW_OUT_DEP_FLTTM_DATE` | `_DATE` suffix on a `_TM` target → SEM-06 |
| 19 | `OUT_ARR_FLTDT` | `NEW_OUT_ARR_FLTDT_DATE` | `_DATE` suffix → SEM-06 |
| 20 | `OUT_PAX_TML_CD` | `NEW_OUT_PAX_TML_CD` | |
| 21 | `OUT_GROUND_ACY_CD` | `NEW_OUT_GROUND_ACY_CD` | |
| 22 | `OUT_SERVICE_TYP` | `NEW_OUT_SERVICE_TYP` | |
| 23 | `OUT_FLT_LEG_SEQ_NO` | `NEW_OUT_FLT_LEG_SEQ_NO` | |
| 24 | `AIRCRAFT_OWNER_CD` | `NEW_AIRCRAFT_OWNER_CD` | |
| 25 | `CARRIER_AC_TYP` | `NEW_CARRIER_AC_TYP` | |
| 26 | `MIDNIGHT_QTY` | `NEW_MIDNIGHT_QTY_SMALLINT` | `_SMALLINT` suffix → SEM-06 |
| 27 | `BUFFER_DUR` | `NEW_BUFFER_DUR_SMALLINT` | `_SMALLINT` suffix → SEM-06 |
| 28 | `STD_WORKING_DUR` | `NEW_STD_WORKING_DUR_SMALLINT` | `_SMALLINT` suffix → SEM-06 |
| 29 | `TOW_TIME_DUR` | `NEW_TOW_TIME_DUR_SMALLINT` | `_SMALLINT` suffix → SEM-06 |
| 30 | `FIXED_LINK_RSN_TXT` | `NEW_FIXED_LINK_RSN_TXT` | |
| 31 | `LINK_EFFECTIVE_DT` | `NEW_LINK_EFFECTIVE_DT` | |
| 32 | `LINK_EXPIRY_DT` | `NEW_LINK_EXPIRY_DT` | |
| 33 | `CURRENT_REC_IND` | `NEW_CURRENT_REC_IND` | |

---

## 2. Syntax errors / residual-Teradata constructs (SFX-* / FNX-* / DTX-*)

| Line | Construct | Rule | Why invalid on Snowflake | Classification |
|---|---|---|---|---|
| — | (none) | — | — | — |

**No residual-Teradata constructs found.** The script contains no
`ZEROIFNULL`/`NULLIFZERO` (FNX-01/02), no `CONTAINS`/`OVERLAPS` (SFX-01/02),
no `SEL` (SFX-04), no `SET`/`MULTISET` (SFX-05), no `PRIMARY INDEX`
(SFX-06), no `COLLECT STATS` (SFX-07), no BTEQ directives (SFX-08), no
`LOCKING` (SFX-09), no `(+)` outer joins (SFX-10), no `MINUS` (SFX-14),
no `TOP` (SFX-13), no `FORMAT` cast (SFX-15/FNX-08), no `BYTEINT`/`CHARACTER
SET`/`PERIOD`/`CLOB` types (DTX-*). The statement is parse-clean Snowflake SQL.

---

## 3. Defects (DEF-*)

| Line | Defect | Rule | Classification |
|---|---|---|---|
| — | (none) | — | — |

**No defects found.** Parentheses are balanced (DEF-03), no duplicate columns
on either side (DEF-01), INSERT/SELECT counts match (DEF-05), no malformed
function calls (DEF-04), no broken keywords (DEF-02). The `NOT EXISTS`
subquery's 33-predicate conjunction is well-formed.

---

## 4. Semantic risks (SEM-*)

These parse and run on Snowflake but may change results versus the (absent)
Teradata ground truth. Each is flagged `TODO(SME)` because no DDL and no
Teradata original were supplied.

| # | Line(s) | Risk | Rule | Present? | Classification | Detail |
|---|---|---|---|---|---|---|
| SEM-03 | 71–103 (NOT EXISTS predicates) | `CHAR(n)` padding & comparison | SEM-03 | **Likely** | `SME` | The `NOT EXISTS` anti-join compares all 33 columns between `BASE.FLT_FOLDER_LINKS` (T) and `STAGING.ExpFinalyseInserts` (S). Several keys are plausibly `CHAR(n)` (`*_CD`, `*_TYP`, `*_TXT`, `*_IND`, `*_SFX_CD`). Teradata blank-pads `CHAR(n)` and ignores trailing spaces in `=`; Snowflake does **not** pad, so padding differences silently change which rows the anti-join suppresses — inserting duplicates or suppressing valid rows. Without DDL for both tables this cannot be confirmed. **SME question:** Are any of the 33 comparison keys `CHAR(n)` (vs `VARCHAR`)? If so, wrap each `CHAR(n)` predicate in `RTRIM(...)` on both sides. |
| SEM-06 | 4–8, 15, 17–19, 26–29 (SELECT aliases) + 71–103 (predicates) | Implicit cast / type mismatch in comparison | SEM-06 / DTX-10 | **Likely** | `SME` | The `_SMALLINT`/`_DATE` suffix convention on SELECT aliases signals pre-cast staging values (`NEW_IN_FLT_NO_SMALLINT`, `NEW_IN_DEP_FLTDT_DATE`, `NEW_IN_ARR_FLTTM_DATE`, `NEW_MIDNIGHT_QTY_SMALLINT`, …). The `NOT EXISTS` predicates then compare these against `BASE.FLT_FOLDER_LINKS` columns of unknown type. A type mismatch (e.g. `DATE` vs `TIMESTAMP`, `VARCHAR` vs `NUMBER`, `TIME` vs `TIMESTAMP`) could silently change which rows the anti-join suppresses. Note positions 8 and 18 map a `_DATE`-suffixed alias onto a `_TM` target (`IN_ARR_FLTTM`/`OUT_DEP_FLTTM`) — a possible type-grain mismatch. The suffix describes the staging cast, **not** the target column. **SME question:** Confirm DDL types for both `BASE.FLT_FOLDER_LINKS` and `STAGING.ExpFinalyseInserts` for every `_SMALLINT`/`_DATE`-suffixed column, and confirm the `_TM` targets accept the `_DATE`-cast value. |
| SEM-05 | whole statement | SET-table dedup | SEM-05 | **Not triggered** | n/a | This is a **single** `INSERT` into `BASE.FLT_FOLDER_LINKS` — not multiple INSERTs into one target, nor a `UNION`/`UNION ALL` whose branches all write to one target. Per SEM-05, the SET-table signal does not fire from a single INSERT. The `NOT EXISTS` is an explicit anti-join dedup pattern in the SQL itself, not an implicit SET-table dedup. No `CREATE TABLE` DDL for the target is supplied, but SEM-05 does not require an SME question here because the dedup is explicit, not assumed. (If the target were a Teradata SET table, this `NOT EXISTS` would be redundant but not harmful.) |
| SEM-04 | — | Timestamp / timezone | SEM-04 | **Not present** | n/a | No `TIMESTAMP`/`TIMESTAMP_TZ`/`CURRENT_TIMESTAMP`/`TO_TIMESTAMP_*` constructs in the statement. The `_DATE`/`_TM` columns are date/time, not timestamp-with-TZ, so no TZ drift applies unless DDL reveals otherwise (folded into SEM-06). |
| SEM-01 | — | Integer division | SEM-01 | **Not present** | n/a | No `/` division in the statement. |
| SEM-02 | — | `QUALIFY` / dedup ordering | SEM-02 | **Not present** | n/a | No `QUALIFY` or `ROW_NUMBER` in the statement. |
| SEM-07 | — | `NULL` ordering | SEM-07 | **Not present** | n/a | No `ORDER BY` feeding `QUALIFY`/`TOP`. |
| SEM-08 | — | Empty string vs NULL | SEM-08 | **Not present** | n/a | No `NULLIF(x,'')` or empty-string handling. |
| SEM-09 | — | Aggregate of empty set | SEM-09 | **Not present** | n/a | No aggregates. |
| SEM-10 | — | Lookup join direction | SEM-10 | **Not present** | n/a | No lookup/exchange-rate join; the only join is the `NOT EXISTS` anti-join against the same target table. |

### Open SME questions

1. **(SEM-03)** Are any of the 33 `NOT EXISTS` comparison keys declared
   `CHAR(n)` in `BASE.FLT_FOLDER_LINKS` or `STAGING.ExpFinalyseInserts`? If
   yes, which ones, and should each `CHAR(n)` predicate be wrapped in
   `RTRIM(...)` on both sides to preserve Teradata blank-padding semantics?
2. **(SEM-06)** Confirm the DDL types for both tables for every
   `_SMALLINT`- and `_DATE`-suffixed SELECT alias, and confirm the `_TM`
   target columns (positions 8 `IN_ARR_FLTTM`, 18 `OUT_DEP_FLTTM`) accept the
   `_DATE`-cast staging value without a type-grain mismatch.

---

## 5. Classification summary

| Classification | Count | Items |
|---|---|---|
| `AUTO` | 0 | — |
| `FIX` | 0 | — |
| `SME` | 2 | SEM-03 (CHAR padding in 33-key anti-join), SEM-06 (`_SMALLINT`/`_DATE` suffix type compatibility + `_TM` grain) |
| `KEEP` | 0 | (SNZ inventory empty) |

**This is a semantic-only unit.** The statement is parse-clean Snowflake SQL
with no mechanical (SFX/FNX/DTX/DEF) fixes required. The only findings are two
SME-classified semantic risks that require DDL for both tables to resolve. A
control PASS of the buggy input on the mechanical validator is therefore
**expected** and is not a re-fix trigger — the decisive evidence is the SEM-*
inventory and manual spot-check, not the control's mechanical result (per the
standing lesson: *"A parse PASS is not correctness."*).

---

## 6. Table dependency inventory

| Role | Table | Schema | Notes |
|---|---|---|---|
| Target (INSERT) | `FLT_FOLDER_LINKS` | `BASE` | 33-column target. No DDL supplied → SET/MULTISET unknown (not needed: single INSERT, explicit `NOT EXISTS` dedup). |
| Source (SELECT) | `ExpFinalyseInserts` | `STAGING` | 33 `NEW_*` projection columns; supplies the candidate rows. |
| Anti-join probe (NOT EXISTS) | `FLT_FOLDER_LINKS` | `BASE` | Same as target; probed on all 33 columns to suppress already-present rows. |

**Verdict:** One target (`BASE.FLT_FOLDER_LINKS`), one source
(`STAGING.ExpFinalyseInserts`). The target is also self-probed in the `NOT
EXISTS` anti-join. No other dependencies. The script is self-contained and
parse-clean; the only open items are the two SEM-03/SEM-06 SME questions that
require DDL for both tables.