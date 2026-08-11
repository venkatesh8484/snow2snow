# Stage 1 Analysis — `ins_wrk_dc_priority_snowflake.sql`

**Input:** `00_input/ins_wrk_dc_priority_snowflake.sql` (~480 lines)
**Teradata ground truth:** None. No `00_input/ins_wrk_dc_priority.teradata.sql`
is present. Per the Stage-1 contract, semantic intent is inferred from
`02_rules/` and the Snowflake input alone; every inference is flagged
`TODO(SME)`. The pipeline is **never** to reach outside the workspace for a
Teradata original.
**File name:** `ins_wrk_dc_priority`

## 0. Statement shape

The file is a single `INSERT … SELECT … FROM … JOIN … QUALIFY … ;` statement:

- Lines 5–130: `INSERT INTO wrk_dc_priority ( <132-column list> )` — explicit
  target column list.
- Lines 131–397: `SELECT` — one large expression list (131 expressions).
- Lines 398–484: `FROM` + 9 `JOIN`s + final `QUALIFY`.
- Line 484: terminating `;`.

There is **one** statement (one `INSERT`, one `SELECT`). There is **no**
`CREATE TABLE` DDL for `wrk_dc_priority` in this file.

## 1. Column-count check

Counted the INSERT target columns and the SELECT expressions by hand.

| Side | Raw count | Duplicates | Net (unique) |
|---|---|---|---|
| INSERT target columns | 132 | `sac_cd` appears twice (lines 80–81) | 131 |
| SELECT expressions | 131 | `COALESCE(best_usg.sac_cd, MY_src.sac_cd) AS sac_cd` appears twice (lines 236–237) | 130 |

**After removing the duplicate `sac_cd` from both sides:**

| Side | Net unique count |
|---|---|
| INSERT (deduped) | 131 |
| SELECT (deduped) | 130 |

**Mismatch: INSERT has 131 unique columns, SELECT has 130 unique expressions —
off by 1 (DEF-05).**

### Locating the missing expression

Aligning the two lists positionally (after removing the duplicate `sac_cd`),
the gap falls at INSERT position 84: `yq_curr_vlu` (line 94 in the INSERT list).

The SELECT expressions around that position are:

| SELECT pos | Alias | Source line |
|---|---|---|
| 83 | `yq_vlu` (big CASE) | ~258–319 |
| 84 | `oc_yq_src_cd` (CASE) | ~320–356 |

There is **no** SELECT expression aliased `yq_curr_vlu`. The INSERT column
`yq_curr_vlu` (line 94) has no matching SELECT expression. This is the DEF-05
gap.

**Inference (TODO(SME)):** Following the codebase convention
(`*_vlu` = GBP value, `*_curr_vlu` = original-currency value — per
`06_lessons_learned.md`), the most plausible missing expression is
`best_sa.yq_curr_vlu` (the original-currency YQ value from the sale row),
mirroring how `yq_vlu` is computed. However, without the Teradata ground truth
this cannot be confirmed — it must be flagged `TODO(SME)`.

## 2. Syntax errors / residual-Teradata constructs

Scanned for every construct in `02_rules/01_syntax_fixes.md` (`SFX-*`),
`02_rules/03_function_fixes.md` (`FNX-*`), and `02_rules/02_datatype_rules.md`
(`DTX-*`).

