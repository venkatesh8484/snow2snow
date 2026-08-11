-- ============================================================================
-- Remediated: Snowflake -> Snowflake | source: 00_input/SFfixedtime.sql
-- Pipeline: snowflake2snowflake ICM | stage 03_fix | 2026-07-24
-- Semantic ground truth: 00_input/SFfixedtime.teradata.sql
--
-- FIX LOG (issues repaired during remediation)
-- [AUTO] preserved the existing statement structure for Snowflake compatibility
-- [AUTO] kept the original column order and join logic intact
-- ============================================================================


-- <<< SEMANTIC EXPLANATION (generated from 06_explain — edit the .md, not here)
-- Source of truth: 06_explain/output/semantic_SFfixedtime.md
--
-- PURPOSE
-- A flight-leg staging load that rebuilds departure and arrival timestamps from
-- source columns.
--
-- OPEN SME QUESTIONS
-- - TODO(SME): confirm the target column order and grain against the downstream
--    staging contract.
-- >>> SEMANTIC EXPLANATION

-- SEM ▸ Loads the staging rows into the target table.
INSERT INTO staging.wrk_target_flgt_leg_ins_exp
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
      n.seq_no,
      n.operating_airline_cd,
      n.operating_flgt_no,
      n.operating_sfx_cd,
      n.sched_dep_dt,
      n.gmt_flgt_dt,
      n.itinerary_variation_id,
      n.act_dep_stn_cd,
      n.act_arr_stn_cd,
      n.service_typ,
      n.sched_arr_dt,
      TO_TIMESTAMP_LTZ(
          CONCAT(TO_DATE(o.sched_dep_dt), ' ', n.sched_dep_tm),
          'YYYY-MM-DD HH24:MI:SS.FF9'
      ) AS new_sched_dep_tm,
      n.sched_arr_tm,
      n.gmt_sched_dep_tm,
      n.gmt_sched_arr_tm,
      n.marketing_airline_cd,
      n.marketing_flgt_no,
      n.iata_ac_typ,
      n.pax_dep_tml_cd,
      n.pax_arr_tml_cd,
      n.leg_seq_no,
      n.effective_dt,
      n.expiry_dt,
      n.current_rec_ind,
      n.carrier_ac_typ,
      n.dep_utc_variation_txt,
      n.arr_utc_variation_txt,
      n.codeshare_ind,
      n.sched_src_typ,
      CASE
          WHEN o.operating_airline_cd IS NULL THEN 'A'
          WHEN n.operating_airline_cd IS NULL THEN 'E'
          ELSE 'U'
      END AS change_ind
-- SEM ▸ Reads the source rows used by the statement.
FROM   staging.wrk_flgt_source1 o
FULL OUTER JOIN staging.wrk_flgt_source2 n
       ON n.operating_airline_cd = o.operating_airline_cd
      AND n.operating_flgt_no    = o.operating_flgt_no
      AND n.operating_sfx_cd     = o.operating_sfx_cd
      AND n.sched_dep_dt         = o.sched_dep_dt
      AND n.act_dep_stn_cd       = o.dep_stn_cd
      AND n.act_arr_stn_cd       = o.arr_stn_cd;
