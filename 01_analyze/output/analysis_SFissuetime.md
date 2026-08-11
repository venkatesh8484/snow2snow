# Stage 1 — Analysis: `SFissuetime.sql`

**Input:** `00_input/SFissuetime.sql` (139 lines)
**Teradata ground truth:** none — no `SFissuetime.teradata.sql` in `00_input/`.
Semantic intent is therefore inferred from sibling columns / naming conventions
and every inference is flagged `TODO(SME)`.
**Reviewer guidance:** none — no `07_review/output/review_SFissuetime.md` exists.
**Archive step:** run `python3 05_report/archive_outputs.py SFissuetime` before
this re-analysis so a re-run starts from a clean slate (no-op if the orchestrator
already archived this unit's outputs). This analysis audits the **buggy input**
as-is; it does not assume any prior fix has been applied.

**Prior-run context (from `02_rules/06_lessons_learned.md`):** extensive prior
runs exist for `SFissuetime.sql`. The 2026-07-25 re-run applied exactly one
mechanical change — DEF-06 alias normalization at SELECT pos 42
(`AS new_sched_departure_date` → `AS new_sched_departure_time`) — and left the
SQL structure unchanged with 11 `TODO(SME)` markers across 5 SEM-* risks. This
audit re-confirms those findings against the current buggy input (the alias is
still `new_sched_departure_date` in `00_input/`, so the defect is still
present in the source).

---

## 1. Column-count check (INSERT target vs SELECT expressions)

| Side | Count | Duplicates | Net |
|---|---|---|---|
| INSERT target columns (lines 3–62) | 60 | none | 60 |
| SELECT expressions (lines 65–131) | 60 | none | 60 |

**Result: 60 = 60 — counts match. No DEF-05 (count mismatch).**

Counting notes:
- The `TO_TIMESTAMP_LTZ( CONCAT(...) , '...' )` block (lines 106–109) is **one**
  expression aliased `AS new_sched_departure_date`.
- The `CASE WHEN ... END` block (lines 127–131) is **one** expression aliased
  `AS change_ind` (the last SELECT item, position 60).

### Position-by-position alias-vs-target-name alignment audit (critical)

INSERT…SELECT is **positional**, so the alias name is cosmetic — the expression
lands in whatever target slot its ordinal position dictates. The mechanical
validator cannot catch a wrong alias because positional binding makes it inert;
this audit is what surfaces DEF-06. Full position-by-position table:

| Pos | INSERT target (line) | SELECT expression (line) | Aligned? |
|---|---|---|---|
| 1 | `old_operating_airline_cd` (4) | `o.operating_airline_cd` (66) | ✅ |
| 2 | `old_operating_flgt_no` (5) | `o.operating_flgt_no` (67) | ✅ |
| 3 | `old_operating_sfx_cd` (6) | `o.operating_sfx_cd` (68) | ✅ |
| 4 | `old_sched_departure_date` (7) | `o.sched_departure_date` (69) | ✅ |
| 5 | `old_gmt_flgt_dt` (8) | `o.gmt_flgt_dt` (70) | ✅ |
| 6 | `old_departure_station` (9) | `o.departure_station` (71) | ✅ |
| 7 | `old_arrival_station` (10) | `o.arrival_station` (72) | ✅ |
| 8 | `old_service_typ` (11) | `o.service_typ` (73) | ✅ |
| 9 | `old_sched_arrival_date` (12) | `o.sched_arrival_date` (74) | ✅ |
| 10 | `old_gmt_flgt_arrival_date` (13) | `o.gmt_flgt_arrival_date` (75) | ✅ |
| 11 | `old_sched_departure_time` (14) | `o.sched_departure_time` (76) | ✅ |
| 12 | `old_sched_arrival_time` (15) | `o.sched_arrival_time` (77) | ✅ |
| 13 | `old_gmt_sched_departure_time` (16) | `o.gmt_sched_departure_time` (78) | ✅ |
| 14 | `old_gmt_sched_arrival_time` (17) | `o.gmt_sched_arrival_time` (79) | ✅ |
| 15 | `old_accounting_year_no` (18) | `o.accounting_year_no` (80) | ✅ |
| 16 | `old_accounting_month_no` (19) | `o.accounting_month_no` (81) | ✅ |
| 17 | `old_accounting_week_no` (20) | `o.accounting_week_no` (82) | ✅ |
| 18 | `old_local_flgt_dt` (21) | `o.local_flgt_dt` (83) | ✅ |
| 19 | `old_iata_ac_typ` (22) | `o.iata_ac_typ` (84) | ✅ |
| 20 | `old_pax_departure_timel_cd` (23) | `o.pax_departure_timel_cd` (85) | ✅ |
| 21 | `old_pax_arrival_timel_cd` (24) | `o.pax_arrival_timel_cd` (86) | ✅ |
| 22 | `old_leg_sequence` (25) | `o.leg_sequence` (87) | ✅ |
| 23 | `old_effective_dt` (26) | `o.effective_dt` (88) | ✅ |
| 24 | `old_expiry_dt` (27) | `o.expiry_dt` (89) | ✅ |
| 25 | `old_opg_flgt_leg_id` (28) | `o.opg_flgt_leg_id` (90) | ✅ |
| 26 | `old_current_rec_ind` (29) | `o.current_rec_ind` (91) | ✅ |
| 27 | `old_carrier_ac_typ` (30) | `o.carrier_ac_typ` (92) | ✅ |
| 28 | `old_dep_utc_variation_txt` (31) | `o.dep_utc_variation_txt` (93) | ✅ |
| 29 | `old_arr_utc_variation_txt` (32) | `o.arr_utc_variation_txt` (94) | ✅ |
| 30 | `old_sched_src_typ` (33) | `o.sched_src_typ` (95) | ✅ |
| 31 | `new_sequence` (34) | `n.sequence` (96) | ✅ |
| 32 | `new_operating_airline_cd` (35) | `n.operating_airline_cd` (97) | ✅ |
| 33 | `new_operating_flgt_no` (36) | `n.operating_flgt_no` (98) | ✅ |
| 34 | `new_operating_sfx_cd` (37) | `n.operating_sfx_cd` (99) | ✅ |
| 35 | `new_sched_departure_date` (38) | `n.sched_departure_date` (100) | ✅ |
| 36 | `new_gmt_flgt_dt` (39) | `n.gmt_flgt_dt` (101) | ✅ |
| 37 | `itinerary_variation_id` (40) | `n.itinerary_variation_id` (102) | ✅ |
| 38 | `new_act_departure_station` (41) | `n.act_departure_station` (103) | ✅ |
| 39 | `new_act_arrival_station` (42) | `n.act_arrival_station` (104) | ✅ |
| 40 | `new_service_typ` (43) | `n.service_typ` (105) | ✅ |
| 41 | `new_sched_arrival_date` (44) | `n.sched_arrival_date` (106) | ✅ |
| **42** | **`new_sched_departure_time`** (45) | **`TO_TIMESTAMP_LTZ(...) AS new_sched_departure_date`** (107–110) | ⚠️ alias lies |
| 43 | `new_sched_arrival_time` (46) | `n.sched_arrival_time` (111) | ✅ |
| 44 | `new_gmt_sched_departure_time` (47) | `n.gmt_sched_departure_time` (112) | ✅ |
| 45 | `new_gmt_sched_arrival_time` (48) | `n.gmt_sched_arrival_time` (113) | ✅ |
| 46 | `marketing_airline_cd` (49) | `n.marketing_airline_cd` (114) | ✅ |
| 47 | `marketing_flgt_no` (50) | `n.marketing_flgt_no` (115) | ✅ |
| 48 | `new_iata_ac_typ` (51) | `n.iata_ac_typ` (116) | ✅ |
| 49 | `new_pax_departure_timel_cd` (52) | `n.pax_departure_timel_cd` (117) | ✅ |
| 50 | `new_pax_arrival_timel_cd` (53) | `n.pax_arrival_timel_cd` (118) | ✅ |
| 51 | `new_leg_sequence` (54) | `n.leg_sequence` (119) | ✅ |
| 52 | `new_effective_dt` (55) | `n.effective_dt` (120) | ✅ |
| 53 | `new_expiry_dt` (56) | `n.expiry_dt` (121) | ✅ |
| 54 | `new_current_rec_ind` (57) | `n.current_rec_ind` (122) | ✅ |
| 55 | `new_carrier_ac_typ` (58) | `n.carrier_ac_typ` (123) | ✅ |
| 56 | `new_dep_utc_variation_txt` (59) | `n.dep_utc_variation_txt` (124) | ✅ |
| 57 | `new_arr_utc_variation_txt` (60) | `n.arr_utc_variation_txt` (125) | ✅ |
| 58 | `new_codeshare_ind` (61) | `n.codeshare_ind` (126) | ✅ |
| 59 | `new_sched_src_typ` (62) | `n.sched_src_typ` (127) | ✅ |
| 60 | `change_ind` (63) | `CASE ... END AS change_ind` (128–132) | ✅ |

The expression at SELECT position 42 is aliased `new_sched_departure_date`, but
position 42 of the INSERT list is `new_sched_departure_time` (line 45). The alias
name matches INSERT position 35 (`new_sched_departure_date`, line 38), which is
already populated by `n.sched_departure_date` (line 100).

**Interpretation:** The expression
`TO_TIMESTAMP_LTZ(CONCAT(TO_DATE(o.sched_departure_date), ' ', n.sched_departure_time), 'YYYY-MM-DD HH24:MI:SS.FF9')`
combines a **date** and a **time** into a **timestamp**. Logically this is a
"departure **time** (as a timestamp)" value, which belongs in
`new_sched_departure_time` (pos 42) — **not** in `new_sched_departure_date`
(pos 35, already a plain date). The positional placement is therefore correct;
only the **alias is a copy-paste error** (DEF-06). This is the most likely
reading, but with no Teradata ground truth the intent cannot be proven — see
SME-Q5.

---

## 2. Syntax errors / residual-Teradata constructs

The file is **clean Snowflake** — it parses and resolves without any SFX/FNX/DTX
fix. No residual Teradata constructs found.

| # | Line(s) | Construct | Rule | Verdict |
|---|---|---|---|---|
| — | — | (none) | — | No `ZEROIFNULL`/`NULLIFZERO`, no `CONTAINS`/`OVERLAPS`, no `SEL`, no `SET`/`MULTISET`, no `PRIMARY INDEX`, no `COLLECT STATS`, no BTEQ, no `LOCKING`, no `(+)`, no `MINUS`, no `TOP`, no `CAST ... FORMAT`. |

Valid Snowflake constructs present (confirmed legal):
- `TO_TIMESTAMP_LTZ(...)` (line 107) — native Snowflake function.
- `TO_DATE(...)` (line 108) — native.
- `CONCAT(...)` (line 108) — native.
- `FULL OUTER JOIN ... ON` (lines 133–140) — ANSI join, valid.
- `CASE WHEN ... IS NULL ...` (lines 128–132) — valid.

**No syntax fixes required.**

---

## 3. Defects (DEF-*)

| # | Line(s) | Defect | Rule | Class | Notes |
|---|---|---|---|---|---|
| D1 | 107–110 | Alias `AS new_sched_departure_date` does not match the INSERT target at its position (`new_sched_departure_time`, line 45). | DEF-06 (alias ≠ target — **not a defect**) | **AUTO** | INSERT…SELECT is positional; the alias is cosmetic. Normalize the alias to `AS new_sched_departure_time` for readability so a reader is not misled into thinking this populates `new_sched_departure_date`. No data change. This is the single mechanical fix applied in the prior 2026-07-25 run. |

No DEF-01 (duplicate column), DEF-02 (whitespace typo), DEF-03 (unbalanced
parens — the `TO_TIMESTAMP_LTZ`/`CONCAT` nesting is balanced), DEF-04
(malformed call), DEF-05 (count mismatch — counts are equal), or DEF-07
(wrong column ref — cannot disprove without ground truth; see SME-Q4).

---

## 4. Semantic risks (SEM-*)

| # | Line(s) | Risk | Rule | Present? | Class | Detail |
|---|---|---|---|---|---|---|
| S1 | 107–110 | `TO_TIMESTAMP_LTZ` returns a timestamp **with local session time zone**. The sibling "old" columns are `old_gmt_sched_departure_time` / `old_gmt_sched_arrival_time` (GMT/UTC), and the "new" side has both `new_sched_departure_time` (this slot) and `new_gmt_sched_departure_time` (pos 44, line 112). Using **LTZ** for the local-time slot is plausibly intended, but the session `TIMEZONE` must be pinned or the stored value drifts. | SEM-04 | Yes | **SME** | Confirm the target column `new_sched_departure_time` is meant to hold a **local-time** timestamp (LTZ) and not NTZ/TZ. Pin session `TIMEZONE`. No ground truth → `TODO(SME)`. |
| S2 | 108 | `CONCAT(TO_DATE(o.sched_departure_date), ' ', n.sched_departure_time)` performs **implicit casts**: `TO_DATE(...)` → string for CONCAT, and `n.sched_departure_time` (likely TIME) → string. If `o.sched_departure_date` is already a DATE, `TO_DATE` is a harmless no-op; if it is a string, `TO_DATE` with no format relies on session defaults. | SEM-06 / DTX-10 | Yes | **SME** | Make casts explicit (`TO_CHAR(TO_DATE(...),'YYYY-MM-DD')`) to remove default-format dependence. Confirm source column types. `TODO(SME)`. |
| S3 | 107–110 | Format mask `'YYYY-MM-DD HH24:MI:SS.FF9'` expects 9-digit fractional seconds (`FF9`). If `n.sched_departure_time` carries no fractional seconds, Snowflake parses leniently, but if it carries a different precision the value may truncate/pad. | SEM-06 | Yes | **SME** | Confirm the precision of `n.sched_departure_time` matches `FF9`, or relax the mask. `TODO(SME)`. |
| S4 | 128–132 | `change_ind` CASE uses `IS NULL` (not empty-string) — correct for NULL detection. | SEM-08 | No | — | `IS NULL` is the right test; no empty-string-vs-NULL hazard. The A/E/U logic (o NULL→'A' add, n NULL→'E' expire, else 'U' update) is a standard SCD-2 diff pattern. |
| S5 | 133–140 | FULL OUTER JOIN keys include `n.act_departure_station = o.departure_station` and `n.act_arrival_station = o.arrival_station`. The "new" side uses `act_*_station` (actual) while the "old" side uses `departure_station`/`arrival_station` (which maps to `old_departure_station`/`old_arrival_station`). Whether `o.departure_station` is the **scheduled** or **actual** station on the old side is not provable without DDL/ground truth. | SEM-10 (join direction / alias) | Yes | **SME** | Confirm the station columns are semantically the same grain on both sides (actual-vs-actual). A scheduled-vs-actual mismatch would silently change the join. `TODO(SME)`. |
| S6 | — | SET-table dedup (multiple INSERTs / UNION into one target). | SEM-05 | No | — | Single `INSERT … SELECT` with a `FULL OUTER JOIN` (no `UNION`/`UNION ALL`, no second INSERT). No SET-table signal. No DDL supplied, but none needed — SEM-05 is not triggered. |
| S7 | — | Integer division. | SEM-01 | No | — | No `/` division in the script. |
| S8 | — | `QUALIFY` / dedup ties. | SEM-02 | No | — | No `QUALIFY` or `ROW_NUMBER`. |
| S9 | — | `CHAR(n)` padding. | SEM-03 | No | — | No `CHAR(n)` comparisons visible (no DDL). |
| S10 | — | `NULL` ordering feeding `QUALIFY`/`TOP`. | SEM-07 | No | — | No `ORDER BY` / `QUALIFY`. |
| S11 | — | Aggregate of empty set. | SEM-09 | No | — | No aggregates. |

---

## 5. Classification summary

| ID | Finding | Rule | Class |
|---|---|---|---|
| D1 | Misleading alias `AS new_sched_departure_date` → normalize to `AS new_sched_departure_time` | DEF-06 | **AUTO** |
| S1 | `TO_TIMESTAMP_LTZ` timezone intent (LTZ vs NTZ/TZ); pin session `TIMEZONE` | SEM-04 | **SME** |
| S2 | Implicit casts in `CONCAT`/`TO_DATE` (make explicit) | SEM-06 / DTX-10 | **SME** |
| S3 | `FF9` format precision vs `n.sched_departure_time` precision | SEM-06 | **SME** |
| S5 | Join key `act_*_station` vs `departure_station`/`arrival_station` semantic grain | SEM-10 | **SME** |

**AUTO:** 1 (cosmetic alias normalize).
**FIX:** 0 (no mechanical defect repair beyond the AUTO alias).
**SME:** 4 (all semantic-intent questions; no ground truth available).

---

## 6. Table dependency inventory

| Role | Table | Alias | Lines |
|---|---|---|---|
| Target (INSERT) | `staging.wrk_synthetic_flgt_leg_ins_exp` | — | 1 |
| Source (old side) | `staging.wrk_synthetic_flgt_source1` | `o` | 133 |
| Source (new side) | `staging.wrk_synthetic_flgt_source2` | `n` | 134 |

Join: `o` FULL OUTER JOIN `n` on airline code, flight no, suffix, scheduled
departure date, and departure/arrival stations (lines 135–140).

---

## 7. Open SME questions (for Stage 3 / Stage 6)

- **SME-Q1 (S1, SEM-04):** Is `new_sched_departure_time` intended to store a
  **local-time** timestamp (`TIMESTAMP_LTZ`)? Should the session `TIMEZONE` be
  pinned? (No ground truth.)
- **SME-Q2 (S2, SEM-06/DTX-10):** What are the source types of
  `o.sched_departure_date` and `n.sched_departure_time`? Should the casts in
  `CONCAT`/`TO_DATE` be made explicit to avoid session-default formatting?
- **SME-Q3 (S3, SEM-06):** Does `n.sched_departure_time` carry 9-digit
  fractional seconds, or should the `FF9` mask be relaxed?
- **SME-Q4 (S5, SEM-10):** Are `n.act_departure_station`/`n.act_arrival_station`
  semantically the same (actual) grain as `o.departure_station`/
  `o.arrival_station`? A scheduled-vs-actual mismatch would change the join.
- **SME-Q5 (D1, DEF-06):** Confirm the `TO_TIMESTAMP_LTZ(...)` expression is
  positionally correct in slot 42 (`new_sched_departure_time`) and only the
  **alias** is wrong (not the position). The logical shape (date + time →
  timestamp) supports this, but without ground truth it is an inference.

---

## 8. Verdict

**PARSE-CLEAN, count-balanced (60=60); 1 cosmetic alias defect (AUTO) + 4
semantic SME questions (timezone, implicit casts, format precision, join-key
grain) — no syntax fix needed.** The single AUTO finding (DEF-06 alias
normalization at SELECT pos 42) is the only mechanical change; all four SME
items await DDL / Teradata ground truth and must not be rewritten without
reviewer confirmation. No `07_review/output/review_SFissuetime.md` exists, so
no reviewer guidance is available to close any SME question on this run.