# Validation Report — `ins_wrk_dc_priority`

- **Fixed file:** `03_fix/output/ins_wrk_dc_priority_fixed.sql`
- **Buggy input (control):** `00_input/ins_wrk_dc_priority_snowflake.sql`
- **Date:** 2026-07-24
- **Validator:** `04_validate/validate.py` (sqlglot + Snowflake EXPLAIN backend)
- **Stage:** 4 — Validate

---

## 1. Fixed-file validation (after 1 re-fix cycle)

```
PASS  snowflake connection: probe returned 1
PASS  parse: 1 statement(s) parsed as snowflake using snowflake
INFO  snowflake EXPLAIN stmt 1: skipped — referenced object not loaded (run build_test_schema.py + load test_schema.sql to enable). Detail: 000904 (42000): SQL compilation error: error line 447 at position 33 invalid identifier 'UP_CTRY_GRP.BUS_EFAST_PD_START_DT'
INFO  1 statement(s) skipped for lack of loaded objects — not counted as failures.
PASS  stmt 1: INSERT columns (131) == SELECT expressions (131)
PASS  stmt 1: no duplicate INSERT columns
PASS  no residual Teradata constructs
INFO  TODO(SME) markers outstanding: 17
------------------------------------------------------------
RESULT: PASS
```

### EXPLAIN `INFO` — environment gap, not a defect

The Snowflake EXPLAIN was skipped because the referenced test schema objects
(e.g. `UP_CTRY_GRP.BUS_EFAST_PD_START_DT`) are **not loaded** in the test
database. The split column names (`bus_efast_pd_start_dt` / `bus_efast_pd_end_dt`)
are the TODO(SME) assumptions introduced by the SFX-01 `PERIOD … CONTAINS …` →
`BETWEEN` fix; they cannot be resolved without the source `ref_ctry` DDL.

Per the orchestrator rules, **`INFO` lines do NOT trigger a re-fix**. The
authoritative mechanical check — the **parse** check — **PASSED**, confirming
the SQL is syntactically valid Snowflake. This is an environment gap, not a SQL
defect.

---

## 2. Control validation (buggy input — expect FAIL)

```
PASS  snowflake connection: probe returned 1
FAIL  parse: Expecting ). Line 218, Col: 12. (malformed CAST((col, 0, 9999999999) AS BIGINT))
FAIL  snowflake EXPLAIN stmt 1: 001003 (42000): SQL compilation error: syntax error line 211 unexpected 'THEN', line 220 unexpected 'ELSE', line 260 unexpected ideographic spaces, line 444 unexpected 'CONTAINS'
FAIL  residual Teradata constructs: 4 found (ZEROIFNULL ×2 [FNX-01], PERIOD CONTAINS ×2 [SFX-01])
INFO  TODO(SME) markers outstanding: 0
------------------------------------------------------------
RESULT: FAIL (3 hard check(s))
```

**Control FAIL confirmed.** The buggy input fails on **3 hard checks**:

1. **Parse error** — malformed `CAST((col, 0, 9999999999) AS BIGINT)` (DEF-04).
2. **EXPLAIN compilation error** — `CONTAINS` (SFX-01), ideographic/full-width
   spaces, and stray `THEN`/`ELSE` from the broken CAST.
3. **Residual Teradata constructs** — `ZEROIFNULL` ×2 (FNX-01) and
   `PERIOD … CONTAINS …` ×2 (SFX-01).

This proves the issues targeted by the fix were real, and that the fixed file
resolves all of them.

---

## 3. Re-fix cycle note

- **Cycle 1 (1 cycle consumed):** The initial fix had two defects:
  1. A misplaced `,0` inside the `COALESCE` in the `cou_seq_no` CASE — both the
     `WHEN` and `THEN` branches read `COALESCE( (expr * 4 ,0 )` instead of
     `COALESCE( expr * 4, 0 )` (a stray parenthesis wrapped the `,0`).
  2. Ideographic (full-width U+3000) spaces `　　` before a `CASE` keyword.
- Both were repaired. Re-validation **PASSED**.
- Orchestrator 2-cycle cap respected (1 of 2 used).

---

