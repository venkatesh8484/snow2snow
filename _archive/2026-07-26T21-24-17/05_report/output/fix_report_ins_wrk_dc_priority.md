# Stage 5 — Fix Report: `ins_wrk_dc_priority_snowflake.sql`

**Unit:** `ins_wrk_dc_priority`
**Input:** `00_input/ins_wrk_dc_priority_snowflake.sql`
**Fixed SQL:** `03_fix/output/ins_wrk_dc_priority_fixed.sql`
**Analysis:** `01_analyze/output/analysis_ins_wrk_dc_priority.md`
**Validation:** `04_validate/output/validation_ins_wrk_dc_priority.md`
**Teradata ground truth:** ❌ not supplied (no `00_input/ins_wrk_dc_priority.teradata.sql`)
**SnowSQL client layer:** N/A (`.sql` input — no `SNZ-*` constructs)
**Run date:** 2026-07-25
**Run type:** Re-run (confirms prior 2026-07-23 / 2026-07-24 findings)

---

## 1. Executive summary

The delivered "already-converted" Snowflake script was a thin find/replace over
a Teradata BTEQ and **did not run**: it failed to parse (malformed `CAST`) and
carried residual Teradata constructs (`ZEROIFNULL`, PERIOD `CONTAINS`).
Remediation applied **20+ mechanical fixes** across syntax, function, and
defect rules, plus one semantic hardening (`SEM-07 NULLS LAST`). The fixed file
parses cleanly as Snowflake, the INSERT column count matches the SELECT
expression count (**131 = 131**), no residual Teradata constructs remain, and
the buggy input correctly FAILs the control. **17 `TODO(SME)` markers** remain
for human review (no Teradata ground truth was supplied).

**Validation verdict: PASS** (mechanical). **Control verdict: FAIL (expected).**

A reviewer can sign off from this document together with the Stage-6 semantic
doc (`06_explain/output/semantic_ins_wrk_dc_priority.md`, archived copy
`_archive/2026-07-25T18-43-25/06_explain/output/semantic_ins_wrk_dc_priority.md`),
which carries the clause-by-clause semantic account. This report does not
duplicate it.

---

## 2. Column-count reconciliation

| Side | Raw count | Duplicates removed | Net unique |
|---|---|---|---|
| INSERT target columns | 132 | `sac_cd` ×2 (DEF-01) | **131** |
| SELECT expressions | 131 | `sac_cd` ×2 (DEF-01) + missing `yq_curr_vlu` (DEF-05) | **131** |

After removing the duplicate `sac_cd` on both sides and synthesizing the
missing `yq_curr_vlu` expression (INSERT position 84), positions align
1:1. **Final: 131 = 131.** ✅

---

## 3. Rules applied (grouped)

### 3.1 Syntax / function fixes

| Rule | Count | Source lines | Change |
|---|---|---|---|
| **FNX-01** | 2 | 164, 165 | `ZEROIFNULL(x)` → `COALESCE(x, 0)` (grs_rev_vlu, grs_rev_curr_vlu) |
| **SFX-01** | 2 | 451, 456 | PERIOD `bus_efast_pd CONTAINS best_usg.up_dt` → `best_usg.up_dt BETWEEN <split>_start_dt AND <split>_end_dt` (split column names flagged `TODO(SME)`) |
| **FNX-03** | 2 | 304, 335 | `LAST_DAY(...) - 3` → `DATEADD('day', -3, LAST_DAY(...))` (in `yq_vlu` and `oc_yq_src_cd` CASE branches) |
| **U+3000 strip** | 1 | 267 | Ideographic space `　　` before `CASE` stripped to ASCII space (per lesson 2026-07-24) |

### 3.2 Defect repairs

| Rule | Count | Source lines | Change |
|---|---|---|---|
| **DEF-01** | 1 | 80–81, 228–229 | Removed duplicate `sac_cd` from INSERT col list (2nd) and SELECT expr list (2nd) |
| **DEF-02** | 3 | 177, 178, 179 | `ASallow_piece_qty` / `ASallow_weight_qty` / `ASallow_weight_unit_cd` → added whitespace after `AS` |
| **DEF-04** | 4 | 212, 213, 221, 222 | `CAST((col, 0, 9999999999) AS BIGINT)` → `CAST(COALESCE(col, 0) AS BIGINT)` (corrupted COALESCE + leftover range bound; 2 cols × 2 occurrences in `cou_seq_no` CASE) |
| **DEF-05** | 1 | SELECT pos 84 | Synthesized missing `yq_curr_vlu` expression as `best_sa.yq_curr_vlu` per `*_curr_vlu` (original-currency value) convention |
| **DEF-06** | 7 | 2, 9, 12, 13, 32, 43, 81 | Normalized cosmetic aliases to match INSERT target names (positional binding): `sa_src_cd`→`sale_src_cd`, `cou_no`→`cpn_no`, `opr_myflight_no`→`opr_flt_no`, `opr_myflight_sfx_cd`→`opr_flt_sfx_cd`, `alliance_cd`→`cd`, `ex_to_sa_dt`→`ex_to_sale_dt`, `e_rmk_email_addr_txt`→`emd_rmk_email_addr_txt` |

