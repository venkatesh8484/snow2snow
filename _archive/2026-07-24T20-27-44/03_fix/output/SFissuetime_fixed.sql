-- FIX LOG (issues repaired during remediation)
-- [AUTO] No SFX/FNX/DTX fixes required — file parses clean on Snowflake; no
--        residual Teradata constructs found (ZEROIFNULL, CONTAINS, MULTISET,
--        (+), BTEQ, MINUS, SEL, etc. all absent).
-- [AUTO] No DEF-01/DEF-03/DEF-04/DEF-05 defects — 60 INSERT columns = 60 SELECT
--        expressions; no duplicates, no unbalanced parens, no malformed calls.
-- [DEF-07] line 110: new_sched_departure_time (INSERT pos 42) is fed
--          n.sched_arrival_time — likely copy-paste defect (should be
--          n.sched_departure_time). No Teradata ground truth supplied → FLAGGED
--          as SME, NOT swapped (per DEF-07). See TODO(SME) at line ~110.
-- [DTX-04/SEM-04] lines 106-109: TO_TIMESTAMP_LTZ(...) feeds new_sched_departure_date
--                 (DATE-named slot) while sibling old_sched_departure_date gets a
--                 plain DATE — type drift / session-TZ sensitivity. FLAGGED as
--                 SME (no DDL supplied). See TODO(SME) at lines 106-109.
-- [SEM-03] lines 134-139: string join keys (operating_airline_cd, operating_sfx_cd,
--          departure_station, arrival_station) may be CHAR(n) — blank-padding
--          drift risk. FLAGGED as SME. See TODO(SME) at join block.
-- [SEM-06] lines 134-139: join key type alignment (sched_departure_date both
--          sides) — implicit cast may cause missed matches if types differ.
--          FLAGGED as SME. See TODO(SME) at join block.
-- All findings are SME; no SQL changes were made beyond adding TODO(SME)
-- comments. Minimal diff — statement is executable as-is on Snowflake.

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
      -- TODO(SME) [DTX-04/SEM-04]: new_sched_departure_date (INSERT pos 35) is a
      -- DATE-named slot, but this expression yields TIMESTAMP_LTZ while the
      -- sibling old_sched_departure_date (pos 4) is fed a plain DATE. Is the
      -- target column DATE or TIMESTAMP? If DATE, Snowflake will implicitly cast
      -- (dropping time + shifting by session TZ). Confirm intended type and
      -- whether session TIMEZONE should be pinned. No change made — flagged only.
      TO_TIMESTAMP_LTZ(
          CONCAT(TO_DATE(o.sched_departure_date), ' ', n.sched_departure_time),
          'YYYY-MM-DD HH24:MI:SS.FF9'
      ) AS new_sched_departure_date,
      -- TODO(SME) [DEF-07/SEM-10]: INSERT position 42 is new_sched_departure_time,
      -- but this feeds n.sched_arrival_time — likely a copy-paste defect (should
      -- be n.sched_departure_time). No Teradata ground truth supplied, so NOT
      -- swapped per DEF-07. Confirm the correct source column.
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
          WHEN o.operating_airline_cd IS NULL THEN 'A'
          WHEN n.operating_airline_cd IS NULL THEN 'E'
          ELSE 'U'
      END AS change_ind
FROM   staging.wrk_synthetic_flgt_source1 o
-- TODO(SME) [SEM-03]: string join keys (operating_airline_cd, operating_sfx_cd,
-- departure_station, arrival_station) may be CHAR(n). Teradata blank-pads CHAR;
-- Snowflake does not — trailing-space differences can cause missed matches.
-- If any key is CHAR(n), wrap with RTRIM(...) on both sides.
-- TODO(SME) [SEM-06]: join key type alignment — confirm sched_departure_date is
-- the same type on both sources (DATE vs TIMESTAMP/string). Implicit cast may
-- cause missed matches if types differ.
FULL OUTER JOIN staging.wrk_synthetic_flgt_source2 n
       ON n.operating_airline_cd = o.operating_airline_cd
      AND n.operating_flgt_no    = o.operating_flgt_no
      AND n.operating_sfx_cd     = o.operating_sfx_cd
      AND n.sched_departure_date         = o.sched_departure_date
      AND n.act_departure_station       = o.departure_station
      AND n.act_arrival_station       = o.arrival_station;