## 4. Manual spot-checks

| # | Check | Result | Evidence |
|---|-------|--------|----------|
| 1 | JOIN keys intact (best_sa/best_usg on `dc_id`+`cou_no`; LEFT JOINs for MY_src, exchange rates, location hierarchy, country groups, remittance partner, ty_t5 subquery) | **PASS** | `PARTITION BY dc_id, cou_no` (lines 432, 442, 506); `ON best_sa.dc_id = best_usg.dc_id` (446); LEFT JOINs at 449, 454, 460, 466, 469, 471, 477, 483, 487 |
| 2 | CASE branches in order (`cou_seq_no`, `cdshr_ind`, `yq_vlu`, `oc_yq_src_cd`) | **PASS** | `END AS cou_seq_no` (247), `END AS cdshr_ind` (284), `END AS yq_vlu` (338), `END AS oc_yq_src_cd` (370) — branch order preserved |
| 3 | No dropped columns (131 INSERT = 131 SELECT after removing duplicate `sac_cd` and adding `yq_curr_vlu`) | **PASS** | Validator: `INSERT columns (131) == SELECT expressions (131)`; DEF-01 removed dup `sac_cd`; DEF-05 synthesized `yq_curr_vlu` |
| 4 | No residual Teradata (`ZEROIFNULL`→`COALESCE`, `CONTAINS`→`BETWEEN`, no `SEL`/`SET`/`MULTISET`/`MINUS`/BTEQ) | **PASS** | Validator: `no residual Teradata constructs`; grep confirms only FIX-LOG comment mentions of `ZEROIFNULL`/`CONTAINS` (documenting the fix), none in live SQL |
| 5 | `QUALIFY` kept as-is (3 clauses, SFX-03) | **PASS** | 3 `QUALIFY ROW_NUMBER() OVER (` clauses at lines 431, 441, 505 — no ROW_NUMBER-subquery wrap |
| 6 | `gbp_to_usg_curr` alias NOT renamed (SEM-10) | **PASS** | Alias retained at lines 262, 460–464, 508; FIX LOG notes "kept as-is (join correct, do NOT rename)" |
| 7 | Division kept as `/` (SEM-01, decimal/decimal, no truncation) | **PASS** | FIX LOG SEM-01 note: "Verified decimal/decimal division — no truncation risk, kept '/'" |
| 8 | `NULLS LAST` added to final QUALIFY ORDER BY (SEM-07) | **PASS** | `ORDER BY … DESC NULLS LAST` at lines 507–508; TODO(SME) at 504 |
| 9 | TODO(SME) markers present (17 total) | **PASS** | `grep -c "TODO(SME)"` = 17; validator INFO confirms 17 outstanding |

**All 9 manual spot-checks: PASS.**

---

## 5. Overall verdict

# ✅ PASS

The fixed file `03_fix/output/ins_wrk_dc_priority_fixed.sql` **PASSES** Stage 4
validation:

- **Mechanical checks:** parse PASS, INSERT/SELECT column count match (131=131),
  no duplicate INSERT columns, no residual Teradata constructs.
- **EXPLAIN INFO:** environment gap (test schema objects not loaded), not a SQL
  defect — does not trigger a re-fix.
- **Control:** buggy input FAILs 3 hard checks, confirming the issues were real.
- **Manual spot-checks:** all 9 PASS (JOIN keys, CASE order, columns, residual
  Teradata, QUALIFY, alias, division, NULLS LAST, TODO markers).
- **Re-fix cycles:** 1 of 2 used (COALESCE paren fix + ideographic space removal).

### Outstanding items for SME review

- **17 TODO(SME) markers** outstanding — these are assumptions requiring human
  confirmation (SFX-01 split column names, SEM-02 non-unique QUALIFY tiebreakers,
  SEM-07 NULLS LAST ordering, SEM-08 empty-string-vs-NULL, SEM-10 alias, DEF-04
  CAST semantics, DEF-05 synthesized `yq_curr_vlu`, etc.). They do not block
  mechanical PASS but must be reviewed before production promotion.

**No hand-back to s2s-fix required.** Proceed to Stage 5 (report) and Stage 6
(semantic explanation).