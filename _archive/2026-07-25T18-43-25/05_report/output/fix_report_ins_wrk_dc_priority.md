# Fix Report — `ins_wrk_dc_priority`

**Unit:** `00_input/ins_wrk_dc_priority_snowflake.sql`
**Fixed file:** `03_fix/output/ins_wrk_dc_priority_fixed.sql`
**Stage 1 analysis:** `01_analyze/output/analysis_ins_wrk_dc_priority.md`
**Stage 4 validation:** `04_validate/output/validation_ins_wrk_dc_priority.md`
**Stage 6 semantic doc:** `06_explain/output/semantic_ins_wrk_dc_priority.md`
**Teradata ground truth:** None (no `ins_wrk_dc_priority_snowflake.teradata.sql` in `00_input/`). All inferences flagged `TODO(SME)`.
**Date:** 2026-07-24
**Run type:** Re-run (confirms and supersedes the 2026-07-23 entry in `06_lessons_learned.md`)

---

## 1. Summary

The delivered "already-converted" Snowflake script was a thin find/replace over
Teradata BTEQ that did not parse: it retained `ZEROIFNULL` (×2), `PERIOD …
CONTAINS …` (×2), malformed `CAST((col, 0, 9999999999) AS BIGINT)` calls (×4),
three `ASallow_*` whitespace typos, a duplicate `sac_cd` on both INSERT and
SELECT sides, and a missing `yq_curr_vlu` SELECT expression that left INSERT
(131) ≠ SELECT (130). Stage 3 applied 20 mechanical fixes across six rule
families (FNX-01, SFX-01, FNX-03, DEF-01/02/04/05/06) plus the SEM-07
`NULLS LAST` hardening on the final QUALIFY, normalized seven aliases for
readability (DEF-06), and left four semantic risks as `TODO(SME)` (SEM-02,
SEM-07, SEM-08, SEM-10). One re-fix cycle was consumed to repair a misplaced
`,0` inside a `COALESCE` in the `cou_seq_no` CASE and to strip ideographic
(U+3000) full-width spaces before a `CASE` keyword. Stage 4 validation
**PASSED**: 131 = 131 INSERT/SELECT columns, no duplicates, no residual
Teradata constructs, parse clean; the buggy control input **FAILED** 3 hard
checks (parse, EXPLAIN, 4 residual Teradata constructs). 17 `TODO(SME)`
markers remain outstanding for human sign-off.

---

## 2. Rules applied

### 2.1 Syntax / Function (6 applications)

| Rule | Count | Source lines | Change |
|---|---|---|---|
| **FNX-01** | 2 | 164, 165 | `ZEROIFNULL(best_usg.grs_rev_vlu)` / `ZEROIFNULL(best_usg.grs_rev_curr_vlu)` → `COALESCE(…, 0)`. Identical semantics. |
| **SFX-01** | 2 | 451, 456 | `up_ctry_grp.bus_efast_pd CONTAINS best_usg.up_dt` / `disch_ctry_grp.bus_efast_pd CONTAINS best_usg.up_dt` → `best_usg.up_dt BETWEEN <alias>.bus_efast_pd_start_dt AND <alias>.bus_efast_pd_end_dt` on split columns. `TODO(SME)` on the split column names. |
| **FNX-03** | 2 | 304, 335 | `LAST_DAY(dtrp.remittance_received_to_dt) - 3` → `DATEADD('day', -3, LAST_DAY(dtrp.remittance_received_to_dt))` (2nd occurrence inside the `oc_yq_src_cd` CASE). Identical date arithmetic, explicit form. |
| **SFX-03** | 3 (kept) | 409–413, 418–422, 478–483 | All three `QUALIFY ROW_NUMBER() OVER (…) = 1` clauses retained verbatim — Snowflake supports `QUALIFY`; no ROW_NUMBER-subquery wrap. |

### 2.2 Defects (16 applications)

