# Stage 1 — Analysis: `S_vwxxx_CompareLinksRecordsWithTeradata.snowsql`

**Input:** `00_input/S_vwxxx_CompareLinksRecordsWithTeradata.snowsql` (726 lines)
**Teradata ground truth:** **Not supplied.** No `00_input/S_vwxxx_CompareLinksRecordsWithTeradata.teradata.sql` exists. All semantic inferences are flagged `TODO(SME)`.
**Dialect target:** Snowflake (`.snowsql` — SnowSQL client layer applies, see §7).

---

## 0. Structural overview

The file is **726 lines** and consists of a single 6-statement block that is
**duplicated verbatim**:

| Block | Lines | Statements |
|---|---|---|
| A (original) | 1–363 | 6 statements |
| B (duplicate) | 364–726 | exact copy of A |

The 6 statements in block A are:

1. `CREATE OR REPLACE TRANSIENT TABLE staging.Lkp_InFltLegSeqNo AS …` (lines 1–62)
2. `CREATE OR REPLACE TRANSIENT TABLE STAGING.Rtr_DirectFlowOfLinksRecords AS …` (lines 63–178)
3. `CREATE OR REPLACE TRANSIENT TABLE STAGING.ExpFinalyseInserts AS …` (lines 179–344)
4. `LET err_text VARCHAR := (SELECT …)` — Snowflake Scripting (line 345)
5. `IF (err_text IS NOT NULL) THEN … RAISE EXC; END IF;` — Snowflake Scripting (lines 357–361)
6. `COMMIT;` (line 363)

Block B (364–726) is byte-identical to A and overwrites the same transient
tables — a pure copy-paste defect (see DEF-07 / §4).

**There are no `INSERT … SELECT` statements in this file.** Every statement is
`CREATE OR REPLACE TRANSIENT TABLE … AS SELECT`. The Stage-1 column-count check
(INSERT target cols vs SELECT expressions) therefore **does not apply** — there
is no INSERT target list to align against. The SELECT projections are instead
audited for alias/reference consistency (§3, §4).

---

## 1. Column-count check

| Statement | Type | INSERT cols | SELECT exprs | Net | Verdict |
|---|---|---|---|---|---|
| 1 — `Lkp_InFltLegSeqNo` | CTAS | n/a | 7 (FLT_LEG_SEQ_NO … ARR_STN_CD) | n/a | CTAS — no INSERT list |
| 2 — `Rtr_DirectFlowOfLinksRecords` | CTAS | n/a | `o.* , n.*` + 2 concat cols | n/a | CTAS — see SFX-17 |
| 3 — `ExpFinalyseInserts` | CTAS | n/a | ~30 expressions | n/a | CTAS — see SFX-18 / DEF-07 |

No INSERT…SELECT present. The CTAS projections are checked for alias/reference
defects in §3–§4 instead.

---

## 2. Syntax errors / residual-Teradata constructs

