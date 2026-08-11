# Semantic explanation — `ins_wrk_dc_priority`

**Fixed SQL:** `03_fix/output/ins_wrk_dc_priority_fixed.sql`
**Target table:** `wrk_dc_priority`
**Teradata ground truth:** ❌ not supplied (no `00_input/ins_wrk_dc_priority.teradata.sql`)
**Column count:** 131 INSERT columns ↔ 131 SELECT expressions (after DEF-01 duplicate removal and DEF-05 synthesis)

---

## 1. Purpose

This statement builds the `wrk_dc_priority` work table — one row per
`(dc_id, cou_no)` (document/coupon) — by joining the **best sale-side** and
**best usage-side** records from `wrk_dc_priority_ranked`, enriching them with
the **MY-source** usage row (when present), and attaching currency-exchange
rates, country-grouping lookups, a tax-remittance-partner lookup, and a
`ty_t5` flight-network subquery. The output grain is one prioritized row per
coupon, carrying 131 attributes: revenue/ commission/ surcharge values in both
original currency and GBP, YQ (fuel surcharge) value and source code, coupon
sequence, status flags, and audit/EMD metadata. It is the staging input for
downstream DC (document control) priority processing.

---

## 2. Clause-by-clause walk-through

### 2.1 INSERT target list (131 columns)

The target column list defines the output schema of `wrk_dc_priority`. After
removing the duplicate `sac_cd` (DEF-01, appeared twice at INSERT positions
79–80), the list is 131 columns. Column order is preserved exactly from the
source; aliases were normalized only cosmetically (DEF-06) so each SELECT
expression's alias matches its target column name.

### 2.2 `best_sa` — best sale-side row (subquery + QUALIFY #1)

```sql
SELECT * FROM wrk_dc_priority_ranked
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY dc_id, cou_no ORDER BY sa_priority_no) = 1
```

Picks the single highest-priority **sale** row per `(dc_id, cou_no)`. The
`QUALIFY` is kept as-is (SFX-03 — Snowflake supports `QUALIFY`; no
`ROW_NUMBER` subquery wrap). Ties on `sa_priority_no` are broken
non-deterministically → SEM-02 TODO(SME).

### 2.3 `best_usg` — best usage-side row (subquery + QUALIFY #2)

Same pattern, partitioned by `(dc_id, cou_no)`, ordered by `usg_priority_no`.
Joined `INNER` to `best_sa` on `(dc_id, cou_no)` so only coupons present on
**both** sides survive. Same SEM-02 tiebreaker caveat.

### 2.4 `MY_src` — MY-source usage row (LEFT JOIN)

```sql
LEFT JOIN wrk_dc_priority_ranked MY_src
  ON best_sa.dc_id = MY_src.dc_id
 AND best_sa.cou_no = MY_src.cou_no
 AND MY_src.src_cd = 'MY'
```

Brings in the MY-carrier usage attributes (validity dates, mileage, reroute,
EMD remarks, full-flight station/timestamps) when that source exists for the
coupon; otherwise NULLs. Many SELECT columns `COALESCE(best_sa.x, MY_src.x)` to
fall back across the two.

### 2.5 Exchange-rate joins (`sa_curr_to_gbp`, `gbp_to_usg_curr`)

Two LEFT JOINs to `wrkange_rate`, both filtering `curr_to_cd = 'GBP'` and
`ex_rte_typ = 'I5D'`, keyed on `sa_curr_cd` and bounded by
`curr_cnvrt_dt BETWEEN efast_dt AND exp_dt`. Despite the alias
`gbp_to_usg_curr` (SEM-10), both joins go **to GBP** — the alias is misleading
but the join is correct; it is **not** renamed. These rates convert
`*_curr_vlu` values to GBP inside the `yq_vlu` and `cdshr_comm_curr_vlu` CASEs.

### 2.6 Country-grouping lookups (`dep_loc_hierarchy`, `arr_loc_hierarchy`, `up_ctry_grp`, `disch_ctry_grp`)

Station → country via `wrkg_loc_hierarchy`, then country → `ref_ctry` grouping
(`grouping_typ_txt = 'QY'`). The original Teradata used the PERIOD `CONTAINS`
operator (`bus_efast_pd CONTAINS best_usg.up_dt`); SFX-01 rewrites each as
`best_usg.up_dt BETWEEN bus_efast_pd_start_dt AND bus_efast_pd_end_dt`,
assuming the PERIOD was split into two columns. TODO(SME) confirms the split
column names. These groups feed the EU/AM inter-region YQ-zeroing branch.

### 2.7 `dtrp` — tax remittance partner

