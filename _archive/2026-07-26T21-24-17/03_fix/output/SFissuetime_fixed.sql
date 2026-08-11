-- FIX LOG (issues repaired during remediation)
-- [DEF-06] line 103 (SELECT pos 42): alias `AS new_sched_departure_date` normalized to `AS new_sched_departure_time` to match the INSERT target column at that position. INSERT...SELECT is positional, so this is cosmetic; the expression (date+time -> timestamp) stays in its slot.
-- [SEM-04] line 103 (pos 42): TO_TIMESTAMP_LTZ(...) introduces a session-TIMEZONE dependency. Flagged TODO(SME) — confirm whether this slot is intended to store local time (with new_gmt_sched_departure_time as the GMT sibling) and whether the session TIMEZONE should be pinned or TIMESTAMP_NTZ/TZ used explicitly. No mechanical change.
-- [SEM-06] line 103 (pos 42): CONCAT(TO_DATE(o.sched_departure_date), ' ', n.sched_departure_time) relies on implicit date->string and time->string casts whose format depends on session defaults; the 'YYYY-MM-DD HH24:MI:SS.FF9' parse mask assumes a specific string shape. Flagged TODO(SME) — confirm whether explicit TO_CHAR casts and the FF9 mask (nanoseconds vs seconds) match the source precision. No mechanical change.
-- [SEM-10] lines 122-127 (FULL OUTER JOIN ON): join-key grain mismatch — n.act_departure_station = o.departure_station and n.act_arrival_station = o.arrival_station mix act_* (actual) columns on the new side with non-act_ names on the old side. Flagged TODO(SME) — confirm same grain (scheduled vs actual). Join left unchanged.
-- [SEM-08] lines 128-132 (CASE change_ind): CASE branches on NULL presence of operating_airline_cd to emit 'A'/'E'/'U'. Flagged TODO(SME) — confirm operating_airline_cd cannot be an empty string '' (which would not be NULL and would change the branch). No mechanical change.
-- [SEM-03] join keys: possible CHAR(n) padding/comparison drift on join keys (operating_airline_cd, operating_sfx_cd, service_typ, *_cd, *_typ). Flagged TODO(SME) — confirm no CHAR(n) keys require TRIM/RTRIM to preserve Teradata blank-padding semantics. No mechanical change.
-- [AUTO] No SFX-*/FNX-*/DTX-* rules fired; file is parse-clean Snowflake with no residual Teradata constructs.
-- [AUTO] Column count check: INSERT target cols = 60, SELECT expressions = 60 (match). No DEF-05.
-- [AUTO] No Teradata ground truth supplied (no 00_input/SFissuetime.teradata.sql); every semantic inference is flagged TODO(SME).

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
      -- TODO(SME) SEM-04: TO_TIMESTAMP_LTZ introduces a session-TIMEZONE dependency; confirm this slot is intended as local time (new_gmt_sched_departure_time is the GMT sibling) and whether to pin session TIMEZONE or use TIMESTAMP_NTZ/TZ explicitly.
      -- TODO(SME) SEM-06: CONCAT(TO_DATE(...), ' ', ...) relies on implicit date/time->string casts; confirm explicit TO_CHAR casts and that the FF9 mask matches source sched_departure_time precision (nanoseconds vs seconds).
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
      -- TODO(SME) SEM-08: CASE branches on NULL presence of operating_airline_cd; confirm operating_airline_cd cannot be an empty string '' (which would not be NULL and would change the branch result).
      CASE
          WHEN o.operating_airline_cd IS NULL THEN 'A'
          WHEN n.operating_airline_cd IS NULL THEN 'E'
          ELSE 'U'
      END AS change_ind
FROM   staging.wrk_synthetic_flgt_source1 o
FULL OUTER JOIN staging.wrk_synthetic_flgt_source2 n
       -- TODO(SME) SEM-10: join-key grain mismatch — n.act_departure_station/n.act_arrival_station (actual) vs o.departure_station/o.arrival_station; confirm same grain (scheduled vs actual). Join left unchanged.
       -- TODO(SME) SEM-03: if any join key is CHAR(n), Teradata blank-pads and ignores trailing spaces in '='; Snowflake does not pad. Confirm whether TRIM/RTRIM is required on CHAR(n) keys (operating_airline_cd, operating_sfx_cd, service_typ, *_cd, *_typ).
       ON n.operating_airline_cd = o.operating_airline_cd
      AND n.operating_flgt_no    = o.operating_flgt_no
      AND n.operating_sfx_cd     = o.operating_sfx_cd
      AND n.sched_departure_date         = o.sched_departure_date
      AND n.act_departure_station       = o.departure_station
      AND n.act_arrival_station       = o.arrival_station;