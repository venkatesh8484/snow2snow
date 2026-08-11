# Stage 1 — Analysis: `ins_wrk_dc_priority_snowflake.sql`

**Input:** `00_input/ins_wrk_dc_priority_snowflake.sql`
**Target:** `wrk_dc_priority`
**Teradata ground truth:** ❌ not supplied (no `00_input/ins_wrk_dc_priority.teradata.sql`)
**SnowSQL client layer:** N/A (`.sql` input — no `SNZ-*` constructs)

> **Note:** Archiving of prior outputs (`python3 05_report/archive_outputs.py
> ins_wrk_dc_priority`) could not be executed by this agent (no terminal
> access). If the orchestrator has not already archived them, run it before
> proceeding to Stage 3.

---

## 1. Column-count check (INSERT target cols vs SELECT expressions)

| Side | Raw count | Duplicates | Net unique |
|---|---|---|---|
| INSERT target columns | **132** | `sac_cd` ×2 (lines 79–80) | **131** |
| SELECT expressions | **131** | `sac_cd` ×2 (lines 236–237) | **130** |

**Net mismatch: INSERT 131 ≠ SELECT 130 — off by 1.**

Position-by-position mapping (after removing the duplicate `sac_cd` on both
sides) localises the gap to **INSERT position 84 = `yq_curr_vlu`**. The SELECT
jumps from `CASE … END AS yq_vlu` (pos 83) straight to `CASE … END AS
oc_yq_src_cd` (which maps to INSERT pos 85). The `yq_curr_vlu` expression is
**missing entirely** from the SELECT list → **DEF-05**.

| # | INSERT col (pos) | SELECT expr (pos) | Status |
|---|---|---|---|
| 1 | `usg_src_cd` | `best_usg.src_cd AS usg_src_cd` | ✓ |
| 2 | `sale_src_cd` | `best_sa.src_cd AS sa_src_cd` | alias mismatch (DEF-06) |
| 9 | `cpn_no` | `best_sa.cou_no` | alias mismatch (DEF-06) |
| 12 | `opr_flt_no` | `best_usg.opr_myflight_no AS opr_myflight_no` | alias mismatch (DEF-06) |
| 13 | `opr_flt_sfx_cd` | `best_usg.opr_myflight_sfx_cd AS opr_myflight_sfx_cd` | alias mismatch (DEF-06) |
| 32 | `cd` | `best_usg.alliance_cd AS alliance_cd` | alias mismatch — suspicious (DEF-06/DEF-07 → SME) |
| 43 | `ex_to_sale_dt` | `best_usg.ex_to_sa_dt AS ex_to_sa_dt` | alias mismatch (DEF-06) |
| 81 | `emd_rmk_email_addr_txt` | `MY_src.e_rmk_email_addr_txt` | alias mismatch — suspicious (DEF-06/DEF-07 → SME) |
| **84** | **`yq_curr_vlu`** | **— MISSING —** | **DEF-05** |
| 85 | `oc_yq_src_cd` | `CASE … END AS oc_yq_src_cd` | ✓ (shifted up by 1) |
| 86–132 | (all remaining) | (all remaining, shifted by 1) | ✓ aligned after the gap |

All positions 85–132 align correctly once the missing `yq_curr_vlu` slot is
accounted for.

---

## 2. Syntax errors / residual-Teradata constructs

| # | Line(s) | Construct | Rule | Why invalid on Snowflake | Class |
|---|---|---|---|---|---|
| S1 | 164 | `ZEROIFNULL(best_usg.grs_rev_vlu)` | FNX-01 | Teradata function; not defined in Snowflake → resolution error. Fix → `COALESCE(x, 0)`. | AUTO |
| S2 | 165 | `ZEROIFNULL(best_usg.grs_rev_curr_vlu)` | FNX-01 | Same as S1. | AUTO |
| S3 | 451 | `up_ctry_grp.bus_efast_pd CONTAINS best_usg.up_dt` | SFX-01 | `CONTAINS` is a Teradata PERIOD operator; invalid in Snowflake (parse error). Rebuild as `best_usg.up_dt BETWEEN <bus_efast_pd>_start_dt AND <bus_efast_pd>_end_dt` (assumes PERIOD split). | AUTO (TODO(SME) on split column names) |
| S4 | 456 | `disch_ctry_grp.bus_efast_pd CONTAINS best_usg.up_dt` | SFX-01 | Same as S3. | AUTO (TODO(SME)) |
| S5 | 304 | `LAST_DAY(dtrp.remittance_received_to_dt) - 3` | FNX-03 | Date−int works in Snowflake but is implicit; standardise to `DATEADD('day', -3, LAST_DAY(...))` for safety inside the larger expression. | AUTO |
| S6 | 335 | `LAST_DAY(dtrp.remittance_received_to_dt) - 3` | FNX-03 | Same as S5. | AUTO |
| S7 | 267 | `  CASE` (ideographic space U+3000 before `CASE`) | (new — see lessons 2026-07-24) | Non-ASCII whitespace (U+3000) survives naive find/replace; Snowflake parser rejects it (`unexpected ideographic spaces`). Must be stripped to ASCII space. | FIX |