`LEFT JOIN b_dc_tax_remittance_partner` on `air_no` and `up_dt >= agmt_start_dt`.
Drives the "remittance window" YQ branch: if `up_dt` is **after**
`LAST_DAY(remittance_received_to_dt) - 3 days` (FNX-03 → `DATEADD('day', -3,
LAST_DAY(...))`), the GBP-converted YQ is used; otherwise YQ is zeroed and
`oc_yq_src_cd = 'R'`.

### 2.8 `ty_t5` — flight-network subquery

Joins `QYtna_burst` ⋈ `QYtng` on `myflightno_grp_cd`, filtered to
`air_des_cd = 'MY'` and `bus_unit_cd IN ('tyR','tyS')`. Used to detect whether
the coupon's operating carrier/flight falls in a known MY network within an
effective date range — gates the "priority 1 with network match" YQ branch.

### 2.9 SELECT expressions — notable CASE blocks

- **`grs_rev_vlu` / `grs_rev_curr_vlu`** — `ZEROIFNULL` (FNX-01) →
  `COALESCE(x, 0)`. Teradata's `ZEROIFNULL` returns 0 for NULL; `COALESCE`
  is the Snowflake equivalent.
- **`cou_seq_no`** — the malformed `CAST((col, 0, 9999999999) AS BIGINT)`
  (DEF-04) was a corrupted `COALESCE` with a leftover range bound. Rebuilt as
  `CAST(COALESCE(col, 0) AS BIGINT)` (4 occurrences across WHEN/THEN). The
  expression computes `(dc_no − pme_dc_no) * 4 + cou_no` and keeps it only when
  the result is between 1 and 16. TODO(SME) on the discarded `9999999999`.
- **`cdshr_comm_curr_vlu`** — MY source keeps original-currency value; non-MY
  multiplies `MY_src.cdshr_comm_vlu * gbp_to_usg_curr.ex_rte`.
- **`cdshr_ind`** — `'Y'` when `opr_cd` and `mktg_cd` are both non-empty and
  differ; else `'N'`. Uses `NULLIF(x, '')` (SEM-08 — empty-string vs NULL).
- **`yq_vlu`** — the largest CASE (9 branches): air_no `'000'` non-MY →
  GBP-converted; air_no `'000'` MY → `MY_src.yq_vlu`; MY with `oc_yq_src_cd='R'`
  → `MY_src.yq_vlu`; MY priority-1 with network match → GBP-converted; MY
  EU↔AM inter-region → 0; MY priority-1 within remittance window and < 1000 →
  GBP-converted; other MY → 0; sale-side `yq_vlu > 0` → GBP-converted;
  usage-side `yq_vlu > 0` → `best_usg.yq_vlu`. Division is decimal/decimal
  (SEM-01 — no truncation risk, kept `/`).
- **`yq_curr_vlu`** — **DEF-05**: this expression was entirely missing from
  the buggy SELECT, breaking the 131≠130 column count. Synthesized as
  `best_sa.yq_curr_vlu` (the original-currency YQ value) to mirror the
  `*_vlu` (GBP) / `*_curr_vlu` (original currency) naming convention used by
  every other value pair. TODO(SME) — confirm against Teradata.
- **`oc_yq_src_cd`** — 5-branch CASE returning `'R'`, `'F'`, or `''` (empty
  string sentinel). SEM-08 TODO(SME): confirm `''` vs NULL intent.
- **`MY_acg_usg_cd`** — `'Y'` if `MY_src.air_no IS NOT NULL`, else `'N'`.

### 2.10 Final dedup — QUALIFY #3

```sql
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY best_sa.dc_id, best_sa.cou_no
  ORDER BY sa_curr_to_gbp.efast_dt DESC NULLS LAST,
           gbp_to_usg_curr.efast_dt DESC NULLS LAST) = 1
```

After all LEFT JOINs (which can multiply rows via the exchange-rate and
country-group tables), this final `QUALIFY` collapses back to one row per
`(dc_id, cou_no)` by picking the most recent exchange-rate effective date.
SEM-07: `NULLS LAST` is made explicit so coupons with no matching exchange
rate (NULL `efast_dt`) do **not** win the pick under `DESC` (Snowflake's
default `NULLS FIRST` for `DESC` would let them win). SEM-02: ties on
`efast_dt` are non-deterministic → TODO(SME).

---

## 3. Semantic checks table