| # | Line(s) | Construct | Rule | Why invalid on Snowflake | Class |
|---|---|---|---|---|---|
| S1 | 124–125 | `SELECT o.*, n.*,` in `joined` CTE | **SFX-17 (proposed)** | Snowflake star expansion does **not** auto-prefix columns with the correlation name. The converter assumed Teradata-style `OLD_`/`NEW_` aliasing from `o.*`/`n.*`. Every downstream `OLD_*`/`NEW_*` reference (e.g. `OLD_LINK_STN_CD`, `NEW_LINK_STN_CD`, `OLD_LINK_EXPIRY_DT` at lines 153–170) will fail with "does not exist". Must be replaced with explicit `OLD_`/`NEW_`-prefixed column lists. | FIX |
| S2 | 345 | `LET err_text VARCHAR := (SELECT …)` | **SFX-16 (proposed)** | Snowflake Scripting construct. Not parseable by sqlglot or the Snowflake EXPLAIN backend. Must be commented out for mechanical validation and run as a Snowflake Scripting anonymous block / stored procedure by the orchestrator. | SME |
| S3 | 357–361 | `IF (err_text IS NOT NULL) THEN … SYSTEM$LOG_ERROR … LET EXC EXCEPTION … RAISE EXC; END IF;` | **SFX-16 (proposed)** | Snowflake Scripting block — same as S2. Procedural error-handling, not compilable SQL. | SME |
| S4 | 363 | `COMMIT;` | **SFX-16 (proposed)** | Session-level control statement. Comment out for validation; orchestrator issues `COMMIT` at the session level. | SME |
| S5 | 233, 282, 296, 308 | Intra-SELECT-list alias forward references (`v_IN_FLT_LEG_SEQ_NO`, `v_OUT_FLT_LEG_SEQ_NO`, `NEW_OUT_FLT_LEG_SEQ_NO`, `NEW_IN_FLT_LEG_SEQ_NO` referenced later in the same SELECT list) | **SFX-18 (proposed)** | Teradata permits referencing a SELECT-list alias later in the same SELECT list. Snowflake only allows alias references in `ORDER BY`/`HAVING`. Must restructure into a CTE chain (`base` → `mid` → `final`) so each alias becomes a real column in its own scope. | FIX |

**No residual Teradata keywords found:** no `ZEROIFNULL`, `CONTAINS`, `OVERLAPS`,
`SEL`, `SET`/`MULTISET` (in DDL), `PRIMARY INDEX`, `COLLECT STATS`, BTEQ
directives, `(+)` joins, `MINUS`, `TOP`, or `FORMAT`-casts. The file is
mechanically "Snowflake-ish" — the bugs are structural (SFX-16/17/18) and
defect-based, not keyword leftovers.

---

## 3. Defects

