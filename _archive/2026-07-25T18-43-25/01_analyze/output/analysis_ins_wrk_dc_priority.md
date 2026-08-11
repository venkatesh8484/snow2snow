# Stage 1 — Analysis: `ins_wrk_dc_priority_snowflake.sql`

**Input:** `00_input/ins_wrk_dc_priority_snowflake.sql`
**Teradata ground truth:** None (no `ins_wrk_dc_priority_snowflake.teradata.sql` in `00_input/`). Semantic intent inferred from `02_rules/` + `06_lessons_learned.md`; every inference flagged `TODO(SME)`.
**Target:** `wrk_dc_priority` (INSERT-only script; no `CREATE TABLE` DDL supplied)

---

## 1. Column-count check (INSERT target cols vs SELECT expressions)

| Side | Raw count | Duplicate | Net (after removing duplicate) |
|---|---|---|---|
| INSERT target columns | **132** | `sac_cd` appears twice (lines 80–81, positions 70–71) | **131** |
| SELECT expressions | **131** | `COALESCE(best_usg.sac_cd, MY_src.sac_cd) AS sac_cd` appears twice (lines 228–229, positions 70–71) | **130** |

**Duplicate (DEF-01):** `sac_cd` is duplicated on **both** sides at the same positional offset (70–71). Removing the duplicate from both sides leaves INSERT = 131, SELECT = 130 → **net mismatch of 1** (DEF-05).

### Positional alignment after removing the duplicate

Positions 1–70 and 72–end were aligned position-by-position. The gap is at **INSERT position 84** (`yq_curr_vlu`):

| INSERT pos | INSERT column | SELECT pos | SELECT expression | Status |
|---|---|---|---|---|
| 83 | `yq_vlu` | 83 | `CASE … END AS yq_vlu` | ✓ aligned |
| **84** | **`yq_curr_vlu`** | **84** | **`CASE … END AS oc_yq_src_cd`** | **✗ MISMATCH — SELECT is missing `yq_curr_vlu`** |
| 85 | `oc_yq_src_cd` | 85 | `COALESCE(best_sa.sa_opr_cd, …)` | ✗ shifted |

After the missing `yq_curr_vlu`, every subsequent SELECT expression is off-by-one from the INSERT target. The tail re-aligns because the SELECT has one fewer expression overall (INSERT 131 = `sched_chng_ind` ↔ SELECT 130 = `sched_chng_ind`).

**DEF-05 conclusion:** The SELECT is missing a `yq_curr_vlu` expression at INSERT position 84. Per `06_lessons_learned.md`, `*_vlu` = GBP value and `*_curr_vlu` = original-currency value. The most plausible synthesis is `best_sa.yq_curr_vlu` (the original-currency YQ value from the SA row), but with no Teradata ground truth this must be flagged `TODO(SME)`.

### Additional alias ≠ target name mismatches (DEF-06 — not defects, normalize for readability)

| INSERT pos | INSERT column | SELECT alias | Note |
|---|---|---|---|
| 2 | `sale_src_cd` | `sa_src_cd` | `best_sa.src_cd AS sa_src_cd` — alias drift |
| 9 | `cpn_no` | (no alias) `cou_no` | `best_sa.cou_no` — name mismatch |
| 12 | `opr_flt_no` | `opr_myflight_no` | `best_usg.opr_myflight_no` — name mismatch |
| 13 | `opr_flt_sfx_cd` | `opr_myflight_sfx_cd` | name mismatch |
| 32 | `cd` | `alliance_cd` | `best_usg.alliance_cd AS alliance_cd` — name mismatch |
| 43 | `ex_to_sale_dt` | `ex_to_sa_dt` | `best_usg.ex_to_sa_dt AS ex_to_sa_dt` — name mismatch |
| 81 | `emd_rmk_email_addr_txt` | `e_rmk_email_addr_txt` | `MY_src.e_rmk_email_addr_txt` — name mismatch |

These are positional INSERT…SELECT mappings where the alias differs from the target column name. Per DEF-06, these are **not defects** — INSERT…SELECT is positional. Normalize aliases to target names for readability in Stage 3.

---

## 2. Syntax errors / residual-Teradata constructs

