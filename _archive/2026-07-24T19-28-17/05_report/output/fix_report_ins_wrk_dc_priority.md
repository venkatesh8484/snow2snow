# Remediation report — `ins_wrk_dc_priority_snowflake.sql` → `…_fixed.sql`

**Date:** 2026-07-23 · **Pipeline:** snowflake2snowflake ICM · **Status:** ✅ Fixed & validated (5 SME items open)

## Summary

One `INSERT…SELECT` (~483 lines, 131 target columns, 10 joins, airline
coupon/revenue domain), delivered as "converted Snowflake" but **not
executable**. It carried 4 residual Teradata constructs (2× `ZEROIFNULL`,
2× PERIOD `CONTAINS`) plus 4 real defects — one of which (malformed `CAST`)
prevents the file from parsing at all. All repaired and logged; automated
validation now passes.

## Fixes applied

### Syntax / function (made it run)

| Rule | Where | What |
|---|---|---|
| FNX-01 | 2× (grs_rev) | `ZEROIFNULL(x)` → `COALESCE(x, 0)` — Teradata fn undefined on Snowflake |
| SFX-01 / DTX-05 | 2 joins on `ref_ctry` | PERIOD `… CONTAINS date` → `date BETWEEN <col>_start_dt AND <col>_end_dt` |
| FNX-03 | 2× | `LAST_DAY(x) − 3` → `DATEADD('day', −3, LAST_DAY(x))` |
| SFX-03 | 3× | `QUALIFY ROW_NUMBER()…=1` kept (native on Snowflake) — no rewrite |

### Defects repaired (see FIX LOG in output file)

| ID | Defect | Repair |
|---|---|---|
| D1 (DEF-01) | `sac_cd` listed twice on both sides | Duplicate removed from both sides |
| D2 (DEF-02) | `ASallow_…` missing space ×3 | Repaired to `AS allow_…` |
| D3 (DEF-03/04) | Malformed `CAST((col, 0, 9999999999) AS BIGINT)` + unbalanced parens in `cou_seq_no` — original does not parse | Rebuilt as `CAST(COALESCE(col, 0) AS BIGINT)` |
| D4 (DEF-05) | SELECT missing expression for `yq_curr_vlu` (131 vs 132) | Synthesized `COALESCE(best_sa.yq_curr_vlu, best_usg.yq_curr_vlu)` |
| D5/D6 (DEF-06) | ~15 alias≠target + 7 missing aliases | Normalized / added |

## Open items for SME sign-off

1. **D3** — intent of literal `9999999999` (dropped as a leftover range bound).
2. **D4** — business rule for `yq_curr_vlu` (synthesized from sibling pattern).
3. **SFX-01 (×2)** — actual names of the split PERIOD columns in migrated
   `ref_ctry` DDL (assumed `bus_efast_start_dt` / `bus_efast_end_dt`).
4. **Inline** `-- TODO(SME)` on the `cou_seq_no` constant.

## Validation

`validate.py` (sqlglot, snowflake dialect): parse **PASS**, column counts
**PASS** (131 = 131), no duplicates **PASS**, no residual Teradata **PASS**.
Control run on the buggy input **FAILS** (parse + 4 residual). Full details:
`04_validate/output/validation_ins_wrk_dc_priority.md`.

## Semantic sign-off

Confirmed equivalent to the Teradata original — see
`06_explain/output/semantic_ins_wrk_dc_priority.md`. Key results: no
integer-division truncation (SEM-01), dedup ordering deterministic (SEM-02),
misleading `gbp_to_usg_curr` alias verified correct and intentionally not
renamed (SEM-10).
