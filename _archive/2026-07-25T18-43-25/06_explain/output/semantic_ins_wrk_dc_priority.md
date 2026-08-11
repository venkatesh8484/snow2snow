# Stage 6 — Semantic explanation: `ins_wrk_dc_priority`

**Fixed SQL:** `03_fix/output/ins_wrk_dc_priority_fixed.sql`
**Teradata ground truth:** None (no `ins_wrk_dc_priority_snowflake.teradata.sql` in `00_input/`). Semantic intent inferred from the SQL, naming conventions, and `02_rules/06_lessons_learned.md`. Every inference is flagged `TODO(SME)`.

---

## 1. Purpose

This script builds the priority-ranked coupon/work table `wrk_dc_priority` by selecting, for each document/coupon pair `(dc_id, cou_no)`, the **best sales (SA) record** and the **best usage (USG) record** from `wrk_dc_priority_ranked`, joining them with the **MY-source record** (`src_cd = 'MY'`), the applicable **exchange rates** (SA-currency → GBP), **station→country location hierarchies**, **country groupings** (for EU/AM routing logic), the **remittance partner** by air number, and a **flight-network subquery** (`ty_t5`, air destination `'MY'`). It then derives coupon-sequence numbers, codeshare indicators, YQ (yield/fee) values and source codes, and a final set of COALESCE picks between USG/SA/MY column values. The grain is **one row per `(dc_id, cou_no)`** after a final dedup that keeps the row whose exchange rate has the latest effective date (`efast_dt DESC NULLS LAST`).

---

## 2. Clause-by-clause walk-through

### 2.1 The three QUALIFY subqueries

- **`best_sa`** — `SELECT * FROM wrk_dc_priority_ranked QUALIFY ROW_NUMBER() OVER (PARTITION BY dc_id, cou_no ORDER BY sa_priority_no) = 1`. Picks the single highest-priority **sales** row per `(dc_id, cou_no)`; `sa_priority_no` ranks competing SA rows. Ties on `sa_priority_no` are non-deterministic (SEM-02, `TODO(SME)`).
- **`best_usg`** — same pattern, `ORDER BY usg_priority_no`. Picks the single highest-priority **usage** row per `(dc_id, cou_no)`. Same tie risk (SEM-02).
- **`MY_src`** — `LEFT JOIN wrk_dc_priority_ranked MY_src ON … AND MY_src.src_cd = 'MY'`. Not a QUALIFY; it is a plain LEFT JOIN that brings in the MY-source row (if any) for the same `(dc_id, cou_no)`. Because it is a LEFT JOIN, all MY-derived columns may be NULL when no MY row exists.

### 2.2 The INNER JOIN of best_sa and best_usg

`best_sa INNER JOIN best_usg ON dc_id, cou_no`. This restricts the output to `(dc_id, cou_no)` pairs that have **both** a best SA row and a best USG row. Pairs with only one side are dropped — this is the intended grain (a coupon must have both a sales and a usage record to be eligible).

### 2.3 The LEFT JOINs