**No** `SEL`, `SET`/`MULTISET`, `PRIMARY INDEX`, `COLLECT STATS`, BTEQ
directives, `(+)` joins, `MINUS`, `TOP`, or `FORMAT` casts were found.

---

## 3. Defects (DEF-*)

| # | Line(s) | Defect | Rule | Detail | Class |
|---|---|---|---|---|---|
| D1 | 79–80 (INSERT), 236–237 (SELECT) | Duplicate `sac_cd` column | DEF-01 | `sac_cd` appears twice in the INSERT target list and twice in the SELECT. Remove the duplicate on **both** sides so positions stay aligned. | FIX |
| D2 | 177 | `ASallow_piece_qty` | DEF-02 | Missing whitespace: `ASallow_piece_qty` → `AS allow_piece_qty`. Parse error. | AUTO |
| D3 | 178 | `ASallow_weight_qty` | DEF-02 | Same — `ASallow_weight_qty` → `AS allow_weight_qty`. | AUTO |
| D4 | 179 | `ASallow_weight_unit_cd` | DEF-02 | Same — `ASallow_weight_unit_cd` → `AS allow_weight_unit_cd`. | AUTO |
| D5 | 212, 213, 221, 222 | `CAST((best_sa.dc_no, 0, 9999999999) AS BIGINT)` | DEF-04 | Malformed function call: `(col, 0, 9999999999)` inside a `CAST` is a corrupted `COALESCE(col, 0)` with a leftover range bound. Rebuild as `CAST(COALESCE(col, 0) AS BIGINT)`, mark `TODO(SME)` on the constant `9999999999`. Occurs 4× (two in the WHEN, two in the THEN of the `cou_seq_no` CASE). | FIX |
| D6 | INSERT pos 84 / SELECT (missing) | Missing `yq_curr_vlu` expression | DEF-05 | INSERT has 131 net unique cols; SELECT has 130. The gap is exactly `yq_curr_vlu` (INSERT pos 84). Synthesise the most plausible expression from the `*_vlu` (GBP value) / `*_curr_vlu` (original-currency value) convention: `best_sa.yq_curr_vlu` mirrors how `yq_vlu` is built from `best_sa.yq_curr_vlu / ex_rte`. Mark `TODO(SME)`. | SME |
| D7 | pos 2 | `sa_src_cd` alias vs target `sale_src_cd` | DEF-06 | Cosmetic alias ≠ target name (positional binding). Normalise alias. | AUTO |
| D8 | pos 9 | `cou_no` (no alias) vs target `cpn_no` | DEF-06 | Abbreviation drift (`cou` = `cpn` = coupon). Cosmetic. | AUTO |
| D9 | pos 12 | `opr_myflight_no` alias vs target `opr_flt_no` | DEF-06 | Cosmetic alias ≠ target name. | AUTO |
| D10 | pos 13 | `opr_myflight_sfx_cd` alias vs target `opr_flt_sfx_cd` | DEF-06 | Cosmetic alias ≠ target name. | AUTO |
| D11 | pos 43 | `ex_to_sa_dt` alias vs target `ex_to_sale_dt` | DEF-06 | Abbreviation drift (`sa` vs `sale`). Cosmetic. | AUTO |
| D12 | pos 32 | `alliance_cd` alias vs target `cd` | DEF-06 / DEF-07 | Target `cd` is generic; source `alliance_cd` is specific. Could be a wrong-column copy-paste (DEF-07) or a genuine abbreviation. **No Teradata ground truth** → cannot prove. Flag SME. | SME |
| D13 | pos 81 | `e_rmk_email_addr_txt` vs target `emd_rmk_email_addr_txt` | DEF-06 / DEF-07 | `e_rmk` vs `emd_rmk` — abbreviation or wrong column? **No ground truth** → flag SME. | SME |

