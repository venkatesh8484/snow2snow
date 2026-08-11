-- FIX LOG (issues repaired during remediation)
-- [DEF-06] line 110: alias `AS new_sched_departure_date` -> `AS new_sched_departure_time`
--   to match the INSERT target column at SELECT position 42 (line 45).
--   INSERT...SELECT is positional, so only the alias label changes; the
--   TO_TIMESTAMP_LTZ(...) expression stays in its slot. Minimal diff = 1 token.
-- [SEM-04] line 107-110: TODO(SME) -- TO_TIMESTAMP_LTZ introduces a session-TZ
--   dependency; confirm new_sched_departure_time is meant to hold a local-time
--   (LTZ) timestamp and pin session TIMEZONE.
-- [SEM-06/DTX-10] line 108-109: TODO(SME) -- implicit date/time casts in CONCAT
--   and FF9 mask precision; confirm source types and precision.
-- [SEM-10] line 135-140: TODO(SME) -- act_*_station vs non-act_ join-key grain;
--   confirm both sides are the same (actual) grain.
-- [SEM-08] line 128-132: TODO(SME) -- '' vs NULL on change_ind CASE inputs;
--   confirm IS NULL is the intended test (no empty-string hazard).
-- [SEM-03] (join keys): TODO(SME) -- CHAR(n) padding drift on join keys;
--   confirm no CHAR(n) comparison drift without DDL.
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
      -- TODO(SME): SEM-04 -- TO_TIMESTAMP_LTZ returns a timestamp with local
      --   session time zone; confirm new_sched_departure_time is meant to hold
      --   a local-time (LTZ) timestamp and pin session TIMEZONE.
      -- TODO(SME): SEM-06/DTX-10 -- implicit date/time casts in CONCAT and FF9
      --   mask precision; confirm source types and precision of
      --   o.sched_departure_date and n.sched_departure_time.
      TO_TIMESTAMP_LTZ(
          CONCAT(TO_DATE(o.sched_departure_date), ' ', n.sched_departure_time),
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
      -- TODO(SME): SEM-08 -- '' vs NULL on change_ind CASE inputs; confirm
      --   IS NULL is the intended test (no empty-string hazard).
      CASE
          WHEN o.operating_airline_cd IS NULL THEN 'A'
          WHEN n.operating_airline_cd IS NULL THEN 'E'
          ELSE 'U'
      END AS change_ind
FROM   staging.wrk_synthetic_flgt_source1 o
FULL OUTER JOIN staging.wrk_synthetic_flgt_source2 n
       ON n.operating_airline_cd = o.operating_airline_cd
      -- TODO(SME): SEM-10 -- act_*_station vs non-act_ join-key grain; confirm
      --   both sides are the same (actual) grain.
      -- TODO(SME): SEM-03 -- CHAR(n) padding drift on join keys; confirm no
      --   CHAR(n) comparison drift (no DDL supplied).
      AND n.operating_flgt_no    = o.operating_flgt_no
      AND n.operating_sfx_cd     = o.operating_sfx_cd
      AND n.sched_departure_date         = o.sched_departure_date
      AND n.act_departure_station       = o.departure_station
      AND n.act_arrival_station       = o.arrival_station;