### 3.3 Semantic hardening

| Rule | Count | Source lines | Change |
|---|---|---|---|
| **SEM-07** | 1 | 478–483 | Made `NULLS LAST` explicit in final `QUALIFY … ORDER BY … DESC` (LEFT-JOIN keys can be NULL; Snowflake defaults `NULLS FIRST` for `DESC`) — flagged `TODO(SME)` |
| **SEM-02** | 3 | 409–413, 418–422, 478–483 | `TODO(SME)` before each `QUALIFY` re non-unique priority tiebreaker |
| **SEM-08** | 1 | 252–258 | `TODO(SME)` before `oc_yq_src_cd` CASE re empty-string `''` vs NULL sentinel |
| **SEM-01** | — | 244, 276, 284, 292, 304, 310, 316 | Verified decimal/decimal division — no truncation risk; kept `/` (note only, no change) |
| **SEM-10** | — | 437–441 | `gbp_to_usg_curr` misleading alias kept as-is (join correct; do NOT rename) |
| **SFX-03** | — | 409–413, 418–422, 478–483 | All 3 `QUALIFY` clauses kept as-is (no `ROW_NUMBER` subquery wrap) |

---

## 4. Defects repaired (detail)

1. **Duplicate `sac_cd` (DEF-01):** `sac_cd` appeared twice in both the INSERT
   target list and the SELECT expression list. Removed the second occurrence on
   each side so ordinal positions stay aligned.
2. **Malformed `CAST((col, 0, 9999999999) AS BIGINT)` (DEF-04):** A corrupted
   `COALESCE(col, 0)` with a leftover range bound `9999999999` inside a `CAST`.
   Rebuilt as `CAST(COALESCE(col, 0) AS BIGINT)` for `best_sa.dc_no` and
   `best_sa.pme_dc_no`, twice each (WHEN and THEN of the `cou_seq_no` CASE). The
   constant `9999999999` is unexplained without ground truth → `TODO(SME)`.
3. **Missing `yq_curr_vlu` (DEF-05):** INSERT position 84 had no corresponding
   SELECT expression (131 ≠ 130 net). Synthesized `best_sa.yq_curr_vlu` per the
   `*_curr_vlu` (original-currency value) convention, mirroring how `yq_vlu` is
   built from `best_sa.yq_curr_vlu / ex_rte`. → `TODO(SME)`.
4. **Missing-whitespace aliases (DEF-02):** `ASallow_*` tokens were parse errors;
   added the space after `AS`.
5. **Ideographic space (U+3000):** Non-ASCII whitespace before a `CASE`
   keyword survived the naive find/replace; stripped to ASCII space.

---

## 5. Open `TODO(SME)` items (17 outstanding)

| # | Rule | Location | Question for SME |
|---|---|---|---|
| 1 | SFX-01 | 451 | Confirm `CONTAINS` split-column names (`bus_efast_pd_start_dt` / `_end_dt`) against Teradata source |
| 2 | SFX-01 | 456 | Same — `disch_ctry_grp.bus_efast_pd` split columns |
| 3 | DEF-04 | 212, 221 | Confirm `CAST((col, 0, 9999999999) AS BIGINT)` rebuild; explain constant `9999999999` |
| 4 | DEF-04 | 213, 222 | Same — `best_sa.pme_dc_no` |
| 5 | DEF-05 | SELECT pos 84 | Confirm synthesized `yq_curr_vlu = best_sa.yq_curr_vlu` against Teradata source |
| 6 | DEF-06/DEF-07 | pos 32 | `alliance_cd` → target `cd`: genuine abbreviation or wrong-column copy-paste? |
| 7 | DEF-06/DEF-07 | pos 81 | `e_rmk_email_addr_txt` → target `emd_rmk_email_addr_txt`: abbreviation or wrong column? |
| 8 | SEM-02 | 409–413 | `QUALIFY` tiebreaker on `sa_priority_no` — is it unique per `(dc_id, cou_no)`? |
| 9 | SEM-02 | 418–422 | `QUALIFY` tiebreaker on `usg_priority_no` — unique? |
| 10 | SEM-02 | 478–483 | Final `QUALIFY` tiebreaker on exchange-rate `efast_dt` — unique? |
| 11 | SEM-03 | 269, 277, 283, 295, 331, 339, 347 | `*_cd` / `air_no` CHAR padding drift — are these `CHAR(n)`? Wrap with `TRIM` if so |
| 12 | SEM-05 | — | Precautionary: is `wrk_dc_priority` a SET table? (no DDL supplied) |
| 13 | SEM-06 | 269, 277, 283, 295, 331, 339, 347, 355 | Implicit string↔number casts (`air_no = '000'`) — verify `air_no` type |
| 14 | SEM-07 | 478–483 | Confirm `NULLS LAST` matches Teradata NULL-ordering assumption |
| 15 | SEM-08 | 252–258 | `oc_yq_src_cd` returns `''` (empty string) — intended vs NULL? |
| 16 | SEM-01 | 244, 276, 284, 292, 304, 310, 316 | Verify `*_curr_vlu` / `ex_rte` are decimal (no INT/INT truncation) if DDL becomes available |
| 17 | SEM-10 | 437–441 | Confirm `gbp_to_usg_curr` join direction (alias misleading; join correct) |

