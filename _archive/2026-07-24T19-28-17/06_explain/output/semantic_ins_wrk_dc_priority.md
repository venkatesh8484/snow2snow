# Semantic explanation — `ins_wrk_dc_priority`

**Fixed file:** `03_fix/output/ins_wrk_dc_priority_snowflake_fixed.sql`
**Ground truth:** `../teradata2snowflake/00_input/ins_wrk_dc_priority.bteq`

## 1. Purpose

This statement populates the working table **`wrk_dc_priority`** — one row per
**document/coupon** (`dc_id`, `cou_no`) — by reconciling three views of the same
coupon drawn from `wrk_dc_priority_ranked`: the best **sale** record
(`best_sa`), the best **usage** record (`best_usg`), and the **MY** source
record (`MY_src`). It enriches each coupon with currency-converted revenue and
YQ (carrier-imposed surcharge) values, code-share flags, and flight/station
attributes, then keeps exactly one final row per coupon. In business terms: *for
every coupon, pick the authoritative sale and usage rows, compute its GBP and
original-currency money values under the airline's YQ rules, and stage it for
downstream revenue accounting.*

## 2. Clause-by-clause walk-through

**The three ranked sub-selects (`best_sa`, `best_usg`, `MY_src`).** Each wraps
`wrk_dc_priority_ranked` and uses `QUALIFY ROW_NUMBER() OVER (PARTITION BY
dc_id, cou_no ORDER BY …) = 1` to keep the single best row per coupon —
`best_sa` orders by `sa_priority_no`, `best_usg` by `usg_priority_no`. QUALIFY
is native to Snowflake, so this is kept verbatim; the buggy input already had it
right and we did **not** rewrite it into a ROW_NUMBER subquery (minimal diff).

**Revenue columns (`grs_rev_vlu`, `grs_rev_curr_vlu`).** The delivered file wrote
`ZEROIFNULL(best_usg.grs_rev_vlu)`. `ZEROIFNULL` is a Teradata function and does
not resolve on Snowflake, so the statement failed before it could run. We
replaced it with `COALESCE(best_usg.grs_rev_vlu, 0)`, which is the exact
semantic equivalent — a NULL gross-revenue value becomes 0, everything else is
unchanged.

**`cou_seq_no` CASE.** Computes a coupon sequence number as
`(dc_no − pme_dc_no) * 4 + cou_no`, emitted only when it lands in `1..16`, else
NULL. The delivered file corrupted this into
`CAST((best_sa.dc_no, 0, 9999999999) AS BIGINT)` with unbalanced parentheses —
the single reason the file would not parse. Read against the Teradata original,
the evident intent is `CAST(COALESCE(dc_no, 0) AS BIGINT)`; the stray
`9999999999` is a leftover range bound, dropped and flagged `TODO(SME)`. The
arithmetic and the `BETWEEN 1 AND 16` gate are otherwise preserved exactly.

**`yq_vlu` CASE (9 branches) and `oc_yq_src_cd` CASE (4 branches).** These encode
the airline's YQ surcharge policy: zero-airline handling (`air_no = '000'`),
MY-operated carriage, tax-remittance-partner windows, EU↔AM class exemptions,
and priority/date thresholds. Every branch and its order is preserved from the
Teradata source. Inside two branches the delivered file kept Teradata date
arithmetic `LAST_DAY(x) − 3`; we standardized it to
`DATEADD('day', -3, LAST_DAY(x))`, which is identical in meaning but explicit and
safe inside the surrounding expression. The division `yq_curr_vlu /
sa_curr_to_gbp.ex_rte` converts to GBP; both operands are decimal, so there is
**no** integer-truncation risk (SEM-01) — confirmed against the original.

**`yq_curr_vlu` (synthesized).** The delivered SELECT had no expression for the
target column `yq_curr_vlu`, causing the 131-vs-132 count mismatch. Following the
codebase convention (`*_vlu` = GBP, `*_curr_vlu` = original currency), we
synthesized `COALESCE(best_sa.yq_curr_vlu, best_usg.yq_curr_vlu)` and flagged it
`TODO(SME)` for the exact business rule.

**PERIOD lookups on `ref_ctry` (`up_ctry_grp`, `disch_ctry_grp`).** The delivered
file kept the Teradata predicate `bus_efast_pd CONTAINS best_usg.up_dt`.
`CONTAINS` is a PERIOD operator that does not exist in Snowflake. Assuming the
DDL migration split the PERIOD column into `bus_efast_start_dt` /
`bus_efast_end_dt`, we rewrote it as
`best_usg.up_dt BETWEEN bus_efast_start_dt AND bus_efast_end_dt` — the same
"is this date inside the effective period" test. Column names are assumed →
`TODO(SME)`.