| SEM ID | Risk | Present? | Corrected how? | Equivalent to Teradata? |
|---|---|---|---|---|
| SEM-01 | Integer division | No (decimal/decimal) | Kept `/`; noted only | Yes — no INT/INT truncation |
| SEM-02 | QUALIFY tiebreaker non-determinism | Yes (3 QUALIFYs) | TODO(SME) before each; no unique tiebreaker added | SME — confirm `sa_priority_no`, `usg_priority_no`, `efast_dt` unique per partition |
| SEM-03 | CHAR(n) padding & comparison | Yes (many `*_cd = '000'/'MY'/'R'`) | Not corrected — requires DDL | SME — wrap with `TRIM` if any `*_cd`/`air_no` is `CHAR(n)` |
| SEM-04 | Timestamp / timezone | No | N/A | N/A |
| SEM-05 | SET-table dedup | Not triggered (single INSERT) | Raised as precautionary SME question | SME — is `wrk_dc_priority` a SET table? |
| SEM-06 | Implicit cast / NULL in comparison | Yes (`air_no = '000'`, `… < 1000`) | Not corrected — requires DDL | SME — verify `air_no` type; make casts explicit if numeric |
| SEM-07 | NULL ordering in final QUALIFY | Yes | Made `NULLS LAST` explicit on both `ORDER BY` keys | SME — confirm matches Teradata NULL-ordering assumption |
| SEM-08 | Empty string vs NULL | Yes (`NULLIF(x,'')`, `THEN ''`) | Kept; TODO(SME) on `oc_yq_src_cd` | SME — confirm `''` sentinel intent |
| SEM-09 | Aggregate of empty set / SUM NULL | No | N/A | N/A |
| SEM-10 | Exchange-rate join direction | Yes (`gbp_to_usg_curr` alias) | Kept alias as-is; join verified correct | Yes-with-assumption — do NOT rename alias |

---

## 4. Divergences from the original

| # | Divergence | Justification |
|---|---|---|
| D1 | Duplicate `sac_cd` removed from INSERT and SELECT (DEF-01) | Teradata would error on duplicate INSERT column; removal aligns counts to 131 |
| D2 | `ZEROIFNULL` → `COALESCE(x, 0)` (FNX-01) | Semantic equivalent; `ZEROIFNULL` not defined in Snowflake |
| D3 | PERIOD `CONTAINS` → `BETWEEN start_dt AND end_dt` (SFX-01) | Snowflake has no PERIOD type; assumes PERIOD split into two columns (TODO(SME)) |
| D4 | `LAST_DAY(...) - 3` → `DATEADD('day', -3, LAST_DAY(...))` (FNX-03) | Explicit date arithmetic; same result |
| D5 | `CAST((col, 0, 9999999999) AS BIGINT)` → `CAST(COALESCE(col, 0) AS BIGINT)` (DEF-04) | Original was malformed/unparseable; rebuilt as the intended null-safe cast. The `9999999999` range bound is discarded (TODO(SME)) |
| D6 | Missing `yq_curr_vlu` synthesized as `best_sa.yq_curr_vlu` (DEF-05) | Required to restore 131=131 column alignment; follows `*_curr_vlu` naming convention (TODO(SME)) |
| D7 | Cosmetic alias normalization (DEF-06) | Aliases matched to target column names; positional binding unchanged |
| D8 | `NULLS LAST` made explicit in final QUALIFY (SEM-07) | Prevents NULL exchange-rate rows from winning under `DESC`; **semantic change** flagged TODO(SME) |
| D9 | Ideographic space (U+3000) stripped (S7) | Non-ASCII whitespace rejected by Snowflake parser |

No other intentional behavioral changes. All business logic (CASE branch
order, JOIN keys, column order, `QUALIFY` semantics) is preserved exactly.

---

## 5. Open SME questions

1. **[DEF-04]** The original `CAST((col, 0, 9999999999) AS BIGINT)` discarded a
   `9999999999` argument. Was that a range bound (e.g. `LEAST(col, 9999999999)`)
   or a corrupted artifact? Confirm the rebuilt `CAST(COALESCE(col, 0) AS BIGINT)`
   is correct.
2. **[DEF-05]** Is `best_sa.yq_curr_vlu` the correct expression for the missing
   `yq_curr_vlu` column, or should it derive from `MY_src` / a CASE like
   `yq_vlu` does?
3. **[DEF-06/DEF-07]** Is `alliance_cd → cd` (pos 32) a genuine abbreviation or
   a wrong-column copy-paste?
4. **[DEF-06/DEF-07]** Is `e_rmk_email_addr_txt → emd_rmk_email_addr_txt`
   (pos 81) an abbreviation or a wrong column?
5. **[SFX-01]** Confirm the PERIOD `bus_efast_pd` was split into
   `bus_efast_pd_start_dt` and `bus_efast_pd_end_dt` (both occurrences).
6. **[SEM-02]** Is `sa_priority_no` unique per `(dc_id, cou_no)` in
   `wrk_dc_priority_ranked`? If not, QUALIFY #1 ties are non-deterministic.
7. **[SEM-02]** Is `usg_priority_no` unique per `(dc_id, cou_no)`? Same for
   QUALIFY #2.