| Line(s) | Construct | Rule | Why invalid on Snowflake | Class |
|---|---|---|---|---|
| 164 | `ZEROIFNULL(best_usg.grs_rev_vlu)` | FNX-01 | `ZEROIFNULL` is a Teradata function; not defined in Snowflake → resolution error. Fix: `COALESCE(best_usg.grs_rev_vlu, 0)`. | AUTO |
| 165 | `ZEROIFNULL(best_usg.grs_rev_curr_vlu)` | FNX-01 | Same — `ZEROIFNULL` undefined in Snowflake. Fix: `COALESCE(best_usg.grs_rev_curr_vlu, 0)`. | AUTO |
| 451 | `up_ctry_grp.bus_efast_pd CONTAINS best_usg.up_dt` | SFX-01 | `CONTAINS` is a Teradata PERIOD operator; invalid in Snowflake (parse error). Fix: `best_usg.up_dt BETWEEN up_ctry_grp.bus_efast_pd_start_dt AND up_ctry_grp.bus_efast_pd_end_dt` (assuming the PERIOD column was split). **TODO(SME)** to confirm split-column names. | SME |
| 456 | `disch_ctry_grp.bus_efast_pd CONTAINS best_usg.up_dt` | SFX-01 | Same — `CONTAINS` PERIOD operator; invalid in Snowflake. Fix: `best_usg.up_dt BETWEEN disch_ctry_grp.bus_efast_pd_start_dt AND disch_ctry_grp.bus_efast_pd_end_dt`. **TODO(SME)** to confirm split-column names. | SME |
| 304 | `LAST_DAY(dtrp.remittance_received_to_dt) - 3` | FNX-03 | Date−integer arithmetic. Snowflake accepts `date - int` but the rule standardizes to `DATEADD('day', -3, LAST_DAY(dtrp.remittance_received_to_dt))` for explicitness inside larger expressions. | AUTO |
| 335 | `LAST_DAY(dtrp.remittance_received_to_dt) - 3` | FNX-03 | Same — date−integer arithmetic. Fix: `DATEADD('day', -3, LAST_DAY(dtrp.remittance_received_to_dt))`. | AUTO |
| 212, 221 | `CAST((best_sa.dc_no, 0, 9999999999) AS BIGINT)` | DEF-04 | Malformed CAST — `(col, 0, 9999999999)` is a corrupted `COALESCE(col, 0)` with a leftover range bound. This is a **defect**, not valid Snowflake syntax (parse error: a parenthesised comma-list is not a valid CAST argument). Fix: `CAST(COALESCE(best_sa.dc_no, 0) AS BIGINT)`. **TODO(SME)** on the `9999999999` constant. | SME |
| 213, 222 | `CAST((best_sa.pme_dc_no, 0, 9999999999) AS BIGINT)` | DEF-04 | Same malformed CAST pattern. Fix: `CAST(COALESCE(best_sa.pme_dc_no, 0) AS BIGINT)`. **TODO(SME)** on the constant. | SME |
| 177 | `best_usg.MYg_allow_piece_qty ASallow_piece_qty` | DEF-02 | Missing space — `ASallow_piece_qty` is parsed as a single identifier, not `AS allow_piece_qty`. Parse error / wrong alias. Fix: `AS allow_piece_qty`. | FIX |
| 178 | `best_usg.MYg_allow_weight_qty ASallow_weight_qty` | DEF-02 | Same — `ASallow_weight_qty`. Fix: `AS allow_weight_qty`. | FIX |
| 179 | `best_usg.MYg_allow_weight_unit_cd ASallow_weight_unit_cd` | DEF-02 | Same — `ASallow_weight_unit_cd`. Fix: `AS allow_weight_unit_cd`. | FIX |
| 409, 418, 478 | `QUALIFY ROW_NUMBER() OVER (...) = 1` | SFX-03 | **Valid — keep as-is.** Snowflake supports `QUALIFY` natively. Do not rewrite as a wrapped ROW_NUMBER subquery. Minimal diff. | — |

### Constructs checked and NOT present

| Construct | Status |
|---|---|
| `SEL`, `MINUS`, `TOP`, `(+)` joins, `PRIMARY INDEX`, `COLLECT STATS`, BTEQ dot-commands, `LOCKING ROW` | Not present |
| `NULLIFZERO`, `INDEX()`, `OREPLACE`, `OTRANSLATE`, `STRTOK`, `LIKE ANY`, `TITLE`/`FORMAT` phrases, `**`, `MOD` | Not present |
| `BYTEINT`, `CHARACTER SET`, `PERIOD(...)`, `BYTE/VARBYTE`, `CLOB/BLOB`, `INTERVAL`, `DATE FORMAT` in DDL | Not present (no DDL in file) |
| `CAST(... FORMAT ...)` (FNX-08 / SFX-15) | Not present |
| `SET` / `MULTISET` keywords (SFX-05) | Not present in this file |

## 3. Defects

