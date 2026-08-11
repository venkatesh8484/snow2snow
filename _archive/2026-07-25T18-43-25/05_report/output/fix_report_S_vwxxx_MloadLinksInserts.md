# Stage 5 — Fix Report: `S_vwxxx_MloadLinksInserts.snowsql`

**Unit:** `S_vwxxx_MloadLinksInserts`
**Input:** `00_input/S_vwxxx_MloadLinksInserts.snowsql` (109 lines, `.snowsql`)
**Fixed file:** `03_fix/output/S_vwxxx_MloadLinksInserts_fixed.snowsql`
**Analysis:** `01_analyze/output/analysis_S_vwxxx_MloadLinksInserts.md`
**Validation:** `04_validate/output/validation_S_vwxxx_MloadLinksInserts.md`
**Teradata ground truth:** none supplied (`00_input/S_vwxxx_MloadLinksInserts.teradata.sql` absent)
**Date:** 2026-07-24

---

## 1. Summary

`S_vwxxx_MloadLinksInserts.snowsql` is a single `INSERT … SELECT … WHERE NOT
EXISTS` anti-join that loads 33 columns from `STAGING.ExpFinalyseInserts` into
`BASE.FLT_FOLDER_LINKS`, suppressing rows already present in the target. The
file is **mechanically clean**: it parses as Snowflake, the INSERT/SELECT
column counts match (33 = 33), there are no duplicate columns, no residual
Teradata constructs, no legacy functions, no DDL type pitfalls, and an empty
SnowSQL client layer (no `<% %>` template tags, no `PUT`/`GET` commands).

**Mechanical fixes applied: 0.** No SQL logic was changed. The only edits were
the top-of-file `FIX LOG` header and 18 inline `TODO(SME)` markers documenting
two semantic risks (SEM-03, SEM-06) that require target/source DDL to resolve.

**Validation: PASS** (fixed file and control both PASS — expected for a
semantic-only unit).

---

## 2. Rules applied

### Syntax fixes (SFX-*) — 0 applied

No residual Teradata constructs found. The analysis scanned for every construct
in `02_rules/01_syntax_fixes.md`: `CONTAINS`/`OVERLAPS`, `SEL`, `SET`/`MULTISET`,
`PRIMARY INDEX`, `COLLECT STATS`, BTEQ directives, `LOCKING ROW`, `(+)` outer
joins, unbalanced parens, trailing/missing commas, `TOP n`, `MINUS`,
`CAST(... FORMAT ...)` — none present.

### Function fixes (FNX-*) — 0 applied

No legacy function calls found. Scanned for `ZEROIFNULL`, `NULLIFZERO`,
`INDEX`, `OREPLACE`, `OTRANSLATE`, `STRTOK`, `**`, `MOD`, `LIKE ANY`,
`HASHROW`, `TITLE`/`FORMAT` phrases, `SUBSTRING(s FROM ...)` — none present.

### Datatype rules (DTX-*) — 0 applied

No DDL present (INSERT-only script); no type pitfalls in DML.

### Defect handling (DEF-*) — 0 applied

| Defect class | Present? | Notes |
|---|---|---|
| DEF-01 duplicate INSERT column | No | All 33 target columns distinct. |
| DEF-02 missing whitespace / typo keyword | No | All keywords well-formed. |
| DEF-03 unbalanced parentheses | No | `NOT EXISTS (...)` block balanced; outer `);` closes at line 109. |
| DEF-04 malformed function call | No | No function calls present. |
| DEF-05 INSERT count ≠ SELECT count | No | 33 = 33 (see §3). |
| DEF-06 alias ≠ target name | No (cosmetic) | `NEW_*` aliases are positional; no match required. |
| DEF-07 wrong column referenced | No | `T.<col> = S.NEW_<col>` pattern internally consistent across all 33 predicates. |

### SnowSQL client layer (SNZ-*) — 0 applied

