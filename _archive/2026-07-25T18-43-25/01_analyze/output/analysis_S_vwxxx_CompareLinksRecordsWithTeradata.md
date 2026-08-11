# Stage 1 — Analysis: S_vwxxx_CompareLinksRecordsWithTeradata

**Input:** `00_input/S_vwxxx_CompareLinksRecordsWithTeradata.snowsql` (726 lines)
**Teradata ground truth:** Not supplied.
**File type:** `.snowsql` (SnowSQL client layer — SNZ-* rules apply).

---

## 0. File structure overview

The file contains **two identical blocks** (lines 1–363 and 364–726). Each block
is the same 6-statement sequence:

1. `CREATE OR REPLACE TRANSIENT TABLE staging.Lkp_InFltLegSeqNo AS …` (CTAS)
2. `CREATE OR REPLACE TRANSIENT TABLE STAGING.Rtr_DirectFlowOfLinksRecords AS …` (CTAS)
3. `CREATE OR REPLACE TRANSIENT TABLE STAGING.ExpFinalyseInserts AS …` (CTAS)
4. `LET err_text VARCHAR := (SELECT ANY_VALUE(err_text) FROM …)` (Snowflake Scripting)
5. `IF (err_text IS NOT NULL) THEN … RAISE EXC; END IF;` (Snowflake Scripting)
6. `COMMIT;`

All line numbers below cite the **first block** (lines 1–363). The same findings
apply identically to the second block (lines 364–726) at offset +363.

---

## 1. Column-count check

There are **no `INSERT … SELECT` statements** in this file. All data-movement
statements are `CREATE OR REPLACE TABLE … AS SELECT` (CTAS), where the target
columns are defined by the SELECT aliases. No INSERT/SELECT column-count
mismatch is possible.

| Statement | Type | INSERT cols | SELECT exprs | Net | Status |
|---|---|---|---|---|---|
| `Lkp_InFltLegSeqNo` (line 1) | CTAS | N/A | 7 | — | OK |
| `Rtr_DirectFlowOfLinksRecords` (line 46) | CTAS | N/A | `o.*` + `n.*` + 2 concat | — | See DEF-08 |
| `ExpFinalyseInserts` (line 204) | CTAS | N/A | ~35 expressions | — | See DEF-09/10 |

---

## 2. Syntax errors / residual-Teradata constructs

| # | Line(s) | Construct | Rule | Why invalid on Snowflake | Class |
|---|---|---|---|---|---|
| S-01 | 345–362 | `LET err_text VARCHAR := …; IF … THEN … LET EXC EXCEPTION := …; RAISE EXC; END IF;` — Snowflake Scripting block **without `BEGIN … END;` wrapper** | **New rule proposed: SFX-16** | Snowflake Scripting constructs (`LET`, `IF … THEN`, `RAISE`, `EXCEPTION`) are only valid inside a `BEGIN … END;` anonymous block or a stored procedure. At top level (separated by semicolons as individual SQL statements) they are syntax errors. | **FIX** |
| S-02 | 128–149, 154–175 (×2 blocks) | `IFNULL(x, '')` used in 44 concatenation expressions | — | `IFNULL` **is valid** in Snowflake (alias for `NVL`/2-arg `COALESCE`). Not a defect. Listed for completeness — no action needed. | — |
| S-03 | 192–200 (×2) | `NEW_LINK_STN_CD`, `OLD_LINK_EXPIRY_DT`, `OLD_LINK_STN_CD` referenced in `filtered` CTE WHERE clause | **New rule proposed: SFX-17** | These column names **do not exist** in the `joined` CTE. `joined` does `SELECT o.*, n.*` — column names are the raw names from `old_links`/`new_links` (e.g. `LINK_STN_CD`, `LINK_EXPIRY_DT`), **not** `OLD_`/`NEW_`-prefixed. Snowflake will raise "does not exist or not authorized" at resolution time. | **FIX** |
| S-04 | 207–344 (×2) | `r.NEW_LINK_STN_CD`, `r.NEW_IN_FLT_NO`, `r.OLD_IN_FLT_LEG_SEQ_NO`, `r.OLD_OUT_ALN_CD`, etc. — all `r.NEW_*` and `r.OLD_*` references in `ExpFinalyseInserts` | **New rule proposed: SFX-17** | Same root cause as S-03. `Rtr_DirectFlowOfLinksRecords` has columns named `LINK_STN_CD`, `IN_FLT_NO`, `IN_FLT_LEG_SEQ_NO`, etc. (from `o.*`/`n.*`). The `NEW_`/`OLD_` prefixes were never added. Every `r.NEW_*` / `r.OLD_*` reference will fail at resolution. | **FIX** |
| S-05 | 224, 262, 344 (×2) | `r.Action_code` referenced in `ExpFinalyseInserts` | **DEF-07** | `Action_code` is not projected by either `old_links` or `new_links` CTEs (both use explicit column lists). It does not exist in `Rtr_DirectFlowOfLinksRecords`. | **SME** |
| S-06 | 219→229, 273→279, 279→290, 239→302 (×2) | Intra-SELECT-list alias references: `v_IN_FLT_LEG_SEQ_NO`, `v_OUT_FLT_LEG_SEQ_NO`, `NEW_OUT_FLT_LEG_SEQ_NO`, `NEW_IN_FLT_LEG_SEQ_NO` defined as aliases then referenced later in the same SELECT list | **New rule proposed: SFX-18** | Snowflake does **not** allow referencing a SELECT-list alias elsewhere in the same SELECT list (only in `ORDER BY` / `HAVING`). Teradata permits this. All four alias chains will fail with "does not exist". | **FIX** |
| S-07 | 293–300, 305–309 (×2) | Error-message IFF expressions reference bare column names: `NEW_OUT_ALN_CD`, `NEW_OUT_FLT_NO`, `NEW_OUT_FLT_SFX_CD`, `NEW_OUT_DEP_GMT_FLT_DT`, `NEW_OUT_DEP_GMT_FLT_TM`, `NEW_LINK_STN_CD`, `NEW_OUT_DESTN_STN_CD`, `NEW_IN_ALN_CD`, `NEW_IN_FLT_NO`, `NEW_IN_FLT_SFX_CD`, `NEW_IN_DEP_GMT_FLT_DT` | SFX-18 + DEF-09 | Two problems: (a) intra-SELECT-list alias references (SFX-18); (b) some of these names don't match any alias — e.g. `NEW_IN_FLT_NO` when the alias is `NEW_IN_FLT_NO_smallint`, `NEW_OUT_FLT_NO` when the alias is `NEW_OUT_FLT_NO_smallint`, `NEW_OUT_DEP_GMT_FLT_DT` when the alias is `NEW_OUT_DEP_GMT_FLT_DT_date`. | **FIX** |