| Rule | Count | Source lines | Change |
|---|---|---|---|
| **DEF-01** | 1 | 80–81 (INSERT), 228–229 (SELECT) | Removed the duplicate `sac_cd` from both the INSERT column list and the SELECT expression list (positional offset 70–71 on both sides). |
| **DEF-02** | 3 | 177, 178, 179 | `ASallow_piece_qty` / `ASallow_weight_qty` / `ASallow_weight_unit_cd` → `AS allow_piece_qty` / `AS allow_weight_qty` / `AS allow_weight_unit_cd` (inserted the missing whitespace between `AS` and the alias). |
| **DEF-04** | 4 | 212, 213, 221, 222 | `CAST((best_sa.dc_no, 0, 9999999999) AS BIGINT)` and `CAST((best_sa.pme_dc_no, 0, 9999999999) AS BIGINT)` (2 columns × 2 CASE branches) → `CAST(COALESCE(best_sa.dc_no, 0) AS BIGINT)` / `CAST(COALESCE(best_sa.pme_dc_no, 0) AS BIGINT)`. The `9999999999` constant is treated as a leftover range bound and dropped. `TODO(SME)` on the constant. |
| **DEF-05** | 1 | INSERT pos 84 / SELECT pos 84 | Synthesized the missing `yq_curr_vlu` SELECT expression as `best_sa.yq_curr_vlu`, per the `*_vlu` (GBP) / `*_curr_vlu` (original-currency) naming convention. `TODO(SME)` — confirm against the Teradata source. |
| **DEF-06** | 7 | 2, 9, 12, 13, 32, 43, 81 | Normalized seven aliases to the INSERT target column names for readability (`sa_src_cd`→`sale_src_cd`, `cou_no`→`cpn_no`, `opr_myflight_no`→`opr_flt_no`, `opr_myflight_sfx_cd`→`opr_flt_sfx_cd`, `alliance_cd`→`cd`, `ex_to_sa_dt`→`ex_to_sale_dt`, `e_rmk_email_addr_txt`→`emd_rmk_email_addr_txt`). Cosmetic — INSERT…SELECT is positional. |

### 2.3 Semantic (1 correction + 3 TODO(SME) + 2 notes)

| Rule | Status | Source lines | Change |
|---|---|---|---|
| **SEM-07** | **Corrected** | 478–483 | Made `NULLS LAST` explicit on both keys of the final QUALIFY `ORDER BY sa_curr_to_gbp.efast_dt DESC NULLS LAST, gbp_to_usg_curr.efast_dt DESC NULLS LAST`, so rows with no matching exchange rate (NULL `efast_dt` from the LEFT JOINs) do not win the `ROW_NUMBER() = 1` pick under Snowflake's default `NULLS FIRST` for `DESC`. `TODO(SME)` to confirm this matches the Teradata NULL-ordering assumption. |
| **SEM-02** | TODO(SME) | 409–413, 418–422, 478–483 | Three `QUALIFY … = 1` clauses have non-unique `ORDER BY` keys (`sa_priority_no`, `usg_priority_no`, `efast_dt`); ties are non-deterministic. `TODO(SME)` before each QUALIFY — confirm uniqueness or add a deterministic tiebreaker. |
| **SEM-08** | TODO(SME) | 252–258, 299–321 | `oc_yq_src_cd` CASE returns `''` (empty string) in several branches; `NULLIF(x, '')` is used in `cdshr_ind`. `TODO(SME)` — confirm empty-string-vs-NULL intent against Teradata. |
| **SEM-10** | **NOT fixed (intentional)** | 437–441 | `gbp_to_usg_curr` alias is misleading (it joins **to** GBP, same direction as `sa_curr_to_gbp`) but the join is correct against the Teradata source. Alias kept as-is; renaming would hide, not solve. |
| **SEM-01** | Note only | 244, 276, 284, 292, 304, 310, 316 | `yq_curr_vlu / sa_curr_to_gbp.ex_rte` is decimal/decimal — no integer-truncation risk. Kept `/`. |
| **SEM-06** | Resolved via DEF-04 | 212–222 | Implicit-cast risk in the malformed `CAST((col,0,999…) AS BIGINT)` resolved by the explicit `CAST(COALESCE(col, 0) AS BIGINT)` rebuild. |

---

## 3. Defects repaired