| # | Line(s) | Defect | Rule | Detail | Class |
|---|---|---|---|---|---|
| D1 | 252 | `r.NEW_OUT_DEP_GMT_FLT_TM AS NEW_OUT_ARR_GMT_FLT_TM_date` | **DEF-07** | Copy-paste defect: the alias claims to be the **arrival** time (`NEW_OUT_ARR_GMT_FLT_TM_date`) but the expression references the **departure** time (`NEW_OUT_DEP_GMT_FLT_TM`). The sibling line 251 already projects `NEW_OUT_DEP_GMT_FLT_TM AS NEW_OUT_DEP_GMT_FLT_TM_date`. The arrival-time slot should reference `r.NEW_OUT_ARR_GMT_FLT_TM`. Without Teradata ground truth we cannot prove the intended column — flag `TODO(SME)`. | SME |
| D2 | 364–726 | Entire 6-statement block duplicated verbatim | **DEF-07** | Lines 364–726 are a byte-identical copy of lines 1–363. The second copy re-runs the same `CREATE OR REPLACE TRANSIENT TABLE` statements, overwriting the same tables and doubling run time with no effect. Remove the duplicate block. | FIX |
| D3 | 336–342 | `LEFT JOIN STAGING.Lkp_OutFltLegSeqNo outlk` — table never created | **DEF-07 / new** | `STAGING.Lkp_OutFltLegSeqNo` is joined in statement 3 (line 336) but is **never created** anywhere in the file. Only `staging.Lkp_InFltLegSeqNo` (statement 1) is built. The outbound lookup table is missing — either a `CREATE … AS SELECT` for `Lkp_OutFltLegSeqNo` was dropped during conversion, or it must be created by mirroring the inbound lookup with `GMT_SCHED_DEP_TM` instead of `GMT_SCHED_ARR_TM`. Cannot resolve without ground truth → `TODO(SME)`. | SME |
| D4 | 224, 262, 344 | `r.Action_code` referenced but never projected | **DEF-07 / new** | `r.Action_code` is used in the `ExpFinalyseInserts` SELECT (lines 224, 262) and in the `WHERE r.Action_code IN ('I','B')` (line 344). However, `Action_code` is **not projected** by `Rtr_DirectFlowOfLinksRecords` (statement 2): the `joined`/`filtered` CTEs project `o.* , n.*` plus the two concat columns, and neither `old_links` nor `new_links` select an `Action_code` column. At runtime this raises "invalid identifier 'ACTION_CODE'". The column must either be added to the `new_links` projection (most likely source) or the reference is a converter artefact. → `TODO(SME)`. | SME |
| D5 | 296, 308 | Bare column refs in error-message IFF that match no alias | **DEF-07 / SFX-18** | The outbound error `IFF` (line 296) references `NEW_OUT_FLT_LEG_SEQ_NO`, `NEW_OUT_ALN_CD`, `NEW_OUT_FLT_NO`, `NEW_OUT_FLT_SFX_CD`, `NEW_OUT_DEP_GMT_FLT_DT`, `NEW_OUT_DEP_GMT_FLT_TM`, `NEW_LINK_STN_CD`, `NEW_OUT_DESTN_STN_CD` — but the actual aliases in the same SELECT list are `NEW_OUT_FLT_NO_smallint`, `NEW_OUT_DEP_GMT_FLT_DT_date`, etc. (type-suffixed). These bare names resolve to nothing in Snowflake. The SFX-18 CTE-chain restructure fixes this by carrying raw `r.NEW_*` columns in a `base` CTE. | FIX |
| D6 | 308 | Inbound error message uses `NEW_OUT_DEP_GMT_FLT_TM` for the inbound dep time | **DEF-07** | Line 308: `IN_DEP_GMT_FLT_DT=" ... || NEW_OUT_DEP_GMT_FLT_TM ||` — the inbound error string concatenates the **outbound** departure time (`NEW_OUT_DEP_GMT_FLT_TM`) where the **inbound** departure time should appear. Copy-paste from the outbound error block. Likely should be `NEW_IN_DEP_GMT_FLT_DT` (or its `_date` alias). Flag `TODO(SME)`. | SME |
| D7 | 308 | Inbound error message uses `NEW_OUT_DESTN_STN_CD` for `IN_DESTN_STN_CD` | **DEF-07** | Line 308: `IN_DESTN_STN_CD=" ... || NEW_OUT_DESTN_STN_CD ||` — the inbound error string labels the field `IN_DESTN_STN_CD` but concatenates the **outbound** destination. The inbound side has no `IN_DESTN_STN_CD` column (the inbound origin is `IN_ORIGN_STN_CD`). Likely a copy-paste from the outbound block. Flag `TODO(SME)`. | SME |

---

## 4. Semantic risks (SEM-*)

No Teradata ground truth supplied — every item is inferred and flagged `TODO(SME)`.