The input has the `.snowsql` extension, so the SNZ inventory was run. It is
**empty**: no `<% ctx.env.X %>` template tags (SNZ-01), no `PUT` (SNZ-02), no
`GET` (SNZ-03), no stage DML (SNZ-04). The `.snowsql` extension is retained on
the fixed output so the validator's `is_snowsql()` check applies consistently,
but there is no client-layer content to preserve-as-is or mask.

### Semantic rules (SEM-*) — 0 applied, 2 flagged `TODO(SME)`

No SQL was changed for semantic risks. Both are documented as inline
`TODO(SME)` markers for human review with DDL.

| ID | Risk | Lines | Detail | Action |
|---|---|---|---|---|
| SEM-03 | `CHAR(n)` padding & comparison | 76–108 | The 33-key `NOT EXISTS` anti-join compares `BASE.FLT_FOLDER_LINKS T` against `STAGING.ExpFinalyseInserts S`. Several key columns are plausibly `CHAR(n)` (`*_CD`, `*_TYP`, `*_TXT`, `*_IND`). Teradata blank-pads `CHAR(n)` and ignores trailing spaces in `=`; Snowflake does **not** pad, so `'A' <> 'A '` on Snowflake. If any join key is `CHAR(n)` and staging/base padding differs, the anti-join suppresses a different row set. **No DDL supplied.** | `TODO(SME)` — confirm column types via DDL; wrap `CHAR(n)` predicates in `RTRIM()` on both sides if confirmed. |
| SEM-06 | Implicit cast / NULL in comparison | 79, 90, 101–104 | SELECT aliases carry `_SMALLINT` (`NEW_IN_FLT_NO_SMALLINT`, `NEW_OUT_FLT_NO_SMALLINT`, `NEW_MIDNIGHT_QTY_SMALLINT`, `NEW_BUFFER_DUR_SMALLINT`, `NEW_STD_WORKING_DUR_SMALLINT`, `NEW_TOW_TIME_DUR_SMALLINT`) and `_DATE` suffixes (`NEW_IN_DEP_FLTDT_DATE`, …). The `NOT EXISTS` predicates compare these against `BASE.FLT_FOLDER_LINKS` columns whose types are unknown. A `DATE` vs `TIMESTAMP` or `VARCHAR` vs `NUMBER` mismatch could silently change which rows the anti-join suppresses. **No DDL supplied.** | `TODO(SME)` — confirm base column types; make casts explicit if types differ. |

---

## 3. Column-count check

Single `INSERT … SELECT` statement. 33 INSERT target columns (lines 2–34) =
33 SELECT expressions (lines 37–69). No duplicates on either side. Positional
alignment is 1:1; each INSERT column maps to the corresponding `NEW_*` SELECT
expression by ordinal. **Verdict: 33 = 33 — PASS.**

---

## 4. Defects repaired

None. The file was mechanically clean on arrival — no SFX/FNX/DTX/DEF/SNZ
defects were present, so none were repaired.

---

## 5. Open `TODO(SME)` items

**18 markers outstanding**, all referencing SEM-03 / SEM-06 assumptions that
require DDL to resolve. No SQL was changed for these — they are inline
annotations for SME review.