| # | Rule | Location | Defect | Repair |
|---|---|---|---|---|
| 1 | FNX-01 | src 164 | `ZEROIFNULL(best_usg.grs_rev_vlu)` | `COALESCE(best_usg.grs_rev_vlu, 0)` |
| 2 | FNX-01 | src 165 | `ZEROIFNULL(best_usg.grs_rev_curr_vlu)` | `COALESCE(best_usg.grs_rev_curr_vlu, 0)` |
| 3 | SFX-01 | src 451 | `up_ctry_grp.bus_efast_pd CONTAINS best_usg.up_dt` | `best_usg.up_dt BETWEEN up_ctry_grp.bus_efast_pd_start_dt AND up_ctry_grp.bus_efast_pd_end_dt` (+ `TODO(SME)`) |
| 4 | SFX-01 | src 456 | `disch_ctry_grp.bus_efast_pd CONTAINS best_usg.up_dt` | `best_usg.up_dt BETWEEN disch_ctry_grp.bus_efast_pd_start_dt AND disch_ctry_grp.bus_efast_pd_end_dt` (+ `TODO(SME)`) |
| 5 | FNX-03 | src 304 | `LAST_DAY(dtrp.remittance_received_to_dt) - 3` | `DATEADD('day', -3, LAST_DAY(dtrp.remittance_received_to_dt))` |
| 6 | FNX-03 | src 335 | `LAST_DAY(dtrp.remittance_received_to_dt) - 3` (2nd occurrence, `oc_yq_src_cd` CASE) | `DATEADD('day', -3, LAST_DAY(dtrp.remittance_received_to_dt))` |
| 7 | DEF-01 | src 80–81, 228–229 | Duplicate `sac_cd` in INSERT and SELECT lists | Removed the second occurrence from both sides |
| 8 | DEF-02 | src 177 | `ASallow_piece_qty` | `AS allow_piece_qty` |
| 9 | DEF-02 | src 178 | `ASallow_weight_qty` | `AS allow_weight_qty` |
| 10 | DEF-02 | src 179 | `ASallow_weight_unit_cd` | `AS allow_weight_unit_cd` |
| 11 | DEF-04 | src 212, 221 | `CAST((best_sa.dc_no, 0, 9999999999) AS BIGINT)` (×2 CASE branches) | `CAST(COALESCE(best_sa.dc_no, 0) AS BIGINT)` (+ `TODO(SME)` on `9999999999`) |
| 12 | DEF-04 | src 213, 222 | `CAST((best_sa.pme_dc_no, 0, 9999999999) AS BIGINT)` (×2 CASE branches) | `CAST(COALESCE(best_sa.pme_dc_no, 0) AS BIGINT)` (+ `TODO(SME)` on `9999999999`) |
| 13 | DEF-05 | INSERT pos 84 / SELECT pos 84 | Missing `yq_curr_vlu` SELECT expression (INSERT 131 ≠ SELECT 130 after DEF-01) | Synthesized `best_sa.yq_curr_vlu AS yq_curr_vlu` (+ `TODO(SME)`) |
| 14 | DEF-06 | src 2 | `sa_src_cd` alias ≠ target `sale_src_cd` | Normalized to `sale_src_cd` |
| 15 | DEF-06 | src 9 | `cou_no` alias ≠ target `cpn_no` | Normalized to `cpn_no` |
| 16 | DEF-06 | src 12 | `opr_myflight_no` alias ≠ target `opr_flt_no` | Normalized to `opr_flt_no` |
| 17 | DEF-06 | src 13 | `opr_myflight_sfx_cd` alias ≠ target `opr_flt_sfx_cd` | Normalized to `opr_flt_sfx_cd` |
| 18 | DEF-06 | src 32 | `alliance_cd` alias ≠ target `cd` | Normalized to `cd` |
| 19 | DEF-06 | src 43 | `ex_to_sa_dt` alias ≠ target `ex_to_sale_dt` | Normalized to `ex_to_sale_dt` |
| 20 | DEF-06 | src 81 | `e_rmk_email_addr_txt` alias ≠ target `emd_rmk_email_addr_txt` | Normalized to `emd_rmk_email_addr_txt` |
| 21 | SEM-07 | src 478–483 | Final QUALIFY `ORDER BY … DESC` with NULLable LEFT-JOIN `efast_dt` keys (Snowflake defaults to `NULLS FIRST` for `DESC`) | Added explicit `NULLS LAST` on both keys (+ `TODO(SME)`) |

**Re-fix cycle 1 repairs (not rule-backed — mechanical defects in the first fix attempt):**

