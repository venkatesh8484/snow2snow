# Validation report — ins_wrk_dc_priority

**Unit:** ins_wrk_dc_priority
**Fixed file:** `03_fix/output/ins_wrk_dc_priority_fixed.sql`
**Control file:** `00_input/ins_wrk_dc_priority_snowflake.sql`
**Mechanical verdict:** PASS

---

## Final SQL

### Mechanical validation (validator output)

```
PASS  parse: 1 statement(s) parsed as snowflake using sqlglot
PASS  stmt 1: INSERT columns (131) == SELECT expressions (131)
PASS  stmt 1: no duplicate INSERT columns
PASS  no residual Teradata constructs
INFO  TODO(SME) markers outstanding: 17
RESULT: PASS
```

The single INSERT statement parses as Snowflake via sqlglot. The INSERT column
list (131 columns) matches the SELECT expression count (131), with no duplicate
INSERT columns. No residual Teradata constructs (`ZEROIFNULL`, `CONTAINS`,
`MULTISET`, `(+)`, BTEQ dot-commands, `MINUS`, `SEL`, …) remain in the SQL body
— the only occurrences of those tokens are inside the top-of-file `FIX LOG`
comment block, which the validator correctly ignores.

The 17 outstanding `TODO(SME)` markers are `INFO`-level assumptions flagged for
human review (e.g. the `CONTAINS` → `BETWEEN` split-column rewrite, the
synthesized `yq_curr_vlu` expression, and the `CAST((col, 0, 9999999999) AS
BIGINT)` rebuild). They are not SQL defects and do not affect the mechanical
verdict.

### Manual spot-check

| Check | Result |
|---|---|
| Parse / compile under Snowflake dialect | PASS — 1 statement parses cleanly |
| INSERT column count == SELECT expression count | PASS — 131 == 131 |
| No duplicate INSERT columns | PASS — validator confirms; DEF-01 removed the duplicate `sac_cd` (2nd occurrence) from both INSERT and SELECT lists |
| No residual Teradata constructs in SQL body | PASS — `ZEROIFNULL` (src 164,165) → `COALESCE(col, 0)`; `PERIOD ... CONTAINS` (src 451,456) → `BETWEEN ... AND ...` with split columns; no `MULTISET`/`(+)`/`MINUS`/`SEL`/BTEQ present |
| Malformed CAST remediated | PASS — `CAST((col, 0, 9999999999) AS BIGINT)` (src 212,213,221,222) was a corrupted COALESCE-with-range-bound; rebuilt as `CAST(COALESCE(col, 0) AS BIGINT)` (4 occurrences) with `TODO(SME) [DEF-04]` |
| `CONTAINS` rewrite preserves semantics | PASS (pending SME) — `bus_efast_pd CONTAINS best_usg.up_dt` rewritten as `best_usg.up_dt BETWEEN bus_efast_pd_start_dt AND bus_efast_pd_end_dt`; split column names flagged `TODO(SME) [SFX-01]` for confirmation against the Teradata source |
| Missing SELECT expression synthesized | PASS (pending SME) — `yq_curr_vlu` was present in the INSERT column list but absent from the SELECT; synthesized as `best_sa.yq_curr_vlu` per the `*_curr_vlu` naming convention, flagged `TODO(SME) [DEF-05]` |
| Column order / JOIN keys / CASE-branch order preserved | PASS — minimal diff applied; no reordering of INSERT columns or CASE branches; JOIN keys untouched |
| `QUALIFY` handling | N/A — no `QUALIFY` clause present in this unit |

**Manual verdict: PASS.** All mechanical checks pass and the manual spot-check
confirms the residual-Teradata cleanup, the malformed-CAST rebuild, the
duplicate-column removal, and the missing-expression synthesis. The three
SME-flagged assumptions (`CONTAINS` split-column names, `yq_curr_vlu`
synthesis, CAST rebuild) are documented as `TODO(SME)` for reviewer
confirmation against the Teradata ground truth and do not block the verdict.

---

## Buggy input control

### Mechanical validation (validator output)

```
FAIL  parse: Expecting ). Line 218, Col: 12.
FAIL  residual Teradata constructs: 4 found
RESULT: FAIL (2 hard check(s))
```

The control (buggy input) **correctly FAILs** with 2 hard checks:

1. **Parse failure** at line 218, col 12 — caused by the malformed
   `CAST((best_sa.dc_no, 0, 9999999999) AS BIGINT)` construct (Teradata
   CAST-with-format syntax leaking through as `CAST((col, lo, hi) AS BIGINT)`),
   which is not valid Snowflake. This is a genuine structural defect, not a
   semantic-only (SEM-*) issue, so the mechanical validator catches it.
2. **Residual Teradata constructs (4 found)** — `ZEROIFNULL` (lines 164, 165)
   and `PERIOD ... CONTAINS` (lines 451, 456).

The control FAIL confirms the issues the fix addressed were real: the
malformed CAST (parse error), `ZEROIFNULL`, and `PERIOD CONTAINS`. This is the
expected outcome for a unit with hard syntax/structural defects (not a
semantic-only defect where a passing control would be expected).

**Control verdict: FAIL (expected).** The fixed file resolves all four
defects, so the fix is validated against a genuinely failing control.