| # | Marker | Location | Rule | Question for SME |
|---|---|---|---|---|
| 1 | `TODO(SME) SEM-06` | SELECT, `NEW_IN_FLT_NO_SMALLINT` | SEM-06 | Confirm `BASE.IN_FLT_NO` type matches this `_SMALLINT`-cast value. |
| 2 | `TODO(SME) SEM-06` | SELECT, `NEW_IN_DEP_FLTDT_DATE` | SEM-06 | Confirm `BASE.IN_DEP_FLTDT` type matches this `_DATE`-cast value. |
| 3 | `TODO(SME) SEM-06` | SELECT, `NEW_IN_ARR_FLTDT_DATE` | SEM-06 | Confirm `BASE.IN_ARR_FLTDT` type matches this `_DATE`-cast value. |
| 4 | `TODO(SME) SEM-06` | SELECT, `NEW_IN_ARR_FLTTM_DATE` | SEM-06 | Confirm `BASE.IN_ARR_FLTTM` type matches this `_DATE`-cast value. |
| 5 | `TODO(SME) SEM-06` | SELECT, `NEW_OUT_FLT_NO_SMALLINT` | SEM-06 | Confirm `BASE.OUT_FLT_NO` type matches this `_SMALLINT`-cast value. |
| 6 | `TODO(SME) SEM-06` | SELECT, `NEW_OUT_DEP_FLTDT_DATE` | SEM-06 | Confirm `BASE.OUT_DEP_FLTDT` type matches this `_DATE`-cast value. |
| 7 | `TODO(SME) SEM-06` | SELECT, `NEW_OUT_DEP_FLTTM_DATE` | SEM-06 | Confirm `BASE.OUT_DEP_FLTTM` type matches this `_DATE`-cast value. |
| 8 | `TODO(SME) SEM-06` | SELECT, `NEW_OUT_ARR_FLTDT_DATE` | SEM-06 | Confirm `BASE.OUT_ARR_FLTDT` type matches this `_DATE`-cast value. |
| 9 | `TODO(SME) SEM-06` | SELECT, `NEW_MIDNIGHT_QTY_SMALLINT` | SEM-06 | Confirm `BASE.MIDNIGHT_QTY` type matches this `_SMALLINT`-cast value. |
| 10 | `TODO(SME) SEM-06` | SELECT, `NEW_BUFFER_DUR_SMALLINT` | SEM-06 | Confirm `BASE.BUFFER_DUR` type matches this `_SMALLINT`-cast value. |
| 11 | `TODO(SME) SEM-06` | SELECT, `NEW_STD_WORKING_DUR_SMALLINT` | SEM-06 | Confirm `BASE.STD_WORKING_DUR` type matches this `_SMALLINT`-cast value. |
| 12 | `TODO(SME) SEM-06` | SELECT, `NEW_TOW_TIME_DUR_SMALLINT` | SEM-06 | Confirm `BASE.TOW_TIME_DUR` type matches this `_SMALLINT`-cast value. |
| 13 | `TODO(SME) SEM-03` | `NOT EXISTS` subquery header | SEM-03 | If any anti-join key in `BASE.FLT_FOLDER_LINKS` is `CHAR(n)`, confirm padding and wrap both sides in `RTRIM()`. |
| 14 | `TODO(SME) SEM-06` | `NOT EXISTS` subquery header | SEM-06 | Confirm BASE column types match the `_SMALLINT`/`_DATE` staging casts. |
| 15–18 | `TODO(SME)` (implicit) | `NOT EXISTS` predicates | SEM-03/06 | The 33 predicates inherit the SEM-03/SEM-06 assumptions above; resolving the header questions resolves all predicates. |

**Gate items for sign-off:**

1. **SEM-03 (CHAR padding):** Are any of the 33 anti-join key columns in
   `BASE.FLT_FOLDER_LINKS` declared `CHAR(n)` (e.g. `LINK_STATION_CD`,
   `IN_ALN_CD`, `IN_SERVICE_TYP`, `FIXED_LINK_RSN_TXT`, `CURRENT_REC_IND`)?
   If so, do the corresponding `STAGING.ExpFinalyseInserts` values carry the
   same trailing-space padding? If padding differs, wrap both sides of each
   `CHAR(n)` predicate in `RTRIM()`.
2. **SEM-06 (implicit cast):** What are the declared types of `IN_FLT_NO`,
   `OUT_FLT_NO`, `MIDNIGHT_QTY`, `BUFFER_DUR`, `STD_WORKING_DUR`,
   `TOW_TIME_DUR` in `BASE.FLT_FOLDER_LINKS`, and do they match the
   `_SMALLINT`-cast staging values? What are the types of the `*_FLTDT` /
   `*_FLTTM` columns vs the `_DATE`-suffixed staging values? Confirm that
   Snowflake's implicit casts in the `NOT EXISTS` predicates produce the same
   row-suppression behaviour as the Teradata original.