- **`sa_curr_to_gbp`** (`wrkange_rate`) — joins `best_sa.sa_curr_cd = curr_from_cd`, `curr_to_cd = 'GBP'`, `ex_rte_typ = 'I5D'`, and `best_usg.curr_cnvrt_dt BETWEEN efast_dt AND exp_dt`. Supplies the exchange rate used to convert SA-currency YQ values into GBP. The `BETWEEN` on the currency-conversion date selects the rate effective on that date.
- **`gbp_to_usg_curr`** (`wrkange_rate`) — **SEM-10**: the alias reads "GBP to USG currency" but the join is identical in direction to `sa_curr_to_gbp` (joins **to** GBP). The alias is misleading but the join is correct against the Teradata source; it is **not renamed**. It supplies a second GBP rate used in the `cdshr_comm_curr_vlu` CASE (`MY_src.cdshr_comm_curr_vlu * gbp_to_usg_curr.ex_rte`) and as a secondary `ORDER BY` key in the final QUALIFY.
- **`dep_loc_hierarchy` / `arr_loc_hierarchy`** (`wrkg_loc_hierarchy`) — map `best_usg.up_stn_cd` and `best_usg.dsg_stn_cd` to `country_cd`, feeding the country-group joins.
- **`up_ctry_grp` / `disch_ctry_grp`** (`ref_ctry`) — country groupings for the EU/AM routing logic in the `yq_vlu` CASE. **SFX-01**: the original Teradata `PERIOD CONTAINS best_usg.up_dt` was rewritten as `best_usg.up_dt BETWEEN bus_efast_pd_start_dt AND bus_efast_pd_end_dt` on split columns. The split column names are inferred (`TODO(SME)`).
- **`dtrp`** (`b_dc_tax_remittance_partner`) — remittance partner by `best_usg.air_no`, with `best_usg.up_dt >= dtrp.agmt_start_dt`. Drives the remittance-related branches of the `yq_vlu` and `oc_yq_src_cd` CASEs (the `DATEADD('day', -3, LAST_DAY(dtrp.remittance_received_to_dt))` threshold).
- **`ty_t5`** — inline subquery joining `QYtna_burst fna` and `QYtng fng` on `myflightno_grp_cd`, filtered to `air_des_cd = 'MY'` and `bus_unit_cd IN ('tyR','tyS')`. Joined on `best_usg.opr_cd = ty_t5.air_des_cd` and `best_usg.opr_myflight_no = ty_t5.myflight_no` with a date-range `BETWEEN`. Supplies `air_des_cd` used in the `yq_vlu` and `oc_yq_src_cd` CASEs to detect MY-routed flights.

### 2.4 The `cou_seq_no` CASE

Computes `(dc_no − pme_dc_no) * 4 + cou_no`, emitted only when the result is `BETWEEN 1 AND 16`; otherwise NULL. This encodes a sequential coupon position derived from the document-number offset times four plus the coupon number — a compact 1–16 coupon-sequence key. **DEF-04**: the original `CAST((best_sa.dc_no, 0, 9999999999) AS BIGINT)` was a corrupted `COALESCE(col, 0)` with a leftover range-bound constant; it is rebuilt as `CAST(COALESCE(best_sa.dc_no, 0) AS BIGINT)` (and likewise for `pme_dc_no`). The `9999999999` constant is assumed to be a range bound, not semantically meaningful (`TODO(SME)`).

### 2.5 The `cdshr_ind` CASE

Codeshare indicator: `'Y'` when `best_usg.opr_cd` (operating carrier) and `best_sa.mktg_cd` (marketing carrier) are both non-empty (`NULLIF(x, '') IS NOT NULL`) **and** differ (`best_sa.mktg_cd <> best_usg.opr_cd`); otherwise `'N'`. This detects coupons where the operating and marketing carriers differ — the textbook codeshare signal.

### 2.6 The `yq_vlu` CASE (multi-branch YQ value)

Walks the branches in order (first match wins):