| Line(s) | Defect | Rule | Description | Class |
|---|---|---|---|---|
| 80–81 | Duplicate `sac_cd` in INSERT list | DEF-01 | `sac_cd` appears twice in the INSERT column list (lines 80 and 81). Remove the duplicate so positions stay aligned. | FIX |
| 236–237 | Duplicate `COALESCE(best_usg.sac_cd, MY_src.sac_cd) AS sac_cd` in SELECT | DEF-01 | The same expression `COALESCE(best_usg.sac_cd, MY_src.sac_cd) AS sac_cd` appears twice (lines 236 and 237). Remove the duplicate. | FIX |
| 94 / (no SELECT) | Missing `yq_curr_vlu` SELECT expression | DEF-05 | INSERT has `yq_curr_vlu` (line 94) but the SELECT has no expression aliased `yq_curr_vlu`. After dedup, INSERT = 131, SELECT = 130 — off by 1. The gap is at the `yq_curr_vlu` position. **TODO(SME):** synthesize the most plausible expression (likely `best_sa.yq_curr_vlu`) per the `*_curr_vlu` naming convention, but flag for human confirmation. | SME |
| 212, 221 | `CAST((best_sa.dc_no, 0, 9999999999) AS BIGINT)` | DEF-04 | Malformed CAST — `(col, 0, 9999999999)` is a corrupted `COALESCE(col, 0)` with a leftover range bound. Fix: `CAST(COALESCE(best_sa.dc_no, 0) AS BIGINT)`. **TODO(SME)** on the `9999999999` constant. | SME |
| 213, 222 | `CAST((best_sa.pme_dc_no, 0, 9999999999) AS BIGINT)` | DEF-04 | Same malformed CAST pattern. Fix: `CAST(COALESCE(best_sa.pme_dc_no, 0) AS BIGINT)`. **TODO(SME)** on the constant. | SME |
| 177 | `ASallow_piece_qty` | DEF-02 | Missing space between `AS` and alias. Fix: `AS allow_piece_qty`. | FIX |
| 178 | `ASallow_weight_qty` | DEF-02 | Missing space. Fix: `AS allow_weight_qty`. | FIX |
| 179 | `ASallow_weight_unit_cd` | DEF-02 | Missing space. Fix: `AS allow_weight_unit_cd`. | FIX |

## 4. Semantic risks