---

## 4. Semantic risks (SEM-*)

| # | Line(s) | Risk | Rule | Present? | Notes | Class |
|---|---|---|---|---|---|---|
| SE1 | 270, 286, 304, 335, 343 | Integer division `yq_curr_vlu / ex_rte` | SEM-01 | Likely **No** | `*_curr_vlu` / `ex_rte` are decimal/decimal per the codebase convention (confirmed in prior runs). No INT/INT truncation. Keep `/`. Verify types if DDL becomes available. | SME (verify) |
| SE2 | 409, 418 | `QUALIFY ROW_NUMBER() … ORDER BY sa_priority_no` / `usg_priority_no` | SEM-02 | **Yes** | Ties on the priority number are broken non-deterministically. If two rows share the same priority, the winner is undefined. Flag if `sa_priority_no`/`usg_priority_no` are not unique per `(dc_id, cou_no)`. | SME |
| SE3 | 269, 277, 283, 295, 331, 339, 347 | String equality on `*_cd` columns (`air_no = '000'`, `opr_cd = 'MY'`, `src_cd <> 'MY'`, `mktg_cd <> opr_cd`, `oc_yq_src_cd = 'R'`) | SEM-03 | **Yes** | If any `*_cd` / `air_no` column is `CHAR(n)`, Teradata blank-pads and ignores trailing spaces in `=`; Snowflake does not. Padding drift changes which rows match. Wrap with `TRIM`/`RTRIM` if CHAR. Requires DDL. | SME |
| SE4 | — | Timestamp / timezone | SEM-04 | **No** | No explicit `TIMESTAMP`/`CURRENT_TIMESTAMP` usage in this script. Not present. | — |
| SE5 | — | SET-table dedup | SEM-05 | **Not triggered** | Single `INSERT INTO wrk_dc_priority` (no multiple INSERTs, no `UNION`/`UNION ALL` writing to one target). No SET-dedup signal. **However**, no `CREATE TABLE` DDL for `wrk_dc_priority` is supplied, so SET vs MULTISET cannot be confirmed. Raise as a **precautionary SME question**: "Is `wrk_dc_priority` a SET table?" — but it is **not** a SEM-05 dedup-split candidate on the current evidence. | SME (precautionary) |
| SE6 | 269, 277, 283, 295, 331, 339, 347, 355 | Implicit string↔number cast (`air_no = '000'`, `… < 1000`) | SEM-06 | **Yes** | `air_no = '000'` compares a string literal to `air_no` (type unknown). If `air_no` is numeric, Snowflake is stricter than Teradata → runtime error or silent mismatch. `yq_curr_vlu / ex_rte < 1000` compares decimal to int literal (safe). Make casts explicit; verify `air_no` type. | SME |
| SE7 | 478–482 | `QUALIFY … ORDER BY sa_curr_to_gbp.efast_dt DESC, gbp_to_usg_curr.efast_dt DESC` | SEM-07 | **Yes** | Both `ORDER BY` keys come from **LEFT JOIN**s (`sa_curr_to_gbp`, `gbp_to_usg_curr`) and can be NULL. Snowflake defaults to `NULLS FIRST` for `DESC`, which would let no-exchange-rate rows win the pick. Make `NULLS LAST` explicit. **This is a semantic change** — flag `TODO(SME)` to confirm it matches the Teradata NULL-ordering assumption. | SME |
| SE8 | 258, 326, 341, 355 | `NULLIF(x, '')` and `THEN ''` in CASE | SEM-08 | **Yes** | `NULLIF(best_usg.opr_cd, '')` and `NULLIF(best_sa.mktg_cd, '')` rely on `''` being distinct from NULL. The `oc_yq_src_cd` CASE returns `''` (empty string) as a sentinel — confirm this is intended vs NULL. Snowflake treats `''` as a real empty string, not NULL. | SME |
| SE9 | — | Aggregate of empty set / `SUM` NULL | SEM-09 | **No** | No bare aggregates in this script. Not present. | — |
| SE10 | 437–447 | Exchange-rate join direction (`gbp_to_usg_curr` alias targets `curr_to_cd = 'GBP'`) | SEM-10 | **Yes** | The alias `gbp_to_usg_curr` is misleading (it actually joins **to** GBP, i.e. `curr_to_cd = 'GBP'`), but the join is correct per prior Teradata-confirmed runs. Do **not** "fix" the alias — it would hide, not solve. Flag for reviewer awareness. | SME (confirm) |