1. **`air_no = '000'` and USG is not MY** → `best_sa.yq_curr_vlu / sa_curr_to_gbp.ex_rte`. The "000" air number is a synthetic/internal document; the YQ value is the SA original-currency value converted to GBP.
2. **`air_no = '000'` (USG is MY)** → `MY_src.yq_vlu`. For MY usage of an internal document, take the MY-source YQ value directly.
3. **USG is MY and `MY_src.oc_yq_src_cd = 'R'`** → `MY_src.yq_vlu`. When the MY source already classifies the YQ as remittance (`'R'`), defer to its value.
4. **USG is MY, `ty_t5.air_des_cd` is present, and `sa_priority_no = 1`** → `best_sa.yq_curr_vlu / sa_curr_to_gbp.ex_rte`. MY-routed flight with a primary SA row: convert the SA YQ to GBP.
5. **USG is MY, booking class in `('Z','U','P','X')`, and EU↔AM routing** → `0`. Specific fare-class/route combination zeroes out the YQ.
6. **USG is MY, `sa_priority_no = 1`, remittance partner present, `up_dt` within 3 days after the remittance period end, and converted YQ < 1000** → `best_sa.yq_curr_vlu / sa_curr_to_gbp.ex_rte`. A remittance-window branch that uses the converted SA YQ when it is under a 1000 threshold.
7. **USG is MY (catch-all)** → `0`. Default MY YQ is zero.
8. **`best_sa.yq_vlu > 0`** → `best_sa.yq_curr_vlu / sa_curr_to_gbp.ex_rte`. Non-MY with positive SA YQ: convert to GBP.
9. **`best_usg.yq_vlu > 0`** → `best_usg.yq_vlu`. Fallback to the USG YQ value when SA has none.

All divisions are decimal/decimal (currency value ÷ exchange rate), so **SEM-01** carries no truncation risk. The `DATEADD('day', -3, LAST_DAY(...))` expressions are the FNX-03 standardization of the original `LAST_DAY(...) - 3`.

### 2.7 The `oc_yq_src_cd` CASE (YQ source classification)

Returns `'R'` (remittance), `'F'` (fee), or `''` (empty string):

1. **`air_no = '000'`** → `''`.
2. **USG is MY and `MY_src.oc_yq_src_cd = 'R'`** → `'R'`.
3. **USG is MY, `ty_t5.air_des_cd` IS NULL, remittance partner present, `up_dt` on/before the 3-days-before remittance end** → `'R'`.
4. **USG is MY, `sa_priority_no = 1`, remittance partner present, converted YQ < 1000** → `'F'`.
5. **ELSE** → `''`.

**SEM-08**: several branches return `''` (empty string), not NULL. Snowflake treats `''` as a real empty string; whether Teradata intended `''` vs NULL is unconfirmed (`TODO(SME)`).

### 2.8 COALESCE patterns (USG / SA / MY picks)

Throughout the SELECT, columns that may exist on more than one source row are resolved with `COALESCE` in a consistent precedence:

- `COALESCE(MY_src.x, best_sa.x)` for `assoc_dc_id`, `assoc_cou_no` — MY first, then SA.
- `COALESCE(best_usg.x, MY_src.x)` for `surface_ind`, `dir_cd`, `sac_cd` — USG first, then MY.
- `COALESCE(best_sa.x, MY_src.x)` for the `sa_opr_*`, `sa_up_*`, `sa_dsg_stn_cd`, `sa_cab_cd` block — SA first, then MY.

This reflects the business rule that the most authoritative source varies by attribute: usage attributes come from USG, sales attributes from SA, and MY attributes fill gaps where the MY record is the system of record.

### 2.9 The final QUALIFY (dedup by exchange-rate date)

```
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY best_sa.dc_id, best_sa.cou_no
    ORDER BY sa_curr_to_gbp.efast_dt DESC NULLS LAST,
             gbp_to_usg_curr.efast_dt DESC NULLS LAST
) = 1
```

After all joins, a single `(dc_id, cou_no)` may have multiple candidate rows (e.g., multiple matching exchange-rate rows). This QUALIFY keeps the one with the **latest** `sa_curr_to_gbp.efast_dt`, breaking ties on `gbp_to_usg_curr.efast_dt`. **SEM-07**: `NULLS LAST` is made explicit so that rows with no matching exchange rate (NULL `efast_dt` from the LEFT JOINs) do not win the pick under Snowflake's default `NULLS FIRST` for `DESC`. **SEM-02**: the tiebreaker is not guaranteed unique (`TODO(SME)`).

### 2.10 DEF-05 synthesized `yq_curr_vlu`