| # | Line(s) | Construct | Rule | Why invalid on Snowflake | Class |
|---|---|---|---|---|---|
| 1 | 164 | `ZEROIFNULL(best_usg.grs_rev_vlu)` | FNX-01 | `ZEROIFNULL` is a Teradata function; not defined in Snowflake → resolution error. Fix: `COALESCE(best_usg.grs_rev_vlu, 0)`. | AUTO |
| 2 | 165 | `ZEROIFNULL(best_usg.grs_rev_curr_vlu)` | FNX-01 | Same as above. Fix: `COALESCE(best_usg.grs_rev_curr_vlu, 0)`. | AUTO |
| 3 | 451 | `up_ctry_grp.bus_efast_pd CONTAINS best_usg.up_dt` | SFX-01 | `CONTAINS` is a Teradata PERIOD operator; invalid in Snowflake (parse error). Fix: `best_usg.up_dt BETWEEN up_ctry_grp.bus_efast_pd_start_dt AND up_ctry_grp.bus_efast_pd_end_dt` with `TODO(SME)` on split column names. | AUTO |
| 4 | 456 | `disch_ctry_grp.bus_efast_pd CONTAINS best_usg.up_dt` | SFX-01 | Same as above. Fix: `best_usg.up_dt BETWEEN disch_ctry_grp.bus_efast_pd_start_dt AND disch_ctry_grp.bus_efast_pd_end_dt` with `TODO(SME)`. | AUTO |
| 5 | 304 | `LAST_DAY(dtrp.remittance_received_to_dt) - 3` | FNX-03 | Date − integer subtraction. Snowflake accepts it but FNX-03 standardizes to `DATEADD('day', -3, LAST_DAY(dtrp.remittance_received_to_dt))` for explicitness inside larger expressions. | AUTO |
| 6 | 335 | `LAST_DAY(dtrp.remittance_received_to_dt) - 3` | FNX-03 | Same as above (second occurrence in `oc_yq_src_cd` CASE). | AUTO |
| 7 | 212, 221 | `CAST((best_sa.dc_no, 0, 9999999999) AS BIGINT)` | DEF-04 | Malformed function call — `(col, 0, 9999999999)` inside a CAST is a corrupted `COALESCE(col, 0)` with a leftover range bound. `CAST((a, b, c) AS BIGINT)` is not valid Snowflake syntax (parse error). Fix: `CAST(COALESCE(best_sa.dc_no, 0) AS BIGINT)`, `TODO(SME)` on the `9999999999` constant. | FIX |
| 8 | 213, 222 | `CAST((best_sa.pme_dc_no, 0, 9999999999) AS BIGINT)` | DEF-04 | Same as above for `pme_dc_no`. | FIX |
| 9 | 177 | `best_usg.MYg_allow_piece_qty ASallow_piece_qty` | DEF-02 | Missing whitespace between `AS` and alias → `ASallow_piece_qty` is parsed as a single identifier, not `AS allow_piece_qty`. Parse error / wrong alias. | FIX |
| 10 | 178 | `best_usg.MYg_allow_weight_qty ASallow_weight_qty` | DEF-02 | Same missing-whitespace typo. | FIX |
| 11 | 179 | `best_usg.MYg_allow_weight_unit_cd ASallow_weight_unit_cd` | DEF-02 | Same missing-whitespace typo. | FIX |

**No other residual Teradata constructs found:** No `SEL`, `SET`/`MULTISET`, `PRIMARY INDEX`, `COLLECT STATS`, BTEQ directives, `LOCKING`, `(+)` joins, `MINUS`, `TOP`, or `CAST … FORMAT` present. `QUALIFY` is present (3×) and correctly retained per SFX-03.

---

## 3. Defects (DEF-*)

| # | Line(s) | Defect | Rule | Description | Class |
|---|---|---|---|---|---|
| 1 | 80–81 (INSERT), 228–229 (SELECT) | Duplicate `sac_cd` | DEF-01 | `sac_cd` appears twice in the INSERT column list and twice in the SELECT expression list at the same positional offset. Remove the duplicate from both sides. | AUTO |
| 2 | 177 | `ASallow_piece_qty` | DEF-02 | Missing space between `AS` and alias. Repair to `AS allow_piece_qty`. | FIX |
| 3 | 178 | `ASallow_weight_qty` | DEF-02 | Same. Repair to `AS allow_weight_qty`. | FIX |
| 4 | 179 | `ASallow_weight_unit_cd` | DEF-02 | Same. Repair to `AS allow_weight_unit_cd`. | FIX |
| 5 | 212, 221 | `CAST((best_sa.dc_no, 0, 9999999999) AS BIGINT)` | DEF-04 | Corrupted `COALESCE(best_sa.dc_no, 0)` with leftover range bound `9999999999`. Rebuild as `CAST(COALESCE(best_sa.dc_no, 0) AS BIGINT)`. `TODO(SME)` on the constant. | FIX |
| 6 | 213, 222 | `CAST((best_sa.pme_dc_no, 0, 9999999999) AS BIGINT)` | DEF-04 | Same for `pme_dc_no`. Rebuild as `CAST(COALESCE(best_sa.pme_dc_no, 0) AS BIGINT)`. `TODO(SME)` on the constant. | FIX |
| 7 | INSERT pos 84 / SELECT pos 84 | Missing `yq_curr_vlu` SELECT expression | DEF-05 | After removing the duplicate `sac_cd`, INSERT has 131 columns vs SELECT 130 expressions. The gap is at INSERT position 84 (`yq_curr_vlu`): the SELECT jumps from `yq_vlu` directly to `oc_yq_src_cd`, skipping `yq_curr_vlu`. Synthesize the most plausible expression (e.g. `best_sa.yq_curr_vlu`) per the `*_vlu`/`*_curr_vlu` naming convention, flag `TODO(SME)`. | SME |