**Exchange-rate joins (`sa_curr_to_gbp`, `gbp_to_usg_curr`).** Both join
`wrkange_rate` to `curr_to_cd = 'GBP'`. The alias `gbp_to_usg_curr` reads as if
it converts *to USG currency*, but it too targets GBP. Checked against the
Teradata original, **the join is correct** — the alias is merely misleadingly
named. Per SEM-10 we deliberately did **not** "fix" the alias: renaming would
change nothing at runtime and could disguise a genuine future bug.

**Final `QUALIFY`.** After all joins, a last
`QUALIFY ROW_NUMBER() OVER (PARTITION BY dc_id, cou_no ORDER BY
sa_curr_to_gbp.efast_dt DESC, gbp_to_usg_curr.efast_dt DESC) = 1` collapses the
fan-out from the rate joins to one row per coupon, preferring the most recent
effective rate. Order fully determines the winner, so the dedup is deterministic
(SEM-02).

## 3. Semantic checks

| Rule | Risk | Present? | How handled | Equivalent to Teradata? |
|---|---|---|---|---|
| SEM-01 | Integer-division truncation | No | Operands are decimal; `/` kept | ✅ Yes |
| SEM-02 | Dedup tie-break determinism | Low | `ORDER BY` fully orders each partition | ✅ Yes |
| SEM-03 | CHAR blank-padding | No | Joins are on codes, no padding-sensitive `=` | ✅ Yes |
| SEM-04 | Timestamp / TZ | N/A | No TIMESTAMP arithmetic in this statement | ✅ Yes |
| SEM-10 | Misleading join alias | Yes | Verified correct; alias intentionally kept | ✅ Yes |
| — (FNX-01) | NULL→0 revenue | Yes | `ZEROIFNULL`→`COALESCE(x,0)` | ✅ Yes |
| — (SFX-01) | PERIOD membership | Yes | `CONTAINS`→`BETWEEN` on split cols | ⚠️ Yes, assuming column names |

## 4. Divergences from the original

None intended to change results. All differences are dialect corrections
(FNX-01, SFX-01, FNX-03) or defect repairs (D1–D6). The only values that are not
provably identical are the two `TODO(SME)` synthesized/assumed items (D3
constant, D4 `yq_curr_vlu`), which await SME confirmation.

## 5. Open SME questions

1. **`cou_seq_no` constant** — was `9999999999` a real range cap, or (as
   assumed) a corruption artifact to drop?
2. **`yq_curr_vlu`** — confirm the business rule for original-currency YQ; the
   synthesized `COALESCE(best_sa…, best_usg…)` is a best-guess from the
   `*_curr_vlu` pattern.
3. **`ref_ctry` PERIOD split** — confirm the migrated DDL column names
   (`bus_efast_start_dt` / `bus_efast_end_dt`).

## 6. Inline anchors (drive the SQL comments — edit freely)

`annotate.py` reads this section and injects each note as a `-- SEM ▸` comment
**above the first SQL line that contains the MATCH text**. This is the
reviewer-editable control surface: change a note, add a row, or delete one, then
re-run the annotate step (or the VS Code task) to refresh the comments inside
`…_final.sql`. Keep the ` :: ` separator. Lines starting with `#` are ignored.

```anchors
ORDER BY sa_priority_no :: best_sa = the single best SALE row per coupon (QUALIFY ROW_NUMBER, native on Snowflake).
ORDER BY usg_priority_no :: best_usg = the single best USAGE row per coupon.
COALESCE(best_usg.grs_rev_vlu, 0) :: Revenue: NULL gross revenue -> 0. Was Teradata ZEROIFNULL (FNX-01), identical meaning.
END AS cou_seq_no :: cou_seq_no = (dc_no - pme_dc_no)*4 + cou_no, emitted only within 1..16. Rebuilt from a corrupted CAST (DEF-03/04). TODO(SME): confirm the 9999999999 constant.
END AS yq_vlu :: YQ surcharge policy (9 branches): zero-airline, MY-operated, remittance windows, EU<->AM class exemptions. All branches & order preserved from Teradata. Division is decimal/decimal, no truncation (SEM-01).
AS yq_curr_vlu :: Synthesized: source SELECT had no expression here (DEF-05). *_vlu=GBP, *_curr_vlu=original currency. TODO(SME): confirm the business rule.
END AS oc_yq_src_cd :: YQ source code (4 branches) mirroring the yq_vlu decision tree.
up_ctry_grp.bus_efast_start_dt :: PERIOD lookup: "is up_dt inside the country-group effective period?" Was Teradata PERIOD CONTAINS (SFX-01). TODO(SME): confirm split column names.
LEFT JOIN wrkange_rate gbp_to_usg_curr :: NOTE: this alias reads as "to USG currency" but also targets GBP. Verified correct vs Teradata (SEM-10) — deliberately NOT renamed.
PARTITION BY best_sa.dc_id, best_sa.cou_no :: Final dedup: collapse the rate-join fan-out to the newest effective rate, one row per coupon. Deterministic (SEM-02).
```