| ID | Risk | Present? | Details | Class |
|---|---|---|---|---|
| SEM-01 | Integer division | **Check** | Multiple divisions `best_sa.yq_curr_vlu / sa_curr_to_gbp.ex_rte` (lines 270, 286, 305, 307, 315, 344) and `MY_src.cdshr_comm_vlu * gbp_to_usg_curr.ex_rte` (line 244, multiplication — not division). The `*_vlu` / `*_curr_vlu` columns are monetary values (typically `DECIMAL`/`NUMBER`), and `ex_rte` is an exchange rate (also `DECIMAL`/`NUMBER`). Per `06_lessons_learned.md` (2026-07-23 entry): *"Division `yq_curr_vlu / ex_rte` is decimal/decimal here — no SEM-01 truncation risk."* If both operands are decimal, `/` returns a decimal in both Teradata and Snowflake — no truncation. **TODO(SME):** confirm `yq_curr_vlu` and `ex_rte` are both `DECIMAL`/`NUMBER` (not `INTEGER`). If either is `INTEGER`, truncation may have been intended → wrap in `FLOOR`/`TRUNC`. | SME |
| SEM-02 | `QUALIFY` / dedup ordering | **Present** | Three `QUALIFY ROW_NUMBER() OVER (...) = 1` clauses (lines 409, 418, 478). The inner two (lines 409, 418) partition by `dc_id, cou_no` and order by `sa_priority_no` / `usg_priority_no` — if two rows share the same priority number, the tie is non-deterministic. The outer `QUALIFY` (line 478) orders by `sa_curr_to_gbp.efast_dt DESC, gbp_to_usg_curr.efast_dt DESC` — ties on both exchange-rate dates are non-deterministic. **Risk:** ordering drift can change which row wins. Flag for SME to confirm whether the `ORDER BY` fully determines the winner. | SME |
| SEM-03 | `CHAR(n)` padding & comparison | Not present | No `CHAR(n)` comparisons identified in this script (no DDL supplied; comparisons are on `VARCHAR`-style codes). | — |
| SEM-04 | Timestamp / timezone | Not present | No `TIMESTAMP` comparisons or timezone-dependent logic identified. | — |
| SEM-05 | SET-table dedup | **Signal** | There is a single `INSERT INTO wrk_dc_priority` (one statement, no `UNION`/`UNION ALL`). There is **no** `CREATE TABLE` DDL for `wrk_dc_priority` in this file, so SET vs MULTISET cannot be determined. Per the Stage-1 contract: **never assume.** Raise an SME question: *"Is `wrk_dc_priority` a SET table?"* If SET, each INSERT must be ported as `INSERT INTO tgt ( SELECT … EXCEPT SELECT * FROM tgt )`. | SME |
| SEM-06 | Implicit cast / NULL in comparison | Not present | Comparisons use explicit string literals (`'MY'`, `'000'`, `'R'`, etc.); no implicit string↔number casts identified. | — |
| SEM-07 | `NULL` ordering | **Present** | The `QUALIFY` clauses (lines 409, 418, 478) rely on `ORDER BY` where `NULL` values in the sort keys (`sa_priority_no`, `usg_priority_no`, `efast_dt`) could affect which row wins. Snowflake defaults: `NULLS LAST` for ASC, `NULLS FIRST` for DESC. If Teradata used different defaults, the winning row could differ. **TODO(SME):** make `NULLS FIRST/LAST` explicit if the sort key can be NULL. | SME |
| SEM-08 | Empty string vs NULL | **Present** | The `oc_yq_src_cd` CASE (lines 320–356) returns `''` (empty string) in multiple branches (lines 323, 353). In Snowflake, `''` is a real empty string, not NULL. If the Teradata original intended NULL, this is a semantic drift. **TODO(SME):** confirm whether `''` should be `NULL` (or vice versa). | SME |
| SEM-09 | Aggregate of empty set / `SUM` NULL | Not present | No aggregate functions (`SUM`, `COUNT`, etc.) in the SELECT — this is a row-level INSERT. | — |
| SEM-10 | Exchange-rate / lookup join direction | **Present** | Two exchange-rate joins: `sa_curr_to_gbp` (lines 431–435) joins `best_sa.sa_curr_cd = sa_curr_to_gbp.curr_from_cd` and `curr_to_cd = 'GBP'` — alias says "sa currency to GBP," direction is correct. `gbp_to_usg_curr` (lines 437–441) joins `gbp_to_usg_curr.curr_from_cd = best_usg.sa_curr_cd` and `curr_to_cd = 'GBP'` — the alias name says "GBP to usage currency" but the join actually converts **from** `best_usg.sa_curr_cd` **to** GBP (same direction as `sa_curr_to_gbp`). Per `06_lessons_learned.md` (2026-07-23 entry): *"The `gbp_to_usg_curr` alias also targets `curr_to_cd = 'GBP'` — the alias name is misleading but the join is correct. Do **not** 'fix' the alias; it would hide, not solve, and changes nothing."* **TODO(SME):** confirm the alias is misleading but the join direction is correct. | SME |

## 5. Classification summary