---

## 4. Semantic risks (SEM-*)

| # | Rule | Line(s) | Risk present? | Assessment | Class |
|---|---|---|---|---|---|
| 1 | SEM-01 (integer division truncation) | 244, 276, 284, 292, 304, 310, 316 | **Present — no risk** | `best_sa.yq_curr_vlu / sa_curr_to_gbp.ex_rte` is decimal/decimal (currency value / exchange rate). Per `06_lessons_learned.md` (2026-07-23): confirmed decimal/decimal, no truncation risk. Keep `/`. | AUTO (note only) |
| 2 | SEM-02 (QUALIFY tie-breaking) | 409–413, 418–422, 478–483 | **Present — risk** | Three `QUALIFY ROW_NUMBER() OVER (… ) = 1` clauses. (a) Lines 409–413: `ORDER BY sa_priority_no` — ties broken non-deterministically if multiple rows share the same `sa_priority_no` within a partition. (b) Lines 418–422: `ORDER BY usg_priority_no` — same tie risk. (c) Lines 478–483: `ORDER BY sa_curr_to_gbp.efast_dt DESC, gbp_to_usg_curr.efast_dt DESC` — ties possible if same `efast_dt`. None of the ORDER BY clauses include a unique tiebreaker column. | SME |
| 3 | SEM-07 (NULL ordering in QUALIFY ORDER BY) | 478–483 | **Present — risk** | The final QUALIFY orders by `sa_curr_to_gbp.efast_dt DESC, gbp_to_usg_curr.efast_dt DESC`. Both columns come from LEFT JOINs and can be NULL. Snowflake defaults to `NULLS FIRST` for DESC, which means NULL `efast_dt` rows would rank first and win the `ROW_NUMBER() = 1` pick. If the Teradata source assumed NULLs sort last (or vice versa), the winning row changes. Make `NULLS LAST` explicit (or `NULLS FIRST` per SME). | SME |
| 4 | SEM-10 (misleading alias / join direction) | 437–441 | **Present — do NOT fix** | `gbp_to_usg_curr` alias joins on `curr_to_cd = 'GBP'` — the alias name suggests "GBP to USD" but the join actually converts *to* GBP. Per `06_lessons_learned.md` (2026-07-23): the alias is misleading but the join is correct against the Teradata source. Do **not** rename the alias (SEM-10). | AUTO (no change) |
| 5 | SEM-05 (SET-table dedup) | N/A | **Not applicable** | Single `INSERT INTO wrk_dc_priority` — no multiple INSERTs, no `UNION`/`UNION ALL` into one target. No SET-table signal. No `CREATE TABLE` DDL supplied. | N/A |
| 6 | SEM-03 (CHAR padding) | — | Not detected | No explicit `CHAR(n)` comparisons found in predicates/joins. | N/A |
| 7 | SEM-04 (timestamp TZ) | — | Not detected | No `TIMESTAMP` type declarations or TZ-dependent functions in this script. | N/A |
| 8 | SEM-06 (implicit cast / NULL) | 212–222 | Low | The malformed `CAST((col, 0, 999…) AS BIGINT)` (DEF-04) involves implicit casting, but the fix (explicit `CAST(COALESCE(col, 0) AS BIGINT)`) resolves it. | AUTO |
| 9 | SEM-08 (empty string vs NULL) | 252–258, 299–321 | Low | `NULLIF(best_usg.opr_cd, '')` and `NULLIF(best_sa.mktg_cd, '')` correctly use empty string — Snowflake treats `''` as a real empty string, not NULL, so `NULLIF(x, '')` is correct. The `oc_yq_src_cd` CASE returns `''` (empty string) in several branches — verify this matches Teradata intent (empty string vs NULL). | SME |
| 10 | SEM-09 (aggregate empty set) | — | Not detected | No bare `SUM`/`AVG` over potentially empty sets without COALESCE. | N/A |

