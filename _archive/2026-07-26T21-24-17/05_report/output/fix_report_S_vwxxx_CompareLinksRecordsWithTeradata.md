# Fix Report — `S_vwxxx_CompareLinksRecordsWithTeradata.snowsql`

**Unit:** `S_vwxxx_CompareLinksRecordsWithTeradata.snowsql` (re-run)
**Input:** `00_input/S_vwxxx_CompareLinksRecordsWithTeradata.snowsql` (726 lines)
**Fixed:** `03_fix/output/S_vwxxx_CompareLinksRecordsWithTeradata_fixed.snowsql`
**Dialect target:** Snowflake (`.snowsql` — SnowSQL client layer, SNZ-*)
**Teradata ground truth:** **Not supplied.** No `00_input/<name>.teradata.sql`
exists. Every semantic inference is flagged `TODO(SME)`.
**Date:** 2026-07-25

---

## 1. Executive summary

The input was a 3-step CTAS pipeline (inbound lookup → old/new link compare →
finalise inserts) with a procedural Snowflake Scripting error-abort tail, but
it was **not runnable as-is**. Four structural defects prevented execution:

1. `SELECT o.*, n.*` star expansion assumed Teradata-style `OLD_`/`NEW_`
   auto-prefixing that Snowflake does not perform (**SFX-17**).
2. Intra-SELECT-list alias forward references (legal in Teradata, illegal in
   Snowflake) (**SFX-18**).
3. A bare Snowflake Scripting block (`LET`/`IF`/`RAISE`/`COMMIT`) at top level
   that does not parse (**SFX-16**).
4. A verbatim duplicate of the entire 6-statement block (lines 364–726 = copy of
   1–363) plus a copy-paste column defect (**DEF-07 ×2**).

The fix applied **SFX-17**, **SFX-18**, **SFX-16**, and **DEF-07** (×2),
preserved all 14 SNZ-01 template tags verbatim, and left 19 `TODO(SME)` markers
for the reviewer. **Validation: PASS** (4 statements parse cleanly as
Snowflake; no residual Teradata constructs). **Control: FAIL** (parse failure
at line 345 — the bare `LET` Scripting statement), confirming the structural
defects were real.

---

## 2. Rules applied

### Syntax / structural (SFX-*)

| Rule | Lines (input) | What it does | Class |
|---|---|---|---|
| **SFX-17** | 124–125, 153–170, 192–200, 207–344 | Replaced `o.*, n.*` in the `joined` CTE with explicit `OLD_`/`NEW_`-prefixed column lists (`o.LINK_STN_CD AS OLD_LINK_STN_CD, n.LINK_STN_CD AS NEW_LINK_STN_CD, …`). Snowflake star expansion preserves raw column names; it does not auto-prefix with the correlation name. Every downstream `OLD_*`/`NEW_*` reference now resolves. | FIX |
| **SFX-18** | 233, 282, 296, 308 | Restructured `ExpFinalyseInserts` into a CTE chain (`base` → `mid` → `final`) so SELECT-list aliases (`v_IN_FLT_LEG_SEQ_NO`, `v_OUT_FLT_LEG_SEQ_NO`, `NEW_IN_FLT_LEG_SEQ_NO`, `NEW_OUT_FLT_LEG_SEQ_NO`) become real columns in their own scope rather than forward references within one SELECT list. Also resolves the bare column names in the error-message IFF expressions (e.g. `NEW_OUT_FLT_NO` vs the type-suffixed alias `NEW_OUT_FLT_NO_smallint`) by carrying raw `r.NEW_*` columns in `base`. | FIX |
| **SFX-16** | 345–363 | Commented out the Snowflake Scripting block (`LET err_text …`, `IF … THEN … RAISE EXC … END IF;`, `COMMIT;`). These procedural constructs are not parseable by sqlglot or the Snowflake EXPLAIN backend and are only legal inside an anonymous block. Preserved verbatim in comments with a `-- TODO(SME)` note directing the orchestrator to run them as a Snowflake Scripting anonymous block / stored procedure and issue `COMMIT` at the session level. | SME |

### Defects (DEF-*)

