# Stage 1 — Analysis: `S_vwxxx_MloadLinksInserts.snowsql`

**Input:** `00_input/S_vwxxx_MloadLinksInserts.snowsql` (109 lines, `.snowsql`)
**Teradata ground truth:** none supplied (`00_input/S_vwxxx_MloadLinksInserts.teradata.sql` does not exist).
**Archive step:** `python3 05_report/archive_outputs.py S_vwxxx_MloadLinksInserts` — no prior outputs existed for this unit, so archiving is a no-op.

---

## 1. Column-count check

Single `INSERT … SELECT` statement. Counts below are after removing any
duplicates (there are none on either side).

| Side | Count | Duplicates | Net |
|---|---|---|---|
| INSERT target columns (lines 2–34) | 33 | 0 | 33 |
| SELECT expressions (lines 37–69) | 33 | 0 | 33 |

**Verdict: 33 = 33 — PASS.** No DEF-05 (count mismatch), no DEF-01 (duplicate
columns). Positional alignment is 1:1; each INSERT column maps to the
corresponding `NEW_*` SELECT expression by ordinal.

| # | INSERT column (line) | SELECT expression (line) | Aligned? |
|---|---|---|---|
| 1 | `LINK_STATION_CD` (2) | `NEW_LINK_STATION_CD` (37) | ✓ |
| 2 | `IN_ORIGN_STATION_CD` (3) | `NEW_IN_ORIGN_STATION_CD` (38) | ✓ |
| 3 | `IN_ALN_CD` (4) | `NEW_IN_ALN_CD` (39) | ✓ |
| 4 | `IN_FLT_NO` (5) | `NEW_IN_FLT_NO_SMALLINT` (40) | ✓ |
| 5 | `IN_FLT_SFX_CD` (6) | `NEW_IN_FLT_SFX_CD` (41) | ✓ |
| 6 | `IN_DEP_FLTDT` (7) | `NEW_IN_DEP_FLTDT_DATE` (42) | ✓ |
| 7 | `IN_ARR_FLTDT` (8) | `NEW_IN_ARR_FLTDT_DATE` (43) | ✓ |
| 8 | `IN_ARR_FLTTM` (9) | `NEW_IN_ARR_FLTTM_DATE` (44) | ✓ |
| 9 | `IN_PAX_TML_CD` (10) | `NEW_IN_PAX_TML_CD` (45) | ✓ |
| 10 | `IN_GROUND_ACY_CD` (11) | `NEW_IN_GROUND_ACY_CD` (46) | ✓ |
| 11 | `IN_SERVICE_TYP` (12) | `NEW_IN_SERVICE_TYP` (47) | ✓ |
| 12 | `IN_FLT_LEG_SEQ_NO` (13) | `NEW_IN_FLT_LEG_SEQ_NO` (48) | ✓ |
| 13 | `OUT_DESTATION_STATION_CD` (14) | `NEW_OUT_DESTATION_STATION_CD` (49) | ✓ |
| 14 | `OUT_ALN_CD` (15) | `NEW_OUT_ALN_CD` (50) | ✓ |
| 15 | `OUT_FLT_NO` (16) | `NEW_OUT_FLT_NO_SMALLINT` (51) | ✓ |
| 16 | `OUT_FLT_SFX_CD` (17) | `NEW_OUT_FLT_SFX_CD` (52) | ✓ |
| 17 | `OUT_DEP_FLTDT` (18) | `NEW_OUT_DEP_FLTDT_DATE` (53) | ✓ |
| 18 | `OUT_DEP_FLTTM` (19) | `NEW_OUT_DEP_FLTTM_DATE` (54) | ✓ |
| 19 | `OUT_ARR_FLTDT` (20) | `NEW_OUT_ARR_FLTDT_DATE` (55) | ✓ |
| 20 | `OUT_PAX_TML_CD` (21) | `NEW_OUT_PAX_TML_CD` (56) | ✓ |
| 21 | `OUT_GROUND_ACY_CD` (22) | `NEW_OUT_GROUND_ACY_CD` (57) | ✓ |
| 22 | `OUT_SERVICE_TYP` (23) | `NEW_OUT_SERVICE_TYP` (58) | ✓ |
| 23 | `OUT_FLT_LEG_SEQ_NO` (24) | `NEW_OUT_FLT_LEG_SEQ_NO` (59) | ✓ |
| 24 | `AIRCRAFT_OWNER_CD` (25) | `NEW_AIRCRAFT_OWNER_CD` (60) | ✓ |
| 25 | `CARRIER_AC_TYP` (26) | `NEW_CARRIER_AC_TYP` (61) | ✓ |
| 26 | `MIDNIGHT_QTY` (27) | `NEW_MIDNIGHT_QTY_SMALLINT` (62) | ✓ |
| 27 | `BUFFER_DUR` (28) | `NEW_BUFFER_DUR_SMALLINT` (63) | ✓ |
| 28 | `STD_WORKING_DUR` (29) | `NEW_STD_WORKING_DUR_SMALLINT` (64) | ✓ |
| 29 | `TOW_TIME_DUR` (30) | `NEW_TOW_TIME_DUR_SMALLINT` (65) | ✓ |
| 30 | `FIXED_LINK_RSN_TXT` (31) | `NEW_FIXED_LINK_RSN_TXT` (66) | ✓ |
| 31 | `LINK_EFFECTIVE_DT` (32) | `NEW_LINK_EFFECTIVE_DT` (67) | ✓ |
| 32 | `LINK_EXPIRY_DT` (33) | `NEW_LINK_EXPIRY_DT` (68) | ✓ |
| 33 | `CURRENT_REC_IND` (34) | `NEW_CURRENT_REC_IND` (69) | ✓ |