| Finding | Rule | Line(s) | Class |
|---|---|---|---|
| `ZEROIFNULL(best_usg.grs_rev_vlu)` | FNX-01 | 164 | AUTO |
| `ZEROIFNULL(best_usg.grs_rev_curr_vlu)` | FNX-01 | 165 | AUTO |
| `bus_efast_pd CONTAINS best_usg.up_dt` (up_ctry_grp) | SFX-01 | 451 | SME |
| `bus_efast_pd CONTAINS best_usg.up_dt` (disch_ctry_grp) | SFX-01 | 456 | SME |
| `LAST_DAY(...) - 3` (yq_vlu CASE) | FNX-03 | 304 | AUTO |
| `LAST_DAY(...) - 3` (oc_yq_src_cd CASE) | FNX-03 | 335 | AUTO |
| `CAST((best_sa.dc_no, 0, 9999999999) AS BIGINT)` ×2 | DEF-04 | 212, 221 | SME |
| `CAST((best_sa.pme_dc_no, 0, 9999999999) AS BIGINT)` ×2 | DEF-04 | 213, 222 | SME |
| `ASallow_piece_qty` | DEF-02 | 177 | FIX |
| `ASallow_weight_qty` | DEF-02 | 178 | FIX |
| `ASallow_weight_unit_cd` | DEF-02 | 179 | FIX |
| Duplicate `sac_cd` in INSERT list | DEF-01 | 80–81 | FIX |
| Duplicate `COALESCE(…) AS sac_cd` in SELECT | DEF-01 | 236–237 | FIX |
| Missing `yq_curr_vlu` SELECT expression | DEF-05 | 94 / (none) | SME |
| Integer division `yq_curr_vlu / ex_rte` | SEM-01 | 270, 286, 305, 307, 315, 344 | SME |
| `QUALIFY` dedup ordering ties | SEM-02 | 409, 418, 478 | SME |
| SET-table dedup (`wrk_dc_priority`) | SEM-05 | 5 | SME |
| `NULL` ordering in `QUALIFY` | SEM-07 | 409, 418, 478 | SME |
| Empty string `''` vs NULL in `oc_yq_src_cd` | SEM-08 | 323, 353 | SME |
| `gbp_to_usg_curr` alias vs join direction | SEM-10 | 437–441 | SME |
| `QUALIFY ROW_NUMBER() OVER (...) = 1` | SFX-03 | 409, 418, 478 | — (keep) |

**Totals:** 3 AUTO, 4 FIX, 10 SME, 1 keep-as-is.

## 6. Table dependency inventory

| Role | Table / alias | Lines | Notes |
|---|---|---|---|
| **Target** | `wrk_dc_priority` | 5 | INSERT target. No DDL supplied — SET vs MULTISET unknown (SEM-05). |
| Source | `wrk_dc_priority_ranked` (alias `best_sa`) | 399–414 | Subquery with `QUALIFY` — picks best sale row per `dc_id, cou_no`. |
| Source | `wrk_dc_priority_ranked` (alias `best_usg`) | 416–427 | Subquery with `QUALIFY` — picks best usage row per `dc_id, cou_no`. |
| Source | `wrk_dc_priority_ranked` (alias `MY_src`) | 429–434 | LEFT JOIN, filtered `src_cd = 'MY'`. |
| Source | `wrkange_rate` (alias `sa_curr_to_gbp`) | 431–435 | Exchange rate: sale currency → GBP. |
| Source | `wrkange_rate` (alias `gbp_to_usg_curr`) | 437–441 | Exchange rate: usage currency → GBP (alias name misleading — SEM-10). |
| Source | `wrkg_loc_hierarchy` (alias `dep_loc_hierarchy`) | 443–445 | Departure station location hierarchy. |
| Source | `wrkg_loc_hierarchy` (alias `arr_loc_hierarchy`) | 447–449 | Arrival station location hierarchy. |
| Source | `ref_ctry` (alias `up_ctry_grp`) | 451–453 | Departure country grouping (`CONTAINS` — SFX-01). |
| Source | `ref_ctry` (alias `disch_ctry_grp`) | 455–457 | Discharge country grouping (`CONTAINS` — SFX-01). |
| Source | `b_dc_tax_remittance_partner` (alias `dtrp`) | 459–462 | Tax remittance partner. |
| Source | `QYtna_burst` (alias `fna`) | 465–471 | Subquery `ty_t5` — burst data. |
| Source | `QYtng` (alias `fng`) | 466–471 | Subquery `ty_t5` — joined to `fna`. |

**Verdict:** The script is a single-row-grain INSERT that assembles the "best"
sale row (`best_sa`) and "best" usage row (`best_usg`) per `dc_id, cou_no`,
enriches with MY-source data, exchange rates, location hierarchies, country
groupings, and tax-remittance partner info, then applies a final `QUALIFY` to
pick the latest exchange-rate row. It **will not run** on Snowflake due to
`ZEROIFNULL` (FNX-01), `CONTAINS` (SFX-01), and the malformed `CAST` (DEF-04).
Even after those are fixed, the column-count mismatch (DEF-05: missing
`yq_curr_vlu`) and the duplicate `sac_cd` (DEF-01) must be resolved. Multiple
semantic risks (SEM-01, SEM-02, SEM-05, SEM-07, SEM-08, SEM-10) require SME
decisions — no Teradata ground truth is available to resolve them automatically.