### Proposed new rules (for human review)

| Proposed ID | Pattern | Fix | Notes |
|---|---|---|---|
| **SFX-16** | Snowflake Scripting constructs (`LET`, `IF … THEN`, `RAISE`, `EXCEPTION`) used at top level without `BEGIN … END;` wrapper | Wrap the scripting block in `BEGIN … END;` | The converter dropped the BTEQ control-flow wrapper but left Snowflake Scripting constructs as bare statements. They need an anonymous block. |
| **SFX-17** | `SELECT o.*, n.*` in a FULL OUTER JOIN, then downstream references to `OLD_<col>` / `NEW_<col>` prefixed names that were never declared | Replace `o.*, n.*` with explicit column lists using `OLD_`/`NEW_` prefixes: `o.LINK_STN_CD AS OLD_LINK_STN_CD, n.LINK_STN_CD AS NEW_LINK_STN_CD, …` | The converter assumed `o.*`/`n.*` would auto-prefix; it does not. Every downstream `OLD_*`/`NEW_*` reference is broken. |
| **SFX-18** | SELECT-list alias defined and then referenced by name later in the same SELECT list (Teradata forward-reference pattern) | Either repeat the full expression, or restructure using nested CTEs / `LATERAL` so each alias is resolved in its own scope | Teradata allows referencing earlier SELECT aliases within the same SELECT list; Snowflake does not. |

---

## 3. Defects (DEF-*)

| # | Line(s) | Defect | Rule | Notes | Class |
|---|---|---|---|---|---|
| D-01 | 250, 252 (×2) | `r.NEW_OUT_DEP_GMT_FLT_TM` used for **two** different target aliases: `NEW_OUT_DEP_GMT_FLT_TM_date` (line 250) and `NEW_OUT_ARR_GMT_FLT_TM_date` (line 252). The second should be `r.NEW_OUT_ARR_GMT_FLT_TM`. | DEF-07 | Copy-paste error: the outbound **arrival** time slot is populated with the outbound **departure** time. | **SME** |
| D-02 | 308 (×2) | Inbound error message uses `NEW_OUT_DEP_GMT_FLT_TM` for the `IN_DEP_GMT_FLT_TM` field: `IN_DEP_GMT_FLT_TM="' \|\| NEW_OUT_DEP_GMT_FLT_TM` | DEF-07 | Copy-paste from outbound error message. Should use the inbound departure time. | **SME** |
| D-03 | 309 (×2) | Inbound error message uses `NEW_OUT_DESTN_STN_CD` for `IN_DESTN_STN_CD` field | DEF-07 | May be intentional (the "inbound destination" is the link station = outbound origin), but without ground truth this is a suspected copy-paste from the outbound error message. | **SME** |
| D-04 | 336 (×2) | `LEFT JOIN STAGING.Lkp_OutFltLegSeqNo outlk` — table is **referenced but never created** in this file | DEF-07 | Only `Lkp_InFltLegSeqNo` is created. `Lkp_OutFltLegSeqNo` is an unresolved external dependency. May be created by another unit in the pipeline. | **SME** |
| D-05 | 1–363 vs 364–726 | The entire 6-statement block is **duplicated verbatim** | DEF-07 | Lines 364–726 are an exact copy of lines 1–363. Likely accidental duplication. The second block overwrites the same transient tables. | **SME** |
| D-06 | 340 (×2) | `outlk.GMT_SCHED_DEP_TM` referenced in join condition, but `Lkp_OutFltLegSeqNo` is never created — its column list is unknown | DEF-07 | If the outbound lookup table is meant to mirror `Lkp_InFltLegSeqNo`, it should have `GMT_SCHED_DEP_TM` (departure time) instead of `GMT_SCHED_ARR_TM` (arrival time). Cannot verify without DDL. | **SME** |