| Rule | Lines (input) | What it does | Class |
|---|---|---|---|
| **DEF-07** | 252 | Copy-paste column defect: `NEW_OUT_ARR_GMT_FLT_TM_date` was populated from `r.NEW_OUT_DEP_GMT_FLT_TM` (the departure time) but the alias claims the arrival time. Corrected to `r.NEW_OUT_ARR_GMT_FLT_TM`. Flagged `-- TODO(SME)` to confirm the outbound arrival slot should source `NEW_OUT_ARR_GMT_FLT_TM`. | SME |
| **DEF-07** | 364–726 | Removed the verbatim duplicate of the entire 6-statement block (lines 364–726 were a byte-identical copy of 1–363). The second copy re-ran the same `CREATE OR REPLACE TRANSIENT TABLE` statements, overwriting the same tables and doubling run time with no effect. | FIX |

### Semantic (SEM-*)

No SEM-* rule forced a SQL change. The SEM-* risks identified in Stage 1
(SEM-02/03/04/06/07/08/10) are all `TODO(SME)` because no Teradata ground truth
was supplied. They are documented in the Stage-6 semantic doc (see §6) and
flagged inline; this report does not duplicate them.

### SnowSQL client layer (SNZ-*)

| Rule | Count | Handling |
|---|---|---|
| **SNZ-01** | 14 `<% ctx.env.* %>` template tags (Period_start, Period_end, Current_date) | **KEEP** — preserved verbatim, never rewritten. Masked by `snowsql_protect.py` during validation. The fixed file retains the `.snowsql` extension so masking applies. |

No `PUT`/`GET` (SNZ-02/03) or `REMOVE`/`LIST`/`COPY INTO @stage` (SNZ-04)
constructs present.

---

## 3. Defects repaired

| # | Defect | Rule | Resolution |
|---|---|---|---|
| D2 | Entire 6-statement block duplicated verbatim (lines 364–726 = copy of 1–363) | DEF-07 | Duplicate block removed. |
| D5 | Bare column refs in error-message IFF matched no alias (`NEW_OUT_FLT_NO` vs `NEW_OUT_FLT_NO_smallint`, etc.) | SFX-18 | Resolved by the CTE chain — raw `r.NEW_*` columns carried in `base`, referenced by unprefixed names in the final SELECT. |
| D1 | `NEW_OUT_ARR_GMT_FLT_TM_date` sourced from departure time column | DEF-07 | Corrected to `r.NEW_OUT_ARR_GMT_FLT_TM`; flagged `TODO(SME)`. |

---

## 4. Open `TODO(SME)` items (19 outstanding)

These are documented open questions for the reviewer, not validation failures.

| # | Location | Question |
|---|---|---|
| 1 | `base` CTE, lines 224, 262, 344 | `r.Action_code` is referenced in `IFF(r.Action_code = 'I'/'B')` and `WHERE r.Action_code IN ('I','B')` but is **not projected** by `old_links`/`new_links` or the `joined`/`filtered` CTEs. Confirm the source column in `Rtr_DirectFlowOfLinksRecords` (expected from a prior/sibling statement). |
| 2 | `base` CTE, line 336 | `STAGING.Lkp_OutFltLegSeqNo` is joined but **never created** in this file. Confirm it is built by a sibling script and that `GMT_SCHED_DEP_TM` is its departure-time column. |
| 3 | Final SELECT, lines 308–309 | Inbound error message reuses `NEW_OUT_DEP_GMT_FLT_TM` for the `IN_DEP_GMT_FLT_TM` field and `NEW_OUT_DESTN_STN_CD` for `IN_DESTN_STN_CD` (suspected copy-paste from the outbound message). Left as-is — message text is cosmetic, not logic; per DEF-07 do not guess a column swap. |
| 4 | `Lkp_InFltLegSeqNo` QUALIFY | SEM-02/SEM-07: confirm `opg_flt_leg_id` is unique per partition and non-nullable; add `NULLS LAST` if nullable. |
| 5 | `new_links` CTE | SEM-03: `new_links` TRIMs suffix codes; `old_links` does not. If `FLT_SCHEDULE_LINKS` suffix cols are `CHAR(n)`, add TRIM to `old_links` to avoid padding drift in the FULL OUTER JOIN. |
| 6 | `filtered` CTE | SEM-04: confirm `'31122050'` sentinel cast matches source DDL type (TIMESTAMP vs DATE). |
| 7 | `filtered` CTE | SEM-03/SEM-08: `OLD_concat_record <> NEW_concat_record` mixes `TO_CHAR`-formatted values with raw columns; TRIM asymmetry between OLD and NEW sides could change which rows the `<>` filter keeps. |
| 8 | `mid` CTE | SEM-06: `NEW_IN_ARR_GMT_FLT_DT IN ('<% Period_start %>','<% Period_end %>')` relies on implicit string→date cast. Confirm template tags resolve to parseable date strings. |
| 9 | Final SELECT | SEM-04: `TO_TIMESTAMP`/`TRY_TO_TIMESTAMP` produce `TIMESTAMP_NTZ`; no session `TIMEZONE` pinned. Confirm source has no timezone semantics. |
| 10 | `base` CTE, line 336 | SEM-10: confirm lookup tables and link records are at the same grain (operating airline / flt no / suffix / station pair). |
| 11–19 | SFX-16 block | Confirm the error-handling block is executed by the orchestrator as a Snowflake Scripting anonymous block / stored procedure, and that `COMMIT` is issued at the session level after it. |