| # | Location | Defect | Repair |
|---|---|---|---|
| R1 | `cou_seq_no` CASE (WHEN/THEN branches) | Misplaced `,0` inside `COALESCE` — read `COALESCE( (expr * 4 ,0 )` instead of `COALESCE( expr * 4, 0 )` (a stray parenthesis wrapped the `,0`) | Rebuilt as `COALESCE(expr * 4, 0)` — `,0` is a COALESCE argument, not inside the inner parens |
| R2 | Before a `CASE` keyword | Ideographic / full-width spaces (U+3000) `　　` surviving from the Teradata BTEQ find/replace broke Snowflake parsing | Stripped the non-ASCII whitespace |

---

## 4. Open TODO(SME) items

17 `TODO(SME)` markers are outstanding in the fixed file. They do not block the
mechanical PASS but **must be reviewed before production promotion**.

| # | Rule | Topic | Question for the SME |
|---|---|---|---|
| 1 | SFX-01 | Split column names (×2) | Confirm `bus_efast_pd_start_dt` / `bus_efast_pd_end_dt` are the correct split column names on `ref_ctry` for the `PERIOD CONTAINS` → `BETWEEN` rewrite (up_ctry_grp and disch_ctry_grp). |
| 2 | DEF-04 | `9999999999` constant (×4) | Confirm the `9999999999` constant in the original `CAST((col, 0, 9999999999) AS BIGINT)` was a range bound / conversion artifact, not semantically meaningful. |
| 3 | DEF-05 | Synthesized `yq_curr_vlu` | Confirm `best_sa.yq_curr_vlu` is the correct expression for the missing INSERT position 84 (original-currency YQ value from the SA row), per the `*_curr_vlu` convention. |
| 4 | SEM-02 | QUALIFY tie-breaking (×3) | Confirm `sa_priority_no`, `usg_priority_no`, and `efast_dt` are unique per `(dc_id, cou_no)` partition in all three QUALIFY clauses; if not, add a deterministic tiebreaker. |
| 5 | SEM-07 | NULL ordering | Confirm `NULLS LAST` on the final QUALIFY matches the Teradata NULL-ordering assumption (rows with no matching exchange rate should not win the `ROW_NUMBER() = 1` pick). |
| 6 | SEM-08 | Empty string vs NULL | Confirm the `oc_yq_src_cd` branches that return `''` (empty string) are intended vs NULL in Teradata. |
| 7 | SEM-10 | `gbp_to_usg_curr` alias | Confirm the misleading alias is acceptable to keep (join is correct; renaming is out of scope). |

---

## 5. Validation result

**Stage 4 verdict: ✅ PASS** (after 1 re-fix cycle; orchestrator 2-cycle cap respected).

### 5.1 Fixed-file validation

```
PASS  snowflake connection: probe returned 1
PASS  parse: 1 statement(s) parsed as snowflake using snowflake
INFO  snowflake EXPLAIN stmt 1: skipped — referenced object not loaded
      (UP_CTRY_GRP.BUS_EFAST_PD_START_DT). Environment gap, not a SQL defect.
PASS  stmt 1: INSERT columns (131) == SELECT expressions (131)
PASS  stmt 1: no duplicate INSERT columns
PASS  no residual Teradata constructs
INFO  TODO(SME) markers outstanding: 17
RESULT: PASS
```

The EXPLAIN `INFO` is an environment gap (the test schema does not load the
SFX-01 split column names, which are themselves `TODO(SME)` assumptions). Per
orchestrator rules, `INFO` lines do not trigger a re-fix. The authoritative
mechanical check — **parse** — PASSED.

### 5.2 Control validation (buggy input — expected FAIL)

```
PASS  snowflake connection: probe returned 1
FAIL  parse: Expecting ). Line 218, Col: 12. (malformed CAST((col, 0, 9999999999) AS BIGINT))
FAIL  snowflake EXPLAIN stmt 1: 001003 (42000): SQL compilation error:
      syntax error line 211 unexpected 'THEN', line 220 unexpected 'ELSE',
      line 260 unexpected ideographic spaces, line 444 unexpected 'CONTAINS'
FAIL  residual Teradata constructs: 4 found (ZEROIFNULL ×2 [FNX-01], PERIOD CONTAINS ×2 [SFX-01])
RESULT: FAIL (3 hard check(s))
```

**Control FAIL confirmed** — the buggy input fails 3 hard checks:

1. **Parse error** — malformed `CAST((col, 0, 9999999999) AS BIGINT)` (DEF-04).
2. **EXPLAIN compilation error** — `CONTAINS` (SFX-01), ideographic/full-width spaces (U+3000), and stray `THEN`/`ELSE` from the broken CAST.
3. **Residual Teradata constructs** — `ZEROIFNULL` ×2 (FNX-01) and `PERIOD … CONTAINS …` ×2 (SFX-01).

This proves the issues targeted by the fix were real and that the fixed file
resolves all of them.

### 5.3 Re-fix cycle note

- **Cycle 1 (1 of 2 used):** Two defects in the initial fix:
  1. A misplaced `,0` inside `COALESCE` in the `cou_seq_no` CASE — both the
     `WHEN` and `THEN` branches read `COALESCE( (expr * 4 ,0 )` instead of
     `COALESCE( expr * 4, 0 )` (a stray parenthesis wrapped the `,0`).
  2. Ideographic (full-width U+3000) spaces `　　` before a `CASE` keyword,
     surviving from the Teradata BTEQ find/replace.
- Both repaired; re-validation PASSED.

### 5.4 Manual spot-checks (9/9 PASS)

| # | Check | Result |
|---|-------|--------|
| 1 | JOIN keys intact (`best_sa`/`best_usg` on `dc_id`+`cou_no`; LEFT JOINs for `MY_src`, exchange rates, location hierarchy, country groups, remittance partner, `ty_t5` subquery) | PASS |
| 2 | CASE branch order preserved (`cou_seq_no`, `cdshr_ind`, `yq_vlu`, `oc_yq_src_cd`) | PASS |
| 3 | No dropped columns (131 INSERT = 131 SELECT after DEF-01 + DEF-05) | PASS |
| 4 | No residual Teradata (`ZEROIFNULL`→`COALESCE`, `CONTAINS`→`BETWEEN`, no `SEL`/`SET`/`MULTISET`/`MINUS`/BTEQ) | PASS |
| 5 | `QUALIFY` kept as-is (3 clauses, SFX-03) — no ROW_NUMBER-subquery wrap | PASS |
| 6 | `gbp_to_usg_curr` alias NOT renamed (SEM-10) | PASS |
| 7 | Division kept as `/` (SEM-01, decimal/decimal, no truncation) | PASS |
| 8 | `NULLS LAST` added to final QUALIFY ORDER BY (SEM-07) | PASS |
| 9 | 17 `TODO(SME)` markers present | PASS |

---

## 6. Sign-off checklist

A reviewer can sign off from this document alone. Confirm each item:

- [x] **Parse PASS** — fixed SQL parses as Snowflake (1 statement).
- [x] **Column count match** — 131 INSERT = 131 SELECT after DEF-01 (duplicate `sac_cd` removed) and DEF-05 (`yq_curr_vlu` synthesized).
- [x] **No duplicate INSERT columns.**
- [x] **No residual Teradata constructs** — `ZEROIFNULL`, `CONTAINS`, `MULTISET`, `(+)`, BTEQ, `MINUS`, `SEL` all absent.
- [x] **`QUALIFY` retained** (SFX-03) — 3 clauses, no ROW_NUMBER-subquery wrap.
- [x] **JOIN keys and CASE-branch order preserved** (spot-checks 1–2).
- [x] **Control FAIL** — buggy input fails 3 hard checks, confirming the issues were real.
- [x] **Re-fix cycle within cap** — 1 of 2 cycles used.
- [x] **Semantic doc exists** — `06_explain/output/semantic_ins_wrk_dc_priority.md` (referenced, not duplicated here).
- [ ] **SME review of 17 `TODO(SME)` markers** — required before production promotion (see §4).
- [ ] **SFX-01 split column names** confirmed against `ref_ctry` DDL.
- [ ] **DEF-05 `yq_curr_vlu` synthesis** confirmed against Teradata source or SME.
- [ ] **SEM-02 QUALIFY tie-breakers** confirmed unique or augmented.
- [ ] **SEM-07 `NULLS LAST`** confirmed to match Teradata NULL ordering.
- [ ] **SEM-08 empty-string-vs-NULL** intent confirmed for `oc_yq_src_cd`.
- [ ] **DEF-04 `9999999999` constant** confirmed to be a non-semantic range bound.

**Mechanical sign-off: READY.** Semantic sign-off: **pending SME review** of the
17 `TODO(SME)` markers above.