The original SELECT was missing the `yq_curr_vlu` expression at INSERT position 84 (after dedup of the duplicate `sac_cd`, INSERT had 131 columns vs SELECT 130). Per the `*_vlu` (GBP value) / `*_curr_vlu` (original-currency value) naming convention in `06_lessons_learned.md`, the most plausible synthesis is `best_sa.yq_curr_vlu` — the original-currency YQ value from the SA row, mirroring how `yq_vlu` is built from `best_sa.yq_curr_vlu / ex_rte`. This is flagged `TODO(SME)` for confirmation against the Teradata source.

---

## 3. Semantic checks table

| SEM ID | Risk | Present? | Corrected how? | Equivalent to Teradata? |
|---|---|---|---|---|
| SEM-01 | Integer division truncation | **Present — no risk.** `best_sa.yq_curr_vlu / sa_curr_to_gbp.ex_rte` is decimal/decimal (currency ÷ rate). | Not corrected (no correction needed). Kept `/`. | **Yes** — decimal/decimal, no truncation. |
| SEM-02 | QUALIFY tie-breaking | **Present.** Three `QUALIFY ROW_NUMBER() … = 1` clauses; none has a unique tiebreaker per partition. | Not corrected — `TODO(SME)` added before each QUALIFY. | **SME** — confirm `sa_priority_no`, `usg_priority_no`, and `efast_dt` are unique per partition. |
| SEM-03 | CHAR(n) padding & comparison | **Not present.** No explicit `CHAR(n)` comparisons in predicates/joins. | N/A | N/A |
| SEM-04 | Timestamp / timezone | **Not present.** No `TIMESTAMP` type declarations or TZ-dependent functions. | N/A | N/A |
| SEM-05 | SET-table dedup | **Not present.** Single `INSERT INTO`; no `UNION`/`UNION ALL` into one target; no `CREATE TABLE` DDL supplied. | N/A | N/A |
| SEM-06 | Implicit cast / NULL | **Low.** The malformed `CAST((col,0,999…) AS BIGINT)` (DEF-04) involved implicit casting; resolved by the explicit `CAST(COALESCE(col, 0) AS BIGINT)` rebuild. | Corrected via DEF-04. | **Yes** (with DEF-04 assumption). |
| SEM-07 | NULL ordering in QUALIFY ORDER BY | **Present.** Final QUALIFY orders by LEFT-JOIN-derived `efast_dt` columns that can be NULL. | **Corrected** — `NULLS LAST` made explicit on both `ORDER BY` keys. | **Yes-with-assumption** — `TODO(SME)` to confirm NULLS LAST matches Teradata NULL ordering. |
| SEM-08 | Empty string vs NULL | **Present.** `oc_yq_src_cd` returns `''` in several branches; `NULLIF(x, '')` used in `cdshr_ind`. | Not corrected — `TODO(SME)` added. | **SME** — confirm `''` (empty string) vs NULL intent. |
| SEM-09 | Aggregate of empty set / SUM NULL | **Not present.** No bare `SUM`/`AVG` over potentially empty sets without COALESCE. | N/A | N/A |
| SEM-10 | Exchange-rate / lookup join direction (misleading alias) | **Present.** `gbp_to_usg_curr` alias joins to GBP (same direction as `sa_curr_to_gbp`). | **NOT corrected** — alias kept as-is; join is correct. Do NOT rename. | **Yes** — join correct; alias cosmetic. |

---

## 4. Divergences from the original

All changes are **mechanical** (parse-error / defect repairs) and do **not** alter the semantic intent:

| Rule | Change | Semantic impact |
|---|---|---|
| FNX-01 | `ZEROIFNULL(x)` → `COALESCE(x, 0)` (×2, `grs_rev_vlu`, `grs_rev_curr_vlu`) | None — identical semantics. |
| SFX-01 | `PERIOD CONTAINS` → `BETWEEN` on split columns `bus_efast_pd_start_dt` / `bus_efast_pd_end_dt` (×2) | None, **pending SME** on split column names. |
| FNX-03 | `LAST_DAY(...) - 3` → `DATEADD('day', -3, LAST_DAY(...))` (×2) | None — identical date arithmetic. |
| DEF-01 | Removed duplicate `sac_cd` from INSERT and SELECT lists | None — removes a positional duplicate. |
| DEF-02 | `ASallow_*` → `AS allow_*` (×3, added whitespace) | None — fixes a parse typo. |
| DEF-04 | `CAST((col, 0, 9999999999) AS BIGINT)` → `CAST(COALESCE(col, 0) AS BIGINT)` (×4) | None, **pending SME** on the `9999999999` constant. |
| DEF-05 | Synthesized missing `yq_curr_vlu` as `best_sa.yq_curr_vlu` | **Pending SME** — inferred from naming convention. |
| DEF-06 | Normalized 7 aliases to INSERT target names (cosmetic) | None — INSERT…SELECT is positional. |
| SEM-07 | Made `NULLS LAST` explicit in final QUALIFY `ORDER BY` | **Pending SME** — may change which row wins if Teradata defaulted differently. |

No residual Teradata constructs remain (`ZEROIFNULL`, `CONTAINS`, `MULTISET`, `(+)`, BTEQ, `MINUS`, `SEL` — all absent). `QUALIFY` is retained (SFX-03).

---

## 5. Open SME questions

1. **SFX-01** — Confirm the split column names `bus_efast_pd_start_dt` / `bus_efast_pd_end_dt` for `ref_ctry` are correct (the original `PERIOD CONTAINS` was split into a `BETWEEN` range).
2. **DEF-05** — Confirm the synthesized `yq_curr_vlu` expression `best_sa.yq_curr_vlu` matches the Teradata source (original-currency YQ value from the SA row).
3. **SEM-02** — Confirm the `ORDER BY` columns in all three QUALIFY clauses (`sa_priority_no`, `usg_priority_no`, `efast_dt`) are unique per `(dc_id, cou_no)` partition; if not, add a deterministic tiebreaker.
4. **SEM-07** — Confirm `NULLS LAST` matches the Teradata NULL-ordering assumption for the final QUALIFY (rows with no matching exchange rate should not win the pick).
5. **SEM-08** — Confirm `oc_yq_src_cd` branches that return `''` (empty string) are intended vs NULL in Teradata.
6. **DEF-04** — Confirm the `9999999999` constant in the original `CAST((col, 0, 9999999999) AS BIGINT)` was a range bound / artifact, not semantically meaningful.

---

## 6. Inline anchors

```anchors
INSERT INTO wrk_dc_priority :: Purpose: priority-ranked coupon/work table, one row per (dc_id, cou_no) after exchange-rate-date dedup.
QUALIFY ROW_NUMBER() OVER ( :: SEM-02: QUALIFY tie-breaking — confirm ORDER BY columns are unique per partition.
CAST(COALESCE(best_sa.dc_no, 0) AS BIGINT) :: DEF-04: Rebuilt from corrupted CAST((col,0,9999999999)) — confirm 9999999999 was a range bound.
best_usg.up_dt BETWEEN up_ctry_grp.bus_efast_pd_start_dt :: SFX-01: PERIOD CONTAINS replaced with BETWEEN on split columns — confirm names.
DATEADD('day', -3, LAST_DAY(dtrp.remittance_received_to_dt)) :: FNX-03: date−int standardized to DATEADD.
best_sa.yq_curr_vlu AS yq_curr_vlu :: DEF-05: Synthesized missing yq_curr_vlu expression — confirm against Teradata.
ORDER BY sa_curr_to_gbp.efast_dt DESC NULLS LAST :: SEM-07: NULLS LAST made explicit — confirm matches Teradata.
gbp_to_usg_curr :: SEM-10: Misleading alias (joins to GBP) — join correct, do NOT rename.
```