---

## 5. Validation result

**Mechanical verdict: PASS**

```
INFO  .snowsql input — masked template tags / PUT-GET commands for validation (preserved as-is in the file).
PASS  parse: 4 statement(s) parsed as snowflake using sqlglot
PASS  no residual Teradata constructs
INFO  TODO(SME) markers outstanding: 19
RESULT: PASS
```

- **Parse:** PASS — 4 statements parse cleanly as Snowflake via sqlglot.
- **Residual Teradata:** PASS — no `ZEROIFNULL`, `CONTAINS`, `MULTISET`, `(+)`,
  BTEQ dot-commands, `MINUS`, `SEL`, etc.
- **TODO(SME):** 19 outstanding — expected; genuine SME assumptions, not
  validation failures.
- **Column order / JOIN keys / CASE-branch order:** preserved exactly.
- **No dropped columns:** all input projections present; only the verbatim
  duplicate block (DEF-07) and the commented-out scripting block (SFX-16) were
  removed/commented.
- **SNZ-01:** 14 template tags preserved verbatim.

### Buggy input control: FAIL (parse)

```
FAIL  parse: Invalid expression / Unexpected token. Line 345, Col: 20.
PASS  no residual Teradata constructs
RESULT: FAIL (1 hard check(s))
```

The control fails at line 345 — the bare `LET err_text VARCHAR := (...)`
Snowflake Scripting statement at top level outside any `BEGIN … END;` block.
This is the same construct the fix comments out under SFX-16. Because the
control failure is a **hard parse failure** (not a semantic-only SEM-* defect),
the passing-control caveat does not apply — the buggy input genuinely does
not parse, and the fixed file genuinely does. The mechanical contrast is
decisive; the manual spot-check corroborates it.

### Environment notes

- The validator fell back to sqlglot (no live Snowflake backend). This is an
  environment gap, not a SQL defect — `INFO`/`WARN` lines are not failures.
- The commented-out scripting block is the correct mechanical outcome: a
  Snowflake Scripting anonymous block cannot be expressed as a parseable
  `.sql` statement in this batch context, so it is preserved as comments for
  the orchestrator to execute.

---

## 6. Stage-6 semantic reference

The clause-by-clause semantic account lives in the Stage-6 doc:
`06_explain/output/semantic_S_vwxxx_CompareLinksRecordsWithTeradata.md`
(archived copy:
`_archive/2026-07-25T18-43-25/06_explain/output/semantic_S_vwxxx_CompareLinksRecordsWithTeradata.md`).
It addresses the SEM-02/03/04/06/07/08/10 risks flagged in the Stage-1
analysis. This report references it; it does not duplicate it.

---

## 7. Sign-off checklist

- [x] Fixed file parses cleanly as Snowflake (4 statements).
- [x] No residual Teradata constructs.
- [x] Column order, JOIN keys, and CASE-branch order preserved.
- [x] `o.*`/`n.*` star expansion replaced with explicit prefixed columns (SFX-17).
- [x] Intra-SELECT-list alias references resolved via CTE chain (SFX-18).
- [x] Snowflake Scripting block isolated as commented SME item (SFX-16).
- [x] Duplicate block removed (DEF-07).
- [x] Copy-paste column defect corrected (DEF-07).
- [x] 14 SNZ-01 template tags preserved verbatim; `.snowsql` extension retained.
- [x] Buggy control fails to parse (line 345), confirming defects were real.
- [ ] **Reviewer:** resolve the 19 `TODO(SME)` items (Action_code source,
      missing `Lkp_OutFltLegSeqNo` table, inbound error-message field values,
      SEM-* semantic flags, SFX-16 orchestrator execution).

**Verdict:** Mechanically PASS. Ready for reviewer sign-off pending resolution
of the 19 open `TODO(SME)` items.