---

## 2. Syntax errors / residual-Teradata constructs

**None found.** The file was scanned for every construct in
`02_rules/01_syntax_fixes.md` (SFX-*) and `02_rules/03_function_fixes.md`
(FNX-*):

| Construct checked | Present? |
|---|---|
| `CONTAINS` / `OVERLAPS` (SFX-01/02) | No |
| `SEL` (SFX-04) | No |
| `SET` / `MULTISET` (SFX-05) | No |
| `PRIMARY INDEX` (SFX-06) | No |
| `COLLECT STATS` (SFX-07) | No |
| BTEQ directives (SFX-08) | No |
| `LOCKING ROW` (SFX-09) | No |
| `(+)` outer joins (SFX-10) | No |
| Unbalanced parens (SFX-11) | No |
| Trailing/missing commas (SFX-12) | No |
| `TOP n` (SFX-13) | No |
| `MINUS` (SFX-14) | No |
| `CAST(... FORMAT ...)` (SFX-15) | No |
| `ZEROIFNULL` / `NULLIFZERO` (FNX-01/02) | No |
| `INDEX` / `OREPLACE` / `OTRANSLATE` / `STRTOK` (FNX-04–07) | No |
| `**` / `MOD` / `LIKE ANY` / `HASHROW` (FNX-09–12) | No |
| `TITLE` / `FORMAT` phrases (FNX-13) | No |
| `SUBSTRING(s FROM ...)` (FNX-15) | No |

The statement is valid Snowflake SQL: a single `INSERT … SELECT` with a
`NOT EXISTS` anti-join subquery. No DTX-* type pitfalls appear in DDL (there is
no DDL — this is an INSERT-only script).

---

## 3. Defects (DEF-*)

**None found.**

| Defect class | Present? | Notes |
|---|---|---|
| DEF-01 duplicate column in INSERT list | No | All 33 target columns are distinct. |
| DEF-02 missing whitespace / typo keyword | No | All keywords well-formed. |
| DEF-03 unbalanced parentheses | No | The `NOT EXISTS ( SELECT 1 FROM … WHERE … )` block opens at line 73 and closes at line 109; the outer statement closes with `);` at line 109. Balanced. |
| DEF-04 malformed function call | No | No function calls present. |
| DEF-05 INSERT count ≠ SELECT count | No | 33 = 33 (see §1). |
| DEF-06 alias ≠ target name | No (cosmetic) | Aliases follow a consistent `NEW_*` naming convention; they are positional and do not need to match target names. Not a defect. |
| DEF-07 wrong column referenced | No | Without a Teradata original, no copy-paste column swap can be disproven; the `T.<col> = S.NEW_<col>` pattern is internally consistent across all 33 predicates. |

---

## 4. Semantic risks (SEM-*)

No Teradata ground truth was supplied, so every semantic inference is flagged
`TODO(SME)`. The statement parses cleanly; the risks below are about whether
results match the original intent.

