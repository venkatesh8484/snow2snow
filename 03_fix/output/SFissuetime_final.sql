
-- <<< SEMANTIC EXPLANATION (generated from 06_explain — edit the .md, not here)
-- Source of truth: 06_explain/output/semantic_SFissuetime.md
--
-- PURPOSE
-- `SFissuetime.sql` builds an SCD-2-style "old vs new" comparison table,
-- `staging.wrk_synthetic_flgt_leg_ins_exp`, by FULL OUTER JOINing two flight-leg
-- sources — `staging.wrk_synthetic_flgt_source1` (the "old" side, alias `o`) and
-- `staging.wrk_synthetic_flgt_source2` (the "new" side, alias `n`) — on the
-- flight identity keys (airline code, flight no, suffix, scheduled departure
-- date, and departure/arrival stations). For each matched pair it projects 60
-- columns: 30 "old_*" attributes from `o`, then 29 "new_*" attributes from `n`
-- (including a derived `new_sched_departure_time` timestamp built by combining
-- `o.sched_departure_date` with `n.sched_departure_time` via
-- `TO_TIMESTAMP_LTZ`), and a final `change_ind` flag computed as `'A'` (add —
-- old side NULL), `'E'` (expire — new side NULL), or `'U'` (update — both
-- present). The grain of one output row is one flight-leg identity.
--
-- ---
--
-- OPEN SME QUESTIONS
-- 1. **SEM-04 — LTZ intent.** Is `new_sched_departure_time` intended to store a
--    **local-time** timestamp (`TIMESTAMP_LTZ`)? Should the session `TIMEZONE` be
--    pinned, or should this be `TIMESTAMP_NTZ`/`TIMESTAMP_TZ`? (The sibling
--    `new_gmt_sched_departure_time` suggests the LTZ slot is the local time.)
-- 2. **SEM-06/DTX-10 — source types.** What are the source types of
--    `o.sched_departure_date` and `n.sched_departure_time`? Should the casts in
--    `CONCAT`/`TO_DATE` be made explicit (`TO_CHAR(TO_DATE(...),'YYYY-MM-DD')`) to
--    avoid session-default formatting?
-- 3. **SEM-06 — `FF9` precision.** Does `n.sched_departure_time` carry 9-digit
--    fractional seconds, or should the `FF9` mask be relaxed (e.g. `FF6`/`FF3`)?
-- 4. **SEM-10 — join-key grain.** Are `n.act_departure_station`/
--    `n.act_arrival_station` semantically the same (actual) grain as
--    `o.departure_station`/`o.arrival_station`? A scheduled-vs-actual mismatch
--    would change the join.
-- 5. **SEM-08 — `''` vs NULL.** Does the source ever use `''` (empty string) as
--    a sentinel that should be treated as NULL in the `change_ind` CASE? If so, add
--    `NULLIF(col,'')` before the `IS NULL` test.
-- 6. **SEM-03 — `CHAR(n)` padding.** Are any join keys `CHAR(n)`? If so, wrap
--    both sides in `RTRIM`/`TRIM` to preserve Teradata blank-padding semantics.
-- 7. **DEF-06 (confirmation) — position 42.** Confirm the
--    `TO_TIMESTAMP_LTZ(...)` expression is positionally correct in slot 42
--    (`new_sched_departure_time`) and only the alias was wrong. The logical shape
--    (date + time → timestamp) supports this, but without ground truth it is an
--    inference.
--
-- ---
-- >>> SEMANTIC EXPLANATION

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
      -- SEM ▸ SEM-04: TO_TIMESTAMP_LTZ returns a timestamp with local session TZ; confirm new_sched_departure_time is local-time and pin session TIMEZONE
      TO_TIMESTAMP_LTZ(
          -- SEM ▸ SEM-06/DTX-10: implicit date/time casts in CONCAT; make explicit with TO_CHAR(...,'YYYY-MM-DD')
          CONCAT(TO_DATE(o.sched_departure_date), ' ', n.sched_departure_time),
          -- SEM ▸ SEM-06: FF9 mask expects 9-digit fractional seconds; confirm n.sched_departure_time precision
          'YYYY-MM-DD HH24:MI:SS.FF9'
      -- SEM ▸ DEF-06: alias normalized from new_sched_departure_date to match INSERT target at position 42 (positional binding, no data change)
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
          -- SEM ▸ SEM-08: change_ind SCD-2 diff uses IS NULL (A=add/E=expire/U=update); confirm '' is not a sentinel
          WHEN o.operating_airline_cd IS NULL THEN 'A'
          -- SEM ▸ SEM-08: expire branch of the SCD-2 change_ind CASE
          WHEN n.operating_airline_cd IS NULL THEN 'E'
          ELSE 'U'
      END AS change_ind
FROM   staging.wrk_synthetic_flgt_source1 o
-- SEM ▸ SEM-10: FULL OUTER JOIN preserves adds/expires; join-key grain (act_* vs non-act_) flagged
FULL OUTER JOIN staging.wrk_synthetic_flgt_source2 n
       ON n.operating_airline_cd = o.operating_airline_cd
      -- TODO(SME): SEM-10 -- act_*_station vs non-act_ join-key grain; confirm
      --   both sides are the same (actual) grain.
      -- TODO(SME): SEM-03 -- CHAR(n) padding drift on join keys; confirm no
      --   CHAR(n) comparison drift (no DDL supplied).
      AND n.operating_flgt_no    = o.operating_flgt_no
      AND n.operating_sfx_cd     = o.operating_sfx_cd
      AND n.sched_departure_date         = o.sched_departure_date
      -- SEM ▸ SEM-10: act_* (actual) vs non-act_ join-key grain; confirm both sides are the same grain
      AND n.act_departure_station       = o.departure_station
      AND n.act_arrival_station       = o.arrival_station;
