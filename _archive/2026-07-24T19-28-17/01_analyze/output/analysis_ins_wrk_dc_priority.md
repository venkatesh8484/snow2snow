# Analysis — `00_input/ins_wrk_dc_priority_snowflake.sql`

Single `INSERT INTO wrk_dc_priority (...) SELECT …` statement, airline
coupon/revenue domain (~483 lines). Delivered as "converted Snowflake" by
another team, but it does **not** run. Teradata original available as ground
truth: `../teradata2snowflake/00_input/ins_wrk_dc_priority.bteq`.

## Column-count check (do this first)

| Side | Count | Detail |
|---|---|---|
| INSERT column list | **132** | includes `sac_cd` twice (lines 80–81) |
| SELECT expressions | **131** | includes duplicated `COALESCE(...sac_cd...)`; **no expression for `yq_curr_vlu`** |

Net after removing the duplicate from both sides: 131 vs 130 → **one SELECT
expression missing** (position of `yq_curr_vlu`, between `yq_vlu` and
`oc_yq_src_cd`).

## Syntax errors / residual Teradata constructs

| # | Line(s) | Construct | Why invalid on Snowflake | Rule | Class |
|---|---|---|---|---|---|
| S1 | 164–165 | `ZEROIFNULL(best_usg.grs_rev_vlu)` (×2) | `ZEROIFNULL` is a Teradata function — undefined in Snowflake (resolution error) | FNX-01 | AUTO → `COALESCE(x, 0)` |
| S2 | 451, 456 | `bus_efast_pd CONTAINS best_usg.up_dt` (×2) | `CONTAINS` is a Teradata PERIOD operator — parse error in Snowflake | SFX-01 / DTX-05 | AUTO + assumption (split into `bus_efast_start_dt` / `bus_efast_end_dt`) |
| S3 | ~300, ~331 | `LAST_DAY(x) - 3` (date − int) | Runs, but ambiguous inside a large CASE; standardize | FNX-03 | AUTO → `DATEADD('day', -3, LAST_DAY(x))` |
| S4 | 421, 430, 494 | `QUALIFY ROW_NUMBER() OVER (…) = 1` | **Valid** — Snowflake supports QUALIFY natively | SFX-03 | AUTO (keep as-is) |

## Defects

| # | Line(s) | Defect | Rule | Class |
|---|---|---|---|---|
| D1 | 80–81 & 236–237 | `sac_cd` duplicated in INSERT list and SELECT list | DEF-01 | FIX — remove from both sides |
| D2 | 177–179 | `ASallow_piece_qty` etc. — missing space after `AS` | DEF-02 | FIX |
| D3 | 210–230 | `cou_seq_no`: `CAST((best_sa.dc_no, 0, 9999999999) AS BIGINT)` — malformed (row-constructor inside CAST) + unbalanced parens. **This is the parse-blocking error.** | DEF-03 / DEF-04 | FIX + SME — evident intent `CAST(COALESCE(dc_no, 0) AS BIGINT)`; `9999999999` looks like a leftover range bound |
| D4 | INSERT vs SELECT | INSERT expects `yq_curr_vlu` but SELECT provides only `yq_vlu` and `oc_yq_src_cd` → count mismatch | DEF-05 | FIX + SME — synthesize `COALESCE(best_sa.yq_curr_vlu, best_usg.yq_curr_vlu)` following the `*_curr_vlu` pattern |
| D5 | many | Alias ≠ target name (`sa_src_cd`/`sale_src_cd`, `opr_myflight_no`/`opr_flt_no`, `ex_to_sa_dt`/`ex_to_sale_dt`, `cd`/`alliance_cd`, `e_rmk_email_addr_txt`/`emd_rmk_email_addr_txt`) | DEF-06 | AUTO — positional, cosmetic; normalize aliases |
| D6 | ~351–357 | Seven `COALESCE(...)` expressions with no alias | DEF-06 | AUTO — add aliases matching target columns |

## Semantic risks (parse fine, could change results)

| # | Where | Risk | Rule | Verdict |
|---|---|---|---|---|
| M1 | `yq_curr_vlu / sa_curr_to_gbp.ex_rte` | Integer-division truncation | SEM-01 | Not present — both operands are decimals. Keep `/`. |
| M2 | Final `QUALIFY … ORDER BY efast_dt DESC` | Dedup tie-break determinism | SEM-02 | `ORDER BY` fully determines winner within (dc_id, cou_no). OK. |
| M3 | `gbp_to_usg_curr` join (also targets GBP) | Misleading alias hiding a bug | SEM-10 | Verified against Teradata — join is correct. **Do not rename.** |
| M4 | `up_ctry_grp` / `disch_ctry_grp` PERIOD lookups | PERIOD split-column names | SEM-04 / SFX-01 | Assumption on split names → TODO(SME). |

## Tables referenced

Target: `wrk_dc_priority`.
Sources: `wrk_dc_priority_ranked` (×3 self-join), `wrkange_rate` (×2),
`wrkg_loc_hierarchy` (×2), `ref_ctry` (×2), `b_dc_tax_remittance_partner`,
`QYtna_burst`, `QYtng`.

## Verdict

Not executable as delivered (D3 blocks parsing; S1/S2 fail resolution).
Remediable in one pass. **5 items need SME confirmation** (D3 constant intent,
D4 synthesized expression, SFX-01 period-column names ×2, plus the `-- TODO(SME)`
on the constant) — all repaired with `TODO(SME)` markers. Two semantic items
(M1, M3) confirmed equivalent against the Teradata original.