---

## 4. Semantic risks (SEM-*)

| # | Line(s) | Risk | Rule | Present? | Notes | Class |
|---|---|---|---|---|---|---|
| SEM-01 | — | Integer division | SEM-01 | **No** | No division operators found. | — |
| SEM-02 | 27–44 (×2) | `QUALIFY ROW_NUMBER() OVER (… ORDER BY ssfl.opg_flt_leg_id DESC) = 1` | SEM-02 | **Yes** | If `opg_flt_leg_id` is unique, ties are impossible and ordering is deterministic. If not unique, the winner is non-deterministic. Low risk but flag. | **SME** |
| SEM-03 | 80, 113 (×2) | `TRIM(IN_FLT_SFX_CD)`, `TRIM(OUT_FLT_SFX_CD)` in `new_links`; join on `n.IN_FLT_SFX_CD = o.IN_FLT_SFX_CD` (line 183) | SEM-03 | **Yes** | `old_links` does **not** TRIM `IN_FLT_SFX_CD` or `OUT_FLT_SFX_CD`. If these are `CHAR(n)` columns, Teradata blank-pads and the untrimmed `o.` side may mismatch the trimmed `n.` side. The join condition compares `n.IN_FLT_SFX_CD` (trimmed) to `o.IN_FLT_SFX_CD` (untrimmed). | **SME** |
| SEM-04 | 193, 268, 323 (×2) | `TO_TIMESTAMP('31122050','DDMMYYYY')`, `TRY_TO_TIMESTAMP(…,'DDMONYY')`, `TO_TIMESTAMP('<% ctx.env…%>','DDMONYY')` | SEM-04 | **Yes** | All `TO_TIMESTAMP` calls produce `TIMESTAMP_NTZ` (no timezone). No session `TIMEZONE` is pinned. If source data has timezone semantics, values may shift. | **SME** |
| SEM-05 | — | SET-table dedup | SEM-05 | **No** | All targets are `CREATE OR REPLACE TRANSIENT TABLE` (CTAS), not `INSERT`. No SET/MULTISET DDL supplied. SEM-05 does not apply. | — |
| SEM-06 | 234–236, 283–285 (×2) | `r.NEW_IN_ARR_GMT_FLT_DT IN ('<% ctx.env…start%>', '<% ctx.env…end%>')` — comparing a date/timestamp column to template-string literals | SEM-06 | **Yes** | The implicit cast from string to date depends on session defaults and the column type. If `NEW_IN_ARR_GMT_FLT_DT` is a DATE, the string literals must be parseable dates. If it's a TIMESTAMP, the comparison may silently mismatch. | **SME** |
| SEM-07 | 27–44 (×2) | `ORDER BY ssfl.opg_flt_leg_id DESC` in QUALIFY — no explicit `NULLS FIRST/LAST` | SEM-07 | **Yes** | If `opg_flt_leg_id` can be NULL, Snowflake defaults to `NULLS FIRST` for `DESC`, which would let NULL-keyed rows win the dedup. Low risk if the column is non-nullable. | **SME** |
| SEM-08 | 128–175 (×2) | `IFNULL(x, '')` — empty string used as NULL replacement in concatenation | SEM-08 | **Yes** | In Snowflake, `''` is a real empty string (not NULL). This is **intentional** for concatenation (to avoid NULL propagating through `\|\|`). Behavior is correct. Flag for awareness. | — |
| SEM-09 | — | Aggregate of empty set | SEM-09 | **No** | No aggregate functions in the main query (only `ANY_VALUE` in the error-check subquery, which is safe). | — |
| SEM-10 | 329–342 (×2) | Join key direction: `inlk.OPERATING_AIRLINE_CD = r.NEW_IN_ALN_CD`, `outlk.OPERATING_AIRLINE_CD = r.NEW_OUT_ALN_CD` | SEM-10 | **Yes** | The lookup tables join on `OPERATING_*` columns to `NEW_IN_*`/`NEW_OUT_*` columns. Without DDL/ground truth, cannot confirm these are the same grain. The `CAST(r.NEW_IN_FLT_NO AS INT)` on both sides of the join (lines 331, 333) suggests type alignment, but the semantic direction is unverified. | **SME** |

