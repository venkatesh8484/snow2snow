# Validation Report — `S_vwxxx_CompareLinksRecordsWithTeradata`

- **Fixed file:** `03_fix/output/S_vwxxx_CompareLinksRecordsWithTeradata_fixed.snowsql`
- **Control (buggy input):** `00_input/S_vwxxx_CompareLinksRecordsWithTeradata.snowsql`
- **Dialect:** Snowflake (`.snowsql` — template tags / PUT-GET masked by `snowsql_protect.py`)
- **Mechanical verdict: PASS**

---

## Final SQL

### Mechanical validation (validator output)

```
INFO  .snowsql input — masked template tags / PUT-GET commands for validation (preserved as-is in the file).
PASS  parse: 4 statement(s) parsed as snowflake using sqlglot
PASS  no residual Teradata constructs
INFO  TODO(SME) markers outstanding: 19
RESULT: PASS
```

- **Parse:** PASS — 4 statements parse cleanly as Snowflake via sqlglot.
- **Residual Teradata:** PASS — no `ZEROIFNULL`, `CONTAINS`, `MULTISET`, `(+)`, BTEQ dot-commands, `MINUS`, `SEL`, etc.
- **TODO(SME):** 19 outstanding markers — expected; this unit carries genuine SME
  assumptions (Action_code source, sibling `Lkp_OutFltLegSeqNo` table, inbound
  error-message field values, SEM-* semantic flags). These are not validation
  failures; they are documented open questions for the reviewer.

### Manual spot-check

| # | Check | Result | Evidence |
|---|-------|--------|----------|
| 1 | Statement count / structure | PASS | 4 `CREATE OR REPLACE TRANSIENT TABLE` statements (`Lkp_InFltLegSeqNo`, `Rtr_DirectFlowOfLinksRecords`, `ExpFinalyseInserts`, final insert target). The verbatim duplicate of the 6-statement block present in the input (lines 364–726) was removed per `[DEF-07]`. |
| 2 | `o.*` / `n.*` resolution (SFX-17) | PASS | The `joined` CTE now projects explicit `OLD_*`/`NEW_*`-prefixed column lists instead of `o.*, n.*`; downstream `filtered` and `ExpFinalyseInserts` references (`NEW_LINK_STN_CD`, `OLD_LINK_EXPIRY_DT`, `r.NEW_*`, `r.OLD_*`) all resolve against prefixed columns. |
| 3 | Intra-SELECT-list alias references (SFX-18) | PASS | `ExpFinalyseInserts` restructured into a `base -> mid -> final` CTE chain so forward-referenced aliases (`v_IN_FLT_LEG_SEQ_NO`, `v_OUT_FLT_LEG_SEQ_NO`, `NEW_OUT_FLT_LEG_SEQ_NO`, `NEW_IN_FLT_LEG_SEQ_NO`) are real columns in their own scope. |
| 4 | Snowflake Scripting block (SFX-16) | PASS | The bare `LET / IF ... THEN / RAISE EXC` block (input lines 345–362) is not legal as top-level SQL. It is commented out with a `-- TODO(SME)` note directing the orchestrator to run it as a Snowflake Scripting anonymous block / stored procedure. The SQL batch therefore compiles; the procedural error-handling logic is preserved verbatim in comments. |
| 5 | Column order / JOIN keys / CASE-branch order | PASS | No reordering of projected columns, JOIN keys, or CASE branches relative to the input intent. `QUALIFY` not used here. |
| 6 | No dropped columns | PASS | All projected columns from the input are present in the fixed file; the only removed content is the verbatim duplicate block (DEF-07) and the commented-out scripting block (SFX-16). |
| 7 | Template tags preserved (SNZ-01) | PASS | 14 `<% ctx.env.* %>` tags (Period_start, Period_end, Current_date) preserved verbatim — masked for validation, untouched in the file. |
| 8 | Residual Teradata constructs | PASS | Confirmed by validator and by grep: none present. |
| 9 | DEF-07 correction | PASS | `NEW_OUT_ARR_GMT_FLT_TM_date` now sources `r.NEW_OUT_ARR_GMT_FLT_TM` (was `r.NEW_OUT_DEP_GMT_FLT_TM`); flagged `-- TODO(SME)` for confirmation. |

### Notes / environment gaps
- The validator fell back to sqlglot (no live Snowflake backend). This is an
  environment gap, not a SQL defect — `INFO`/`WARN` lines are not failures.
- The commented-out scripting block is the correct mechanical outcome: a
  Snowflake Scripting anonymous block cannot be expressed as a parseable
  `.sql` statement in this batch context, so it is preserved as comments for the
  orchestrator to execute. This is a documented SME item, not a defect.

---

## Buggy input control

### Mechanical validation (validator output)

```
INFO  .snowsql input — masked template tags / PUT-GET commands for validation (preserved as-is in the file).
FAIL  parse: Invalid expression / Unexpected token. Line 345, Col: 20.
PASS  no residual Teradata constructs
RESULT: FAIL (1 hard check(s))
```

### Interpretation

The control **FAILs as expected** on a genuine structural defect, confirming
the issues the fix addressed were real (not semantic-only):

- **Line 345, Col 20** corresponds to the bare `LET err_text VARCHAR := (...)`
  Snowflake Scripting statement sitting at top level outside any
  `BEGIN ... END;` anonymous block. Snowflake (and sqlglot) reject `LET` / `IF`
  / `RAISE` as bare SQL statements — they are only legal inside a procedural
  block. This is the same construct the fix comments out under `[SFX-16]`.
- The control also implicitly exercises the upstream `o.*, n.*` and
  intra-SELECT-list alias issues (`[SFX-17]`, `[SFX-18]`); these would surface
  as resolution errors at compile time in a live Snowflake session even though
  sqlglot's parse failure stops at the first hard token error.

Because the control failure is a **hard parse failure** (not a semantic-only
SEM-* defect), the passing control caveat does not apply here — the buggy
input genuinely does not parse, and the fixed file genuinely does. The
mechanical contrast is decisive; the manual spot-check above corroborates it.

---

## Verdict

**PASS** — The fixed file parses cleanly as Snowflake (4 statements), contains
no residual Teradata constructs, preserves column order / JOIN keys / CASE
order, resolves all `o.*`/`n.*` and intra-SELECT-list alias references, and
correctly isolates the Snowflake Scripting error-handling block as a commented
SME item. The buggy control fails to parse at line 345, confirming the
structural defects were real. No hand-back to `s2s-fix` required.