| # | Line(s) | Risk | Rule | Present? | Detail | Class |
|---|---|---|---|---|---|---|
| M1 | 124–125, 153–170 | `o.* , n.*` star expansion + `OLD_*`/`NEW_*` references | SFX-17 / SEM-10 | Yes | The join-key direction and the `OLD_*`/`NEW_*` naming rely on auto-prefixing that Snowflake does not perform. Once explicit prefixes are added (SFX-17), verify each `OLD_*`/`NEW_*` reference maps to the correct side. | SME |
| M2 | 87–88, 235–236, 284–285, 323 | `TO_DATE('<% … %>','DDMONYY')` / `TO_TIMESTAMP('<% … %>','DDMONYY')` | SEM-04 / SEM-06 | Yes | Template-tag values are string-cast to DATE/TIMESTAMP with `'DDMONYY'`. The `MON` token is locale-dependent; the template value format is unknown. If the orchestrator emits a different date format, the cast silently returns NULL or errors. Pin session locale / confirm template value format. | SME |
| M3 | 153, 170 | `OLD_LINK_EXPIRY_DT = TO_TIMESTAMP('31122050','DDMMYYYY')` | SEM-04 | Yes | The "far-future" sentinel `31122050` is cast with `'DDMMYYYY'`. Confirm this matches the source DDL type (TIMESTAMP vs DATE) and that the comparison is type-consistent. | SME |
| M4 | 124–178 | `OLD_concat_record <> NEW_concat_record` string comparison | SEM-03 / SEM-08 | Yes | The concat records mix `TO_CHAR`-formatted dates/times with raw columns. If any key is `CHAR(n)`, Teradata blank-pads and ignores trailing spaces in `=`; Snowflake does not. The `RTRIM`/`TRIM` calls on the NEW side (lines 142, 144–147) but not the OLD side suggest an asymmetry that could change which rows the `<>` filter keeps. | SME |
| M5 | 1–62, 364–425 | `QUALIFY ROW_NUMBER() OVER (… ORDER BY ssfl.opg_flt_leg_id DESC) = 1` | SEM-02 / SEM-07 | Yes | Dedup tie-break is on `opg_flt_leg_id DESC`. If `opg_flt_leg_id` is not unique per partition, the winner is non-deterministic. No `NULLS` clause — confirm NULL ordering matches Teradata. | SME |
| M6 | 224, 262 | `IFF(r.Action_code = 'I', …)` / `IFF(r.Action_code = 'B', …)` | SEM-06 | Yes | `Action_code` is a string compared to literals. Once D4 is resolved (column projected), confirm the value domain (`'I'`/`'B'`/others) and that no implicit cast is involved. | SME |
| M7 | 345–363 | `LET … IF … RAISE … COMMIT` error-handling block | SEM-05 (n/a) / SFX-16 | Yes | This is procedural SET-like control flow. There is no SET-table DDL here (all CTAS), so SEM-05 does not fire. The block is an error-abort guard, not a dedup. | SME |
| M8 | 252, 615 | `NEW_OUT_ARR_GMT_FLT_TM_date` defect (D1) | SEM-10 | Yes | The wrong-column reference (D1) is also a semantic-direction risk: the arrival-time slot is populated from the departure-time column. | SME |

**SEM-05 (SET-table) check:** No `INSERT` statements and no `UNION`/`UNION ALL`
writing to a single target. All statements are `CREATE OR REPLACE TRANSIENT
TABLE … AS SELECT` (overwrite semantics). **SEM-05 does not apply** — no SET vs
MULTISET question arises. No SME question raised on SEM-05.

**SEM-01 (integer division):** No `/` division on integer columns found. Not present.

---

## 5. Classification summary

| Class | Count | Items |
|---|---|---|
| **AUTO** | 0 | — |
| **FIX** | 4 | S1 (SFX-17), S5 (SFX-18), D2 (dup block), D5 (SFX-18 bare refs) |
| **SME** | 9 | S2/S3/S4 (SFX-16 Scripting), D1 (DEF-07 wrong col), D3 (missing table), D4 (Action_code), D6 (DEF-07 inbound err), D7 (DEF-07 inbound err), M2–M6 (SEM-*), M8 |
| **KEEP** | 7+ | SNZ-01 template tags (see §7) |

---

## 6. Proposed new rules (for human review)

| Proposed ID | Origin | Summary |
|---|---|---|
| **SFX-16** | lessons learned 2026-07-24 | Snowflake Scripting constructs (`LET`/`IF`/`RAISE`/`COMMIT`) are not parseable by sqlglot/EXPLAIN. Comment out for mechanical validation; orchestrator runs them as an anonymous block / stored procedure. Do **not** wrap in `BEGIN … END;` (still fails parser). |
| **SFX-17** | lessons learned 2026-07-24 | `SELECT o.*, n.*` does not auto-prefix columns with the correlation name in Snowflake. Replace with explicit `OLD_`/`NEW_`-prefixed column lists. |
| **SFX-18** | lessons learned 2026-07-24 | Intra-SELECT-list alias forward references are invalid in Snowflake (only `ORDER BY`/`HAVING`). Restructure into a CTE chain (`base` → `mid` → `final`) so each alias becomes a real column. |
| **DEF-07 (extension)** | this run | Missing lookup table (`Lkp_OutFltLegSeqNo`) joined but never created; `Action_code` referenced but never projected. Both are converter drop/loss defects — flag `TODO(SME)`, do not synthesise without ground truth. |