---

## 5. SnowSQL client layer inventory (SNZ-*)

| # | Line(s) | Construct | Rule | Classification |
|---|---|---|---|---|
| SNZ-01 | 87, 88 | `<% ctx.env.S_vw6122_CompareLinksRecordsWithTeradata_Period_start %>` / `_end %>` in `TO_DATE(…)` | SNZ-01 | **KEEP** |
| SNZ-01 | 235, 236 | `<% ctx.env.…Period_start %>` / `_end %>` in `IN (…)` list | SNZ-01 | **KEEP** |
| SNZ-01 | 284, 285 | Same template tags in outbound boundary validation `IN (…)` list | SNZ-01 | **KEEP** |
| SNZ-01 | 323 | `<% ctx.env.S_vw6122_CompareLinksRecordsWithTeradata_Current_date %>` in `TO_TIMESTAMP(…)` | SNZ-01 | **KEEP** |
| SNZ-01 | 450, 451 | Same Period_start/end tags (second block) | SNZ-01 | **KEEP** |
| SNZ-01 | 598, 599 | Same (second block, inbound validation) | SNZ-01 | **KEEP** |
| SNZ-01 | 647, 648 | Same (second block, outbound validation) | SNZ-01 | **KEEP** |
| SNZ-01 | 686 | Same Current_date tag (second block) | SNZ-01 | **KEEP** |

**Summary:** 14 template-tag occurrences (SNZ-01), 3 distinct env variables:
- `S_vw6122_CompareLinksRecordsWithTeradata_Period_start`
- `S_vw6122_CompareLinksRecordsWithTeradata_Period_end`
- `S_vw6122_CompareLinksRecordsWithTeradata_Current_date`

No `PUT`/`GET` commands (SNZ-02/03) found. No `COPY INTO @stage` / `REMOVE` / `LIST` (SNZ-04) found.

All SNZ-01 constructs are classified **KEEP** — preserve verbatim, never rewrite, never report as syntax defects.

---

## 6. Classification summary

| Class | Count | Description |
|---|---|---|
| **AUTO** | 0 | No mechanical rule-fixable items (no existing SFX/FNX/DTX rules fire) |
| **FIX** | 4 | S-01 (missing BEGIN…END), S-03 (filtered WHERE broken refs), S-04 (ExpFinalyseInserts broken refs), S-06 (intra-SELECT alias refs), S-07 (error-message alias refs) — all require proposed new rules SFX-16/17/18 |
| **SME** | 9 | S-05 (Action_code), D-01 (OUT_ARR vs OUT_DEP), D-02 (IN error uses OUT time), D-03 (IN_DESTN uses OUT_DESTN), D-04 (Lkp_OutFltLegSeqNo missing), D-05 (duplicated block), D-06 (outlk column list), SEM-02/03/04/06/07/10 |
| **KEEP** | 14 | SNZ-01 template tags (preserve verbatim) |

---

## 7. Table dependency inventory

| Table | Schema | Role | Lines | Notes |
|---|---|---|---|---|
| `schedule_sales_flt_leg` | BASE | Source (read) | 21 | Flight leg source |
| `schedule_sales_mkg_leg` | BASE | Source (read) | 22 | Marketing leg source for BA filter |
| `FLT_SCHEDULE_LINKS` | BASE | Source (read) | 74 | Old/current links |
| `WRK_FLT_SCHED_LINKS` | STAGING | Source (read) | 110 | New/working links |
| `Lkp_InFltLegSeqNo` | staging | Target (CTAS) → Source (read) | 1, 329 | Created then joined to |
| `Lkp_OutFltLegSeqNo` | STAGING | Source (read) | 336 | **Never created in this file** — external dependency |
| `Rtr_DirectFlowOfLinksRecords` | STAGING | Target (CTAS) → Source (read) | 46, 326 | Created then read by ExpFinalyseInserts |
| `ExpFinalyseInserts` | STAGING | Target (CTAS) → Source (read) | 204, 345 | Created then read by error-check subquery |

---

## 8. Verdict

**Cannot run on Snowflake — 3 structural breakages (missing BEGIN…END wrapper, `o.*`/`n.*` without OLD_/NEW_ prefixing, and intra-SELECT-list alias references) prevent resolution; 6 SME items need human decisions before a fix can be attempted.**