8. **[SEM-02]** Is `efast_dt` unique per `(dc_id, cou_no)` within the final
   QUALIFY #3 partition? If two exchange-rate rows share the same `efast_dt`,
   the winner is undefined.
9. **[SEM-03]** Are any `*_cd` / `air_no` columns `CHAR(n)` (blank-padded)? If
   so, `TRIM`/`RTRIM` is needed to preserve Teradata comparison semantics.
10. **[SEM-05]** Is `wrk_dc_priority` a SET table (silent duplicate drop on
    INSERT)? DDL not supplied.
11. **[SEM-06]** Is `air_no` numeric or string? `air_no = '000'` compares to a
    string literal — confirm type and add explicit cast if numeric.
12. **[SEM-07]** Does the explicit `NULLS LAST` in the final QUALIFY match the
    Teradata NULL-ordering assumption for `DESC`?
13. **[SEM-08]** Does `oc_yq_src_cd` intend `''` (empty string) as a sentinel,
    or should it be `NULL`? Same for any `NULLIF(x, '')` usage.
14. **[SEM-10]** Confirm the `gbp_to_usg_curr` join direction (joins **to GBP**)
    is correct despite the misleading alias — kept as-is.
15. **[SEM-01]** Confirm `yq_curr_vlu / ex_rte` operands are both decimal
    (no INT truncation); verify if DDL becomes available.
16. **[DEF-06]** Confirm the cosmetic alias normalizations (`sa_src_cd→sale_src_cd`,
    `cou_no→cpn_no`, `opr_myflight_no→opr_flt_no`, `opr_myflight_sfx_cd→opr_flt_sfx_cd`,
    `ex_to_sa_dt→ex_to_sale_dt`) are purely cosmetic and do not change binding.
17. **[S7]** Confirm no other non-ASCII whitespace remains after the U+3000
    strip.

---

## 6. Inline anchors

```anchors
COALESCE(best_usg.grs_rev_vlu, 0) :: FNX-01: ZEROIFNULL → COALESCE(x,0); 0-for-NULL preserved
COALESCE(best_usg.grs_rev_curr_vlu, 0) :: FNX-01: ZEROIFNULL → COALESCE(x,0)
CAST(COALESCE(best_sa.dc_no, 0) AS BIGINT) :: DEF-04: malformed CAST((col,0,9999999999)) rebuilt as CAST(COALESCE(col,0)); 9999999999 discarded (SME)
best_sa.yq_curr_vlu AS yq_curr_vlu :: DEF-05: missing yq_curr_vlu synthesized as best_sa.yq_curr_vlu per *_curr_vlu convention (SME)
THEN '' :: SEM-08: empty-string sentinel in oc_yq_src_cd — confirm '' vs NULL intent (SME)
best_usg.up_dt BETWEEN up_ctry_grp.bus_efast_pd_start_dt AND up_ctry_grp.bus_efast_pd_end_dt :: SFX-01: PERIOD CONTAINS → BETWEEN split cols; confirm split names (SME)
best_usg.up_dt BETWEEN disch_ctry_grp.bus_efast_pd_start_dt AND disch_ctry_grp.bus_efast_pd_end_dt :: SFX-01: PERIOD CONTAINS → BETWEEN split cols (SME)
DATEADD('day', -3, LAST_DAY(dtrp.remittance_received_to_dt)) :: FNX-03: LAST_DAY()-3 → DATEADD('day',-3,LAST_DAY())
QUALIFY ROW_NUMBER() OVER (
            PARTITION BY dc_id, cou_no
            ORDER BY sa_priority_no
        ) = 1 :: SEM-02: best_sa dedup — sa_priority_no tiebreaker non-unique (SME)
QUALIFY ROW_NUMBER() OVER (
            PARTITION BY dc_id, cou_no
            ORDER BY usg_priority_no
        ) = 1 :: SEM-02: best_usg dedup — usg_priority_no tiebreaker non-unique (SME)
QUALIFY ROW_NUMBER() OVER (
            PARTITION BY best_sa.dc_id, best_sa.cou_no
            ORDER BY sa_curr_to_gbp.efast_dt DESC NULLS LAST,
                     gbp_to_usg_curr.efast_dt DESC NULLS LAST
        ) = 1 :: SEM-07: NULLS LAST made explicit (SME); SEM-02: efast_dt tiebreaker non-unique (SME)
LEFT JOIN wrkange_rate gbp_to_usg_curr :: SEM-10: misleading alias — joins TO GBP; kept as-is, do NOT rename
best_usg.alliance_cd              AS cd :: DEF-06/DEF-07: alliance_cd→cd abbreviation or wrong column? (SME)
MY_src.e_rmk_email_addr_txt       AS emd_rmk_email_addr_txt :: DEF-06/DEF-07: e_rmk→emd_rmk abbreviation or wrong column? (SME)
```