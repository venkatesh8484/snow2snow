# Stage 4 — Validation: `ins_wrk_dc_priority`

**Unit:** `ins_wrk_dc_priority`
**Fixed SQL:** `03_fix/output/ins_wrk_dc_priority_fixed.sql`
**Buggy input:** `00_input/ins_wrk_dc_priority_snowflake.sql`
**Validator:** `04_validate/validate.py` (sqlglot Snowflake parse + Snowflake EXPLAIN + residual-Teradata regex scan + INSERT/SELECT alignment)
**Date:** 2026-07-24

---

## Final SQL

**Result: FAIL (3 hard checks)**

Validator command:
```
python3 04_validate/validate.py 03_fix/output/ins_wrk_dc_priority_fixed.sql
```

Raw output:
```
PASS  snowflake connection: probe returned 1
FAIL  parse: Expecting ). Line 235, Col: 12.
           ) * 4
                ,0
            ) + best_sa.cou_no
        ) BETWEEN 1 AND 16
        THEN (
            COALESCE(
                (
                    (CAST(COALESCE(best_sa.dc_no, 0) AS B
FAIL  snowflake EXPLAIN stmt 1: 001003 (42000): SQL compilation error:
syntax error line 210 at position 8 unexpected 'THEN'.
syntax error line 220 at position 8 unexpected 'ELSE'.
syntax error line 258 at position 0 unexpected '  '.
parse error line 531 at position 13 near '<EOF>'.
FAIL  residual Teradata constructs: 2 found
        line 525: PERIOD CONTAINS (Teradata) -> BETWEEN   [SFX-01]
        line 530: PERIOD CONTAINS (Teradata) -> BETWEEN   [SFX-01]
INFO  TODO(SME) markers outstanding: 14
------------------------------------------------------------
RESULT: FAIL (3 hard check(s))
```

### Hard-check detail

| # | Check | Result | Detail |
|---|---|---|---|
| 1 | Snowflake connection probe | PASS | probe returned 1 |
| 2 | sqlglot parse (Snowflake dialect) | **FAIL** | `Expecting ). Line 235, Col: 12` — unbalanced parenthesis in the `cou_seq_no` CASE expression |
| 3 | Snowflake EXPLAIN (live compile) | **FAIL** | `syntax error line 210 unexpected 'THEN'`, `line 219 unexpected 'ELSE'`, `line 258 unexpected '  '`, `parse error line 531 near '<EOF>'` |
| 4 | INSERT/SELECT column alignment | **SKIPPED** | parse failed → no `exp.Insert` recovered → alignment check did not run |
| 5 | Duplicate INSERT columns | **SKIPPED** | parse failed |
| 6 | Residual Teradata constructs | **FAIL** | 2 hits (see note below) |
| 7 | TODO(SME) count (informational) | INFO | 14 outstanding |

### Parse-error root cause (lines 224–245)

The `cou_seq_no` CASE was rewritten under DEF-04 to convert
`CAST((best_sa.dc_no, 0, 9999999999) AS BIGINT)` →
`CAST(COALESCE(best_sa.dc_no, 0) AS BIGINT)`. The rewrite dropped a closing
parenthesis that existed in the buggy original, leaving an unbalanced `(`:

Fixed (broken) — lines 230–238:
```sql
        COALESCE(
            (
                (CAST(COALESCE(best_sa.dc_no, 0) AS BIGINT)
                 - CAST(COALESCE(best_sa.pme_dc_no, 0) AS BIGINT)
                ) * 4
            ,0
        ) + best_sa.cou_no
```

The inner `(` opened on the line after `COALESCE(` is never closed before
`,0`. The original buggy form had the same skeleton but with the Teradata
`CAST((col, 0, 9999999999) AS BIGINT)` triple-arg cast; both fail to parse, so
this is a **regression introduced by the DEF-04 rewrite** — the fix did not
repair the pre-existing parenthesization defect, it merely changed the inner
expression while preserving the unbalanced `(`.