---

## 5. Classification summary

| Class | Count | Items |
|---|---|---|
| **AUTO** | 9 | S1, S2, S3, S4, S5, S6, D2, D3, D4 (+ D7–D11 cosmetic alias normalisation) |
| **FIX** | 6 | S7 (U+3000 strip), D1 (dup `sac_cd`), D5 (×4 malformed CAST) |
| **SME** | 9 | D6 (missing `yq_curr_vlu`), D12 (`alliance_cd`→`cd`), D13 (`e_rmk`→`emd_rmk`), SE1 (verify div types), SE2 (QUALIFY ties), SE3 (CHAR padding), SE5 (SET-table precautionary), SE6 (implicit cast), SE7 (NULLS LAST), SE8 (`''` vs NULL), SE10 (join direction confirm) |

**Total findings: 24** (15 mechanical + 9 semantic/SME).

---

## 6. Table dependency inventory

| Role | Table / alias | Lines | Notes |
|---|---|---|---|
| **TARGET** | `wrk_dc_priority` | 7 | INSERT target. No DDL supplied — SET/MULTISET unknown (SE5). |
| SOURCE | `wrk_dc_priority_ranked` (as `best_sa`) | 405–414 | Subquery; inner `QUALIFY` on `sa_priority_no`. |
| SOURCE | `wrk_dc_priority_ranked` (as `best_usg`) | 416–425 | Subquery; inner `QUALIFY` on `usg_priority_no`. |
| SOURCE | `wrk_dc_priority_ranked` (as `MY_src`) | 427–431 | LEFT JOIN, filtered `src_cd = 'MY'`. |
| LOOKUP | `wrkange_rate` (as `sa_curr_to_gbp`) | 433–438 | Exchange rate; `curr_to_cd = 'GBP'`, `ex_rte_typ = 'I5D'`. |
| LOOKUP | `wrkange_rate` (as `gbp_to_usg_curr`) | 440–445 | Exchange rate; same table, misleading alias (SE10). |
| LOOKUP | `wrkg_loc_hierarchy` (as `dep_loc_hierarchy`) | 447–448 | Station → country mapping. |
| LOOKUP | `wrkg_loc_hierarchy` (as `arr_loc_hierarchy`) | 450–451 | Station → country mapping. |
| LOOKUP | `ref_ctry` (as `up_ctry_grp`) | 452–455 | Country grouping; `CONTAINS` PERIOD operator (S3). |
| LOOKUP | `ref_ctry` (as `disch_ctry_grp`) | 457–460 | Country grouping; `CONTAINS` PERIOD operator (S4). |
| LOOKUP | `b_dc_tax_remittance_partner` (as `dtrp`) | 462–464 | Tax remittance partner. |
| SOURCE | `QYtna_burst` (as `fna`) | 468–472 | Inside `ty_t5` subquery. |
| SOURCE | `QYtng` (as `fng`) | 469–471 | Inside `ty_t5` subquery. |
| DERIVED | `ty_t5` | 466–474 | Subquery joining `QYtna_burst` ⋈ `QYtng`. |

**Note:** `wrkange_rate` looks like a find/replace artifact (possibly
`wrk_exchange_rate`), but with no ground truth this cannot be confirmed — left
as-is and flagged for reviewer awareness.

---

## 7. Verdict

**Does not run.** The script is a thin find/replace over a Teradata BTEQ that
left 2 `ZEROIFNULL` (FNX-01), 2 PERIOD `CONTAINS` (SFX-01), 2 implicit date
arithmetic (FNX-03), 4 malformed `CAST((col,0,…) AS BIGINT)` (DEF-04), 3
missing-whitespace aliases (DEF-02), 1 ideographic-space (U+3000) corruption, 1
duplicate `sac_cd` (DEF-01), and 1 missing `yq_curr_vlu` expression (DEF-05)
that breaks the INSERT/SELECT column count (131 ≠ 130). All mechanical issues
are fixable with existing rules; the missing `yq_curr_vlu`, two suspicious
alias/column mismatches, and the SEM-02/03/06/07/08/10 semantic risks require
SME confirmation (no Teradata ground truth supplied).