| ID | Risk | Present? | Lines | Detail | Class |
|---|---|---|---|---|---|
| SEM-01 | Integer division | No | — | No division operators in the statement. | — |
| SEM-02 | `QUALIFY` / dedup ordering | No | — | No `QUALIFY` or `ROW_NUMBER` present. | — |
| SEM-03 | `CHAR(n)` padding & comparison | **Possible** | 76–108 | The `NOT EXISTS` anti-join compares 33 column pairs between `BASE.FLT_FOLDER_LINKS T` and `STAGING.ExpFinalyseInserts S`. Several columns are plausibly `CHAR(n)` by naming convention (`*_CD`, `*_TYP`, `*_TXT`, `*_IND`). Teradata blank-pads `CHAR(n)` and ignores trailing spaces in `=`; Snowflake does **not** pad, so `'A' <> 'A '` on Snowflake. If any join key is `CHAR(n)` and the staging values carry different trailing-space padding than the base values, the anti-join will behave differently (rows that should be suppressed as duplicates may be inserted, or vice-versa). **No DDL is supplied**, so the types cannot be confirmed. | **SME** |
| SEM-04 | Timestamp / timezone | No | — | The `*_DATE`-suffixed aliases suggest `DATE` types (no time component), not `TIMESTAMP`. No `TIMESTAMP_TZ`/`LTZ` constructs. Low risk; not flagged. | — |
| SEM-05 | SET-table dedup | **Not triggered** | — | This file contains a **single** `INSERT` into `BASE.FLT_FOLDER_LINKS`. There is no `UNION`/`UNION ALL` and no second `INSERT` into the same target *within this file*. (A companion file `S_vwxxx_MloadLinksUpdates.snowsql` exists, but SET vs MULTISET is a property of the target's `CREATE TABLE` DDL, which is not supplied. Cross-file SET behaviour cannot be inferred from one INSERT-only script.) No SME question raised for this file alone. | — |
| SEM-06 | Implicit cast / NULL in comparison | **Possible** | 79, 90, 101–104 | The SELECT aliases carry `_SMALLINT` (e.g. `NEW_IN_FLT_NO_SMALLINT`, `NEW_OUT_FLT_NO_SMALLINT`, `NEW_MIDNIGHT_QTY_SMALLINT`, `NEW_BUFFER_DUR_SMALLINT`, `NEW_STD_WORKING_DUR_SMALLINT`, `NEW_TOW_TIME_DUR_SMALLINT`) and `_DATE` suffixes (e.g. `NEW_IN_DEP_FLTDT_DATE`), suggesting the converter already cast these staging columns. The `NOT EXISTS` predicates then compare them against `BASE.FLT_FOLDER_LINKS` columns whose types are unknown (no DDL supplied). If the base columns are a different numeric scale or a different date representation, Snowflake's implicit cast may silently coerce — usually safe for numeric↔numeric, but a `DATE` vs `TIMESTAMP` or `VARCHAR` vs `NUMBER` mismatch could change which rows the anti-join suppresses. **No DDL supplied** to confirm. | **SME** |
| SEM-07 | `NULL` ordering | No | — | No `ORDER BY` / `QUALIFY` present. | — |
| SEM-08 | Empty string vs NULL | No | — | No `NULLIF(x,'')` or empty-string comparisons. | — |
| SEM-09 | Aggregate of empty set | No | — | No aggregates. | — |
| SEM-10 | Join-key grain / direction | No | 76–108 | The anti-join keys follow a uniform `T.<base_col> = S.NEW_<base_col>` pattern for all 33 columns — the same 33 columns as the INSERT list. No alias-name mismatch that would hide a grain swap. Internally consistent. | — |

### Open SME questions

1. **SEM-03 (CHAR padding):** Are any of the 33 anti-join key columns in
   `BASE.FLT_FOLDER_LINKS` declared `CHAR(n)` (e.g. `LINK_STATION_CD`,
   `IN_ALN_CD`, `IN_SERVICE_TYP`, `FIXED_LINK_RSN_TXT`, `CURRENT_REC_IND`)?
   If so, do the corresponding `STAGING.ExpFinalyseInserts` values carry the
   same trailing-space padding? If padding differs, the `NOT EXISTS` anti-join
   will not suppress the same rows Teradata would have, and `RTRIM`/`TRIM`
   wrappers are needed on both sides of each `CHAR(n)` predicate.
2. **SEM-06 (implicit cast):** What are the declared types of
   `IN_FLT_NO`, `OUT_FLT_NO`, `MIDNIGHT_QTY`, `BUFFER_DUR`, `STD_WORKING_DUR`,
   `TOW_TIME_DUR` in `BASE.FLT_FOLDER_LINKS`, and do they match the
   `_SMALLINT`-cast staging values? What are the types of the `*_FLTDT` /
   `*_FLTTM` columns vs the `_DATE`-suffixed staging values? Confirm that the
   implicit casts Snowflake applies in the `NOT EXISTS` predicates produce
   the same row-suppression behaviour as the Teradata original.

---

## 5. SnowSQL client layer (SNZ-*)

The input has the `.snowsql` extension, so the SNZ inventory is required. The
file was scanned for every construct in `02_rules/07_snowsql_client.md`:

| ID | Construct | Count | Lines | Class |
|---|---|---|---|---|
| SNZ-01 | `<% ctx.env.X %>` template tags | 0 | — | — |
| SNZ-02 | `PUT` commands | 0 | — | — |
| SNZ-03 | `GET` commands | 0 | — | — |
| SNZ-04 | Stage DML (`COPY INTO @stage`, `REMOVE`, `LIST`) | 0 | — | — |

**The SNZ inventory is empty.** Despite the `.snowsql` extension, this file
contains only plain Snowflake DML — no template placeholders, no `PUT`/`GET`,
no stage commands. Nothing to preserve-as-is; nothing to mask for validation.
The `.snowsql` extension is retained but has no client-layer content.

---

## 6. Finding classification summary

| # | Finding | Rule | Lines | Class | Action |
|---|---|---|---|---|---|
| 1 | Column count 33 = 33, no duplicates | DEF-05/DEF-01 | 2–69 | — | PASS (no action) |
| 2 | No residual Teradata / syntax errors | SFX-*/FNX-*/DTX-* | — | — | PASS (no action) |
| 3 | No defects | DEF-* | — | — | PASS (no action) |
| 4 | Possible `CHAR(n)` padding drift in 33-key anti-join | SEM-03 | 76–108 | **SME** | Flag `TODO(SME)`; confirm column types via DDL; wrap `CHAR(n)` predicates in `RTRIM` if confirmed. |
| 5 | Possible implicit-cast drift on `_SMALLINT`/`_DATE`-suffixed staging values vs unknown base types | SEM-06 | 79, 90, 101–104 | **SME** | Flag `TODO(SME)`; confirm base column types; make casts explicit if types differ. |
| 6 | Empty SNZ inventory (`.snowsql` with no client-layer constructs) | SNZ-* | — | — | No action (nothing to preserve). |

**Counts:** 0 AUTO · 0 FIX · 2 SME · 0 KEEP (SNZ inventory empty).

---

## 7. Table dependency inventory

| Role | Table / view | Schema | Lines | Notes |
|---|---|---|---|---|
| Source (SELECT) | `ExpFinalyseInserts` | `STAGING` | 70 | Read once; alias `S`. Supplies all 33 `NEW_*` columns. |
| Target (INSERT) | `FLT_FOLDER_LINKS` | `BASE` | 1 | Written to via `INSERT INTO`. |
| Anti-join reference | `FLT_FOLDER_LINKS` | `BASE` | 75 | Read inside `NOT EXISTS` subquery; alias `T`. Same table as the INSERT target — the anti-join suppresses rows already present in the target. |

**Dependency order:** `STAGING.ExpFinalyseInserts` must be populated before this
statement runs. `BASE.FLT_FOLDER_LINKS` is both the target and the anti-join
reference (read-then-write within one statement).

---

## 8. Verdict

**Mechanically clean, semantically gated.** The file is a well-formed
single-`INSERT … SELECT … NOT EXISTS` anti-join with 33 = 33 columns, no
residual Teradata, no defects, and an empty SnowSQL client layer — zero
mechanical fixes (SFX/FNX/DTX/DEF/SNZ) are needed. Two SME-classified semantic
risks remain open: SEM-03 (possible `CHAR(n)` padding drift across the 33-key
anti-join) and SEM-06 (possible implicit-cast drift on `_SMALLINT`/`_DATE`
staging values vs unknown base column types). Both require target/source DDL
confirmation before any SQL change is safe; neither can be resolved from the
SQL alone.