---

## 7. SnowSQL client layer (SNZ-*) — `.snowsql` only

| # | Line(s) | Construct | Rule | Classification |
|---|---|---|---|---|
| N1 | 87, 88 | `<% ctx.env.S_vw6122_…_Period_start %>`, `<% …_Period_end %>` in `TO_DATE` | SNZ-01 | **KEEP** |
| N2 | 235, 236 | `<% ctx.env.S_vw6122_…_Period_start/end %>` in `IN (…)` | SNZ-01 | **KEEP** |
| N3 | 284, 285 | `<% ctx.env.S_vw6122_…_Period_start/end %>` in `IN (…)` | SNZ-01 | **KEEP** |
| N4 | 323 | `<% ctx.env.S_vw6122_…_Current_date %>` in `TO_TIMESTAMP` | SNZ-01 | **KEEP** |
| N5 | 450, 451, 598, 599, 647, 648, 686 | Duplicate-block copies of N1–N4 | SNZ-01 | **KEEP** (removed with D2) |

**No `PUT`/`GET` commands (SNZ-02/03) and no `COPY INTO @stage`/`REMOVE`/`LIST`
(SNZ-04) present.** The SNZ inventory is 4 distinct template tags (×2 across the
duplicate block). All are preserved verbatim — never rewritten, never reported as
syntax defects. The fixed output file **must retain the `.snowsql` extension** so
`snowsql_protect.py` masking applies during validation.

---

## 8. Table dependency inventory

| Table | Role | Created by | Used at | Verdict |
|---|---|---|---|---|
| `BASE.schedule_sales_flt_leg` | SOURCE | external | stmt 1 (line 14) | OK — external source |
| `BASE.schedule_sales_mkg_leg` | SOURCE | external | stmt 1 (line 15) | OK — external source |
| `BASE.FLT_SCHEDULE_LINKS` | SOURCE | external | stmt 2 (line 84) | OK — external source |
| `STAGING.WRK_FLT_SCHED_LINKS` | SOURCE | external (upstream stage) | stmt 2 (line 112) | OK — assumed populated by prior job |
| `staging.Lkp_InFltLegSeqNo` | TARGET then SOURCE | stmt 1 (line 1) | stmt 3 (line 333) | OK — created then consumed |
| `STAGING.Rtr_DirectFlowOfLinksRecords` | TARGET then SOURCE | stmt 2 (line 63) | stmt 3 (line 331) | OK — created then consumed |
| `STAGING.ExpFinalyseInserts` | TARGET | stmt 3 (line 179) | stmt 4 (line 350) | OK — created then consumed by error check |
| **`STAGING.Lkp_OutFltLegSeqNo`** | SOURCE (missing) | **never created** | stmt 3 (line 336) | **⚠ MISSING** — joined but no DDL/CTAS in file (D3) |

**One-line verdict:** The file is a 3-step CTAS pipeline (inbound lookup →
old/new link compare → finalise inserts) with a procedural error-abort tail, but
it is **not runnable as-is**: the `o.*, n.*` star expansion (SFX-17), intra-SELECT
alias references (SFX-18), missing `Lkp_OutFltLegSeqNo` table (D3), unprojected
`Action_code` (D4), a copy-paste column defect (D1/D6/D7), a verbatim duplicate
block (D2), and unparseable Snowflake Scripting (SFX-16) all prevent successful
execution. No Teradata ground truth is available, so every semantic inference
carries `TODO(SME)`.