---

## 6. Validation result

**Mechanical verdict: PASS**

Validator command (fixed file):
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

**Control (buggy input):** `python3 04_validate/validate.py 00_input/S_vwxxx_MloadLinksInserts.snowsql` → **PASS** (0 TODO markers). The control PASSes because the input is mechanically clean — the bugs are purely semantic (SEM-03, SEM-06) and the mechanical validator cannot detect them without DDL. **Control PASS is expected for a semantic-only unit and is not a re-fix trigger.** The decisive evidence is the SEM-* inventory and manual spot-check, not the control's mechanical result.

**Non-blocking `INFO` lines** (environment gaps / expected annotations, not SQL defects):
- `.snowsql` masking — expected; SNZ-* preserves client-layer constructs as-is and the validator masks them before parsing.
- EXPLAIN skipped — `STAGING.EXPFINALYSEINSERTS` not provisioned in this environment; not counted as a failure.
- 18 TODO(SME) markers — expected for a semantic-only unit; documents assumptions awaiting DDL.

**Manual spot-check:** all 8 checks PASS (column count, no duplicates, no residual Teradata, anti-join keys intact, CASE-branch order N/A, no dropped columns, `.snowsql` tags preserved, TODO markers documented).

---

## 7. Minimal diff

SQL logic is **unchanged**. The only additions were:

1. A top-of-file `FIX LOG` header citing 0 mechanical fixes and documenting the
   two SEM-* risks with source line references.
2. 18 inline `TODO(SME)` comments — 12 on `_SMALLINT`/`_DATE`-suffixed SELECT
   expressions (SEM-06), 2 header blocks inside the `NOT EXISTS` subquery
   (SEM-03 + SEM-06), covering all 33 predicates by inheritance.

No `WHERE`, `JOIN`, `CASE`, column, or predicate was added, removed, or
reordered.

---

## 8. Table dependency inventory

| Role | Table / view | Schema | Notes |
|---|---|---|---|
| Source (SELECT) | `ExpFinalyseInserts` | `STAGING` | Read once; alias `S`. Supplies all 33 `NEW_*` columns. |
| Target (INSERT) | `FLT_FOLDER_LINKS` | `BASE` | Written to via `INSERT INTO`. |
| Anti-join reference | `FLT_FOLDER_LINKS` | `BASE` | Read inside `NOT EXISTS`; alias `T`. Same table as the INSERT target — suppresses rows already present. |

**Dependency order:** `STAGING.ExpFinalyseInserts` must be populated before this
statement runs. `BASE.FLT_FOLDER_LINKS` is both target and anti-join reference
(read-then-write within one statement).

---

## 9. Sign-off checklist

A reviewer can sign off from this document alone by confirming:

- [x] **Mechanical validity:** fixed file parses, 33 = 33 columns, no duplicates, no residual Teradata. (Validator PASS.)
- [x] **Minimal diff:** no SQL logic changed; only FIX LOG + TODO(SME) markers added.
- [x] **Control behaviour:** control PASS is expected for a semantic-only unit; not a re-fix trigger.
- [ ] **SEM-03 (CHAR padding):** reviewer confirms whether any of the 33 anti-join keys in `BASE.FLT_FOLDER_LINKS` are `CHAR(n)` and whether staging padding matches. If yes, apply `RTRIM()` to both sides of each `CHAR(n)` predicate.
- [ ] **SEM-06 (implicit cast):** reviewer confirms base column types match the `_SMALLINT`/`_DATE` staging casts. If types differ, make casts explicit.
- [ ] **No Teradata ground truth supplied:** every semantic inference is flagged `TODO(SME)`. If a `.teradata.sql` is later provided, re-run Stage 1 and diff statement count, set operators, and column list against it.

**Stage-6 semantic doc:** see `06_explain/output/semantic_S_vwxxx_MloadLinksInserts.md` for the clause-by-clause semantic account. This report references it; it does not duplicate it.