---

## 5. Classification summary

| Finding | Rule | Class |
|---|---|---|
| `ZEROIFNULL` × 2 | FNX-01 | AUTO |
| `PERIOD CONTAINS` × 2 | SFX-01 | AUTO |
| `date - 3` × 2 | FNX-03 | AUTO |
| `QUALIFY` × 3 | SFX-03 | AUTO (keep as-is) |
| Duplicate `sac_cd` (INSERT + SELECT) | DEF-01 | AUTO |
| `ASallow_*` typos × 3 | DEF-02 | FIX |
| `CAST((col, 0, 999…) AS BIGINT)` × 4 occurrences (2 cols × 2 CASE branches) | DEF-04 | FIX |
| Missing `yq_curr_vlu` SELECT expression | DEF-05 | SME |
| Alias ≠ target name × 7 | DEF-06 | AUTO (normalize) |
| Decimal/decimal division — no truncation | SEM-01 | AUTO (note only) |
| QUALIFY tie-breaking (3 clauses) | SEM-02 | SME |
| NULL ordering in final QUALIFY | SEM-07 | SME |
| `gbp_to_usg_curr` misleading alias | SEM-10 | AUTO (do NOT fix) |
| Empty-string vs NULL in `oc_yq_src_cd` CASE | SEM-08 | SME |

**Totals:** 8 AUTO, 4 FIX, 4 SME

---

## 6. Table dependency inventory

| # | Table/alias | Role | Lines |
|---|---|---|---|
| 1 | `wrk_dc_priority` | **Target** (INSERT INTO) | 10 |
| 2 | `wrk_dc_priority_ranked` (alias `best_sa`) | Source — best SA row per dc_id/cou_no | 405–414 |
| 3 | `wrk_dc_priority_ranked` (alias `best_usg`) | Source — best USG row per dc_id/cou_no | 416–425 |
| 4 | `wrk_dc_priority_ranked` (alias `MY_src`) | Source — MY-source row per dc_id/cou_no | 427–432 |
| 5 | `wrkange_rate` (alias `sa_curr_to_gbp`) | Source — exchange rate SA-currency → GBP | 434–441 |
| 6 | `wrkange_rate` (alias `gbp_to_usg_curr`) | Source — exchange rate (misleading alias, joins to GBP) | 437–441 |
| 7 | `wrkg_loc_hierarchy` (alias `dep_loc_hierarchy`) | Source — departure station → country mapping | 443–445 |
| 8 | `wrkg_loc_hierarchy` (alias `arr_loc_hierarchy`) | Source — arrival station → country mapping | 447–448 |
| 9 | `ref_ctry` (alias `up_ctry_grp`) | Source — departure country grouping (PERIOD CONTAINS) | 449–452 |
| 10 | `ref_ctry` (alias `disch_ctry_grp`) | Source — discharge country grouping (PERIOD CONTAINS) | 454–457 |
| 11 | `b_dc_tax_remittance_partner` (alias `dtrp`) | Source — remittance partner by air_no | 459–462 |
| 12 | `QYtna_burst` (alias `fna`, inside subquery `ty_t5`) | Source — flight network burst | 465–472 |
| 13 | `QYtng` (alias `fng`, inside subquery `ty_t5`) | Source — flight network grouping | 465–472 |

**Note:** `wrk_dc_priority_ranked` is referenced 3× (as `best_sa`, `best_usg`, `MY_src`). `wrkange_rate` is referenced 2× (as `sa_curr_to_gbp`, `gbp_to_usg_curr`). `wrkg_loc_hierarchy` is referenced 2× (as `dep_loc_hierarchy`, `arr_loc_hierarchy`). `ref_ctry` is referenced 2× (as `up_ctry_grp`, `disch_ctry_grp`).

---

## 7. Verdict

**Does not run on Snowflake.** The script is a thin find/replace over Teradata BTEQ with 2 `ZEROIFNULL` (FNX-01), 2 `PERIOD CONTAINS` (SFX-01), 2 date-int subtractions (FNX-03), 4 malformed `CAST((col,0,999…))` calls (DEF-04), 3 `ASallow_*` whitespace typos (DEF-02), a duplicate `sac_cd` (DEF-01), and a 1-column INSERT/SELECT count mismatch from a missing `yq_curr_vlu` expression (DEF-05/SME). `QUALIFY` is correctly retained (SFX-03). Semantic risks: QUALIFY tie-breaking and NULL ordering need SME review (SEM-02/SEM-07); the `gbp_to_usg_curr` misleading alias must NOT be "fixed" (SEM-10); decimal/decimal division has no truncation risk (SEM-01).