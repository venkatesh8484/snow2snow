
-- <<< SEMANTIC EXPLANATION (generated from 06_explain — edit the .md, not here)
-- Source of truth: 06_explain/output/semantic_SFissuetime.md
--
-- PURPOSE
-- This statement is a **before/after (old/new) diff of flight-leg records** that
-- produces an insertion-expiration tracking table. It `INSERT`s into
-- `staging.wrk_synthetic_flgt_leg_ins_exp` the result of a `FULL OUTER JOIN`
-- between two synthetic flight-leg sources: `staging.wrk_synthetic_flgt_source1`
-- (the "old" side, alias `o`) and `staging.wrk_synthetic_flgt_source2` (the
-- "new" side, alias `n`). The FULL OUTER JOIN captures every flight leg that
-- exists in *either* source — legs present only on the old side, only on the new
-- side, or on both. A trailing `change_ind` CASE classifies each output row as
-- **A (add)** when the old side is NULL, **E (expire)** when the new side is
-- NULL, or **U (update)** when both sides are present — a standard slowly-
-- changing-dimension diff pattern. The grain of one output row is **one matching
-- flight leg**: operating airline code + flight number + suffix + scheduled
-- departure date + departure station + arrival station. The 60-column target
-- holds 30 `old_*` attributes from `o`, 29 `new_*` attributes from `n`, and the
-- single `change_ind` classifier.
--
-- ---
--
-- OPEN SME QUESTIONS
-- Each is phrased as a decision the reviewer must make. All stem from the
-- absence of a Teradata ground truth and/or DDL.
--
-- - **SME-Q1 (SEM-04):** Is `new_sched_departure_time` intended to store a
--    **local-time** timestamp (`TIMESTAMP_LTZ`), as opposed to `TIMESTAMP_NTZ` or
--    `TIMESTAMP_TZ`? If LTZ is correct, should the session `TIMEZONE` be pinned
--    (e.g. `ALTER SESSION SET TIMEZONE = 'America/Chicago'`) so the stored instant
--    does not drift between runs?
-- - **SME-Q2 (SEM-06):** What are the source column types of
--    `o.sched_departure_date` and `n.sched_departure_time`? Should the implicit
--    casts inside `CONCAT(TO_DATE(...), ' ', n.sched_departure_time)` be made
--    explicit (e.g. `TO_CHAR(TO_DATE(o.sched_departure_date),'YYYY-MM-DD')`) to
--    remove dependence on session default formats?
-- - **SME-Q3 (SEM-06):** Does `n.sched_departure_time` carry **9-digit
--    fractional seconds**, matching the `FF9` element in the format mask? If its
--    precision differs, should the mask be relaxed (e.g. `FF6`) or the value pre-
--    formatted?
-- - **SME-Q4 (SEM-10):** Are `n.act_departure_station` / `n.act_arrival_station`
--    semantically the **same (actual) grain** as `o.departure_station` /
--    `o.arrival_station`? A scheduled-vs-actual mismatch on either station key
--    would silently change which rows pair up and therefore every `change_ind`
--    value.
-- - **SME-Q5 (DEF-06):** Confirm the `TO_TIMESTAMP_LTZ(...)` expression is
--    positionally correct in INSERT slot 42 (`new_sched_departure_time`) and that
--    only the **alias** was wrong (not the position). The logical shape (date +
--    time → timestamp) supports this, but without ground truth it remains an
--    inference.
--
-- ---
-- >>> SEMANTIC EXPLANATION

-- FIX LOG (issues repaired during remediation)
-- [DEF-06] line 106-109: alias AS new_sched_departure_date -> AS new_sched_departure_time (positional alignment; alias was copy-paste error, no data change)
-- TODO(SME) markers added (no mechanical fix, SME review required):
--   [SEM-04] TO_TIMESTAMP_LTZ timezone intent
--   [SEM-06] Implicit casts in CONCAT/TO_DATE
--   [SEM-06] FF9 format precision vs n.sched_departure_time precision
--   [SEM-10] Join key act_*_station vs departure_station/arrival_station grain