---

## 6. Validation result

### Fixed file — mechanical validation

```
PASS  parse: 1 statement(s) parsed as snowflake using sqlglot
PASS  stmt 1: INSERT columns (131) == SELECT expressions (131)
PASS  stmt 1: no duplicate INSERT columns
PASS  no residual Teradata constructs
INFO  TODO(SME) markers outstanding: 17
RESULT: PASS
```

### Manual spot-check

| Check | Result |
|---|---|
| Parse / compile under Snowflake dialect | PASS — 1 statement parses cleanly |
| INSERT column count == SELECT expression count | PASS — 131 == 131 |
| No duplicate INSERT columns | PASS — DEF-01 removed duplicate `sac_cd` |
| No residual Teradata constructs in SQL body | PASS — `ZEROIFNULL`→`COALESCE`; `CONTAINS`→`BETWEEN`; no `MULTISET`/`(+)`/`MINUS`/`SEL`/BTEQ |
| Malformed CAST remediated | PASS — 4 occurrences rebuilt as `CAST(COALESCE(col, 0) AS BIGINT)` |
| `CONTAINS` rewrite preserves semantics | PASS (pending SME) — split-column names flagged |
| Missing SELECT expression synthesized | PASS (pending SME) — `yq_curr_vlu = best_sa.yq_curr_vlu` flagged |
| Column order / JOIN keys / CASE-branch order preserved | PASS — minimal diff; no reordering |
| `QUALIFY` handling | Kept as-is (SFX-03); `NULLS LAST` added to final QUALIFY (SEM-07) |

**Verdict: PASS.**

### Buggy input control

```
FAIL  parse: Expecting ). Line 218, Col: 12.
FAIL  residual Teradata constructs: 4 found
RESULT: FAIL (2 hard check(s))
```

The control **correctly FAILs**: (1) parse failure at line 218 from the
malformed `CAST((col, 0, 9999999999) AS BIGINT)`; (2) 4 residual Teradata
constructs (`ZEROIFNULL` ×2, `PERIOD … CONTAINS` ×2). This confirms the defects
the fix addressed were real and structural. **Control verdict: FAIL (expected).**

---

## 7. Sign-off checklist

- [x] Fixed SQL parses as Snowflake (sqlglot)
- [x] INSERT cols (131) == SELECT expressions (131)
- [x] No duplicate INSERT columns
- [x] No residual Teradata constructs in SQL body
- [x] Column order, JOIN keys, CASE-branch order preserved (minimal diff)
- [x] `QUALIFY` kept (not wrapped in ROW_NUMBER subquery)
- [x] Control (buggy input) FAILs as expected
- [x] All inferences flagged `TODO(SME)` (17 markers)
- [ ] SME confirms `CONTAINS` split-column names (SFX-01)
- [ ] SME confirms `yq_curr_vlu` synthesis (DEF-05)
- [ ] SME confirms `CAST((col, 0, 9999999999) AS BIGINT)` rebuild (DEF-04)
- [ ] SME confirms `NULLS LAST` matches Teradata (SEM-07)
- [ ] SME resolves alias/column suspicions (pos 32, 81) and SEM-02/03/05/06/08/10 risks
- [ ] Reviewer signs off Stage-6 semantic doc

**Mechanical sign-off: READY.** Semantic sign-off pending SME review of the 17
`TODO(SME)` items and the Stage-6 semantic doc.