The same defect is duplicated in the `THEN (...)` branch (lines 239–244).

### Residual-Teradata false-positive note

Both `CONTAINS` hits (lines 525, 530) are **inside `/* ... */` block comments**
that document the SFX-01 remediation (`was \`bus_efast_pd CONTAINS best_usg.up_dt\``).
The actual SQL code on those lines uses the corrected `BETWEEN ... AND ...`
form. A comment-stripped re-scan confirms **zero residual Teradata constructs in
the executable code**:

```
ZEROIFNULL: 0 hits in CODE (clean)
CONTAINS:   0 hits in CODE (clean)
MULTISET:   0 hits in CODE (clean)
MINUS:      0 hits in CODE (clean)
SEL:        0 hits in CODE (clean)
(+):        0 hits in CODE (clean)
```

The validator's `scan_residual()` skips lines that *start* with `--` or `/*`
but does not strip **inline** block comments, so the comment text is flagged.
This is a known validator limitation, **not** a real residual construct. Per
policy the validator was **not** edited to suppress this.

---

## Buggy input control

**Result: FAIL (3 hard checks)** — control behaves correctly (buggy input must fail).

Validator command:
```
python3 04_validate/validate.py 00_input/ins_wrk_dc_priority_snowflake.sql
```

Raw output:
```
PASS  snowflake connection: probe returned 1
FAIL  parse: Expecting ). Line 218, Col: 12.
           ) * 4
                ,0
            ) + best_sa.cou_no
        ) BETWEEN 1 AND 16
        THEN (
            COALESCE(
                (
                    (CAST((best_sa.dc_no, 0, 9999999999) 
FAIL  snowflake EXPLAIN stmt 1: 001003 (42000): SQL compilation error:
syntax error line 211 at position 8 unexpected 'THEN'.
syntax error line 220 at position 8 unexpected 'ELSE'.
syntax error line 260 at position 0 unexpected '  '.
syntax error line 444 at position 35 unexpected 'CONTAINS'.
FAIL  residual Teradata constructs: 4 found
        line 164: ZEROIFNULL (Teradata) -> COALESCE(x,0)  [FNX-01]
        line 165: ZEROIFNULL (Teradata) -> COALESCE(x,0)  [FNX-01]
        line 451: PERIOD CONTAINS (Teradata) -> BETWEEN   [SFX-01]
        line 456: PERIOD CONTAINS (Teradata) -> BETWEEN   [SFX-01]
INFO  TODO(SME) markers outstanding: 0
------------------------------------------------------------
RESULT: FAIL (3 hard check(s))
```

| # | Check | Result | Detail |
|---|---|---|---|
| 1 | Snowflake connection probe | PASS | probe returned 1 |
| 2 | sqlglot parse | **FAIL** | `Expecting ). Line 218` — same unbalanced `(` in `cou_seq_no` CASE |
| 3 | Snowflake EXPLAIN | **FAIL** | `unexpected 'THEN'`, `unexpected 'ELSE'`, `unexpected 'CONTAINS'` (line 444 — real `CONTAINS` in code) |
| 4 | Residual Teradata constructs | **FAIL** | 4 real hits: `ZEROIFNULL` ×2 (lines 164–165), `CONTAINS` ×2 (lines 451, 456 — in executable code) |

The control confirms the original issues were real: `ZEROIFNULL` and
`PERIOD … CONTAINS` were present in executable code, and the `cou_seq_no` CASE
had an unbalanced parenthesis. The fixed file resolved `ZEROIFNULL` (→
`COALESCE`) and `CONTAINS` (→ `BETWEEN`) in code, but **failed to repair the
parenthesis imbalance** in the `cou_seq_no` CASE.

---

## Manual spot-check

| Check | Method | Result | Detail |
|---|---|---|---|
| JOIN keys preserved | diff JOIN/ON clauses fixed vs buggy | **PASS** | All 9 JOIN ON keys identical (best_sa.dc_id=best_usg.dc_id; best_sa.dc_id=MY_src.dc_id; sa_curr_to_gbp; gbp_to_usg_curr; dep_loc_hierarchy; arr_loc_hierarchy; up_ctry_grp; disch_ctry_grp; dtrp). Join types and order unchanged. |
| CASE-branch order preserved | compare WHEN/THEN/ELSE/END sequence | **PASS** | `cou_seq_no` (WHEN/THEN/ELSE NULL/END), `cdshr_comm_curr_vlu`, `cdshr_ind`, `yq_vlu` (8 WHEN branches in same order), `oc_yq_src_cd` (5 WHEN branches in same order), `MY_acg_usg_cd` all match. Fixed adds a synthesized `yq_curr_vlu` CASE (DEF-05) mirroring `yq_vlu` branches — flagged TODO(SME). |
| No dropped columns | INSERT column count fixed vs buggy | **PASS** | Fixed: 132 INSERT columns, 0 duplicates. Buggy: 132 INSERT columns, 1 duplicate (`sac_cd`). DEF-01 duplicate removal confirmed. |
| No residual Teradata in code | comment-stripped regex scan | **PASS** | ZEROIFNULL, CONTAINS, MULTISET, MINUS, SEL, (+) all 0 hits in executable code. (Validator flags 2 `CONTAINS` in inline comments — false positives, see note above.) |
| QUALIFY preserved | grep `QUALIFY` | **PASS** | `QUALIFY ROW_NUMBER() OVER (...) = 1` retained as-is (SFX-03) at lines 409, 418, 478. Not wrapped in subquery. |
| TODO(SME) markers | count | INFO | 14 outstanding — all semantic/defect assumptions flagged for SME review (DEF-04 constant drop, DEF-05 synthesized yq_curr_vlu, SEM-05 SET-table, SFX-01 split column names, etc.) |

---

## Summary

| File | Parse | EXPLAIN | Residual TD (code) | INSERT/SELECT align | Overall |
|---|---|---|---|---|---|
| Fixed `ins_wrk_dc_priority_fixed.sql` | **FAIL** | **FAIL** | PASS (2 false-positive comment hits) | SKIPPED (parse fail) | **FAIL** |
| Buggy `ins_wrk_dc_priority_snowflake.sql` (control) | **FAIL** | **FAIL** | **FAIL** (4 real hits) | SKIPPED (parse fail) | **FAIL** (expected) |

## Verdict

**The fixed SQL FAILS validation.** The remediation correctly resolved the
`ZEROIFNULL` (FNX-01) and `PERIOD … CONTAINS` (SFX-01) constructs and removed the
duplicate `sac_cd` INSERT column (DEF-01), and JOIN keys / CASE-branch order /
column counts are preserved. **However**, the DEF-04 rewrite of
`CAST((col, 0, 9999999999) AS BIGINT)` → `CAST(COALESCE(col, 0) AS BIGINT)`
introduced (or rather, failed to repair) an **unbalanced parenthesis** in the
`cou_seq_no` CASE expression (lines 230–238 and 239–244), so the file does not
parse and will not compile on Snowflake.

**Action required:** return to **s2s-fix** (Stage 3) to repair the parenthesis
imbalance in the `cou_seq_no` CASE. The inner `(` opened after `COALESCE(` must
be closed before `,0`. The corrected skeleton should be:

```sql
        COALESCE(
            (
                (CAST(COALESCE(best_sa.dc_no, 0) AS BIGINT)
                 - CAST(COALESCE(best_sa.pme_dc_no, 0) AS BIGINT)
                ) * 4
            ),
            0
        ) + best_sa.cou_no
```

(apply to both the `WHEN` and `THEN` branches), then re-run this validator.

The validator was **not** edited to make the file pass. The 2 `CONTAINS`
"residual" hits are false positives from inline block comments and do not
reflect executable code; they can be addressed in a future validator refinement
(comment stripping) but are out of scope for this stage.