-- SEM ▸ Purpose: before/after diff of flight leg records into an insertion-expiration tracking table (FULL OUTER JOIN of old source1 vs new source2; change_ind = A/E/U).
INSERT INTO staging.wrk_synthetic_flgt_leg_ins_exp
(
      old_operating_airline_cd,
      old_operating_flgt_no,
      old_operating_sfx_cd,
      old_sched_departure_date,
      old_gmt_flgt_dt,
      old_departure_station,
      old_arrival_station,
      old_service_typ,
      old_sched_arrival_date,
      old_gmt_flgt_arrival_date,
      old_sched_departure_time,
      old_sched_arrival_time,
      old_gmt_sched_departure_time,
      old_gmt_sched_arrival_time,
      old_accounting_year_no,
      old_accounting_month_no,
      old_accounting_week_no,
      old_local_flgt_dt,
      old_iata_ac_typ,
      old_pax_departure_timel_cd,
      old_pax_arrival_timel_cd,
      old_leg_sequence,
      old_effective_dt,
      old_expiry_dt,
      old_opg_flgt_leg_id,
      old_current_rec_ind,
      old_carrier_ac_typ,
      old_dep_utc_variation_txt,
      old_arr_utc_variation_txt,
      old_sched_src_typ,
      new_sequence,
      new_operating_airline_cd,
      new_operating_flgt_no,
      new_operating_sfx_cd,
      new_sched_departure_date,
      new_gmt_flgt_dt,
      itinerary_variation_id,
      new_act_departure_station,
      new_act_arrival_station,
      new_service_typ,
      new_sched_arrival_date,
      new_sched_departure_time,
      new_sched_arrival_time,
      new_gmt_sched_departure_time,
      new_gmt_sched_arrival_time,
      marketing_airline_cd,
      marketing_flgt_no,
      new_iata_ac_typ,
      new_pax_departure_timel_cd,
      new_pax_arrival_timel_cd,
      new_leg_sequence,
      new_effective_dt,
      new_expiry_dt,
      new_current_rec_ind,
      new_carrier_ac_typ,
      new_dep_utc_variation_txt,
      new_arr_utc_variation_txt,
      new_codeshare_ind,
      new_sched_src_typ,
      change_ind
)
SELECT
      o.operating_airline_cd,
      o.operating_flgt_no,
      o.operating_sfx_cd,
      o.sched_departure_date,
      o.gmt_flgt_dt,
      o.departure_station,
      o.arrival_station,
      o.service_typ,
      o.sched_arrival_date,
      o.gmt_flgt_arrival_date,
      o.sched_departure_time,
      o.sched_arrival_time,
      o.gmt_sched_departure_time,
      o.gmt_sched_arrival_time,
      o.accounting_year_no,
      o.accounting_month_no,
      o.accounting_week_no,
      o.local_flgt_dt,
      o.iata_ac_typ,
      o.pax_departure_timel_cd,
      o.pax_arrival_timel_cd,
      o.leg_sequence,
      o.effective_dt,
      o.expiry_dt,
      o.opg_flgt_leg_id,
      o.current_rec_ind,
      o.carrier_ac_typ,
      o.dep_utc_variation_txt,
      o.arr_utc_variation_txt,
      o.sched_src_typ,
      n.sequence,
      n.operating_airline_cd,
      n.operating_flgt_no,
      n.operating_sfx_cd,
      n.sched_departure_date,
      n.gmt_flgt_dt,
      n.itinerary_variation_id,
      n.act_departure_station,
      n.act_arrival_station,
      n.service_typ,
      n.sched_arrival_date,
      -- TODO(SME) [SEM-04]: TO_TIMESTAMP_LTZ returns local-session-TZ timestamp. Confirm new_sched_departure_time should hold local time (not NTZ/TZ). Pin session TIMEZONE.
      -- SEM ▸ SEM-04: Returns a local-session-TZ timestamp. Confirm LTZ intent for new_sched_departure_time and pin session TIMEZONE.
      TO_TIMESTAMP_LTZ(
          -- TODO(SME) [SEM-06]: Implicit casts in CONCAT/TO_DATE — consider TO_CHAR(TO_DATE(o.sched_departure_date),'YYYY-MM-DD') for explicitness. Confirm source column types.
          -- SEM ▸ SEM-06: Implicit casts in CONCAT/TO_DATE — consider explicit TO_CHAR(TO_DATE(...),'YYYY-MM-DD'). Confirm source column types.
          CONCAT(TO_DATE(o.sched_departure_date), ' ', n.sched_departure_time),
          -- TODO(SME) [SEM-06]: FF9 expects 9-digit fractional seconds — confirm n.sched_departure_time precision matches.
          -- SEM ▸ SEM-06: FF9 expects 9-digit fractional seconds — confirm n.sched_departure_time precision matches.
          'YYYY-MM-DD HH24:MI:SS.FF9'
      ) AS new_sched_departure_time,
      n.sched_arrival_time,
      n.gmt_sched_departure_time,
      n.gmt_sched_arrival_time,
      n.marketing_airline_cd,
      n.marketing_flgt_no,
      n.iata_ac_typ,
      n.pax_departure_timel_cd,
      n.pax_arrival_timel_cd,
      n.leg_sequence,
      n.effective_dt,
      n.expiry_dt,
      n.current_rec_ind,
      n.carrier_ac_typ,
      n.dep_utc_variation_txt,
      n.arr_utc_variation_txt,
      n.codeshare_ind,
      n.sched_src_typ,
      CASE
          -- SEM ▸ change_ind SCD pattern: A=add (old side absent), E=expire (new side absent), U=update (both present).
          WHEN o.operating_airline_cd IS NULL THEN 'A'
          WHEN n.operating_airline_cd IS NULL THEN 'E'
          ELSE 'U'
      END AS change_ind
-- TODO(SME) [SEM-10]: Join keys n.act_departure_station=o.departure_station and n.act_arrival_station=o.arrival_station — confirm both sides are actual (not scheduled) station grain.
FROM   staging.wrk_synthetic_flgt_source1 o
-- SEM ▸ SEM-10: Join keys use n.act_*_station vs o.departure_station/arrival_station — confirm both sides are actual-station grain.
FULL OUTER JOIN staging.wrk_synthetic_flgt_source2 n
       ON n.operating_airline_cd = o.operating_airline_cd
      AND n.operating_flgt_no    = o.operating_flgt_no
      AND n.operating_sfx_cd     = o.operating_sfx_cd
      AND n.sched_departure_date         = o.sched_departure_date
      AND n.act_departure_station       = o.departure_station
      AND n.act_arrival_station       = o.arrival_station;
