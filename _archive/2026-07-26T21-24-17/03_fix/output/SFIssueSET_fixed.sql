-- ===========================================================================
-- FIX LOG — SFIssueSET.sql
-- Source: 00_input/SFIssueSET.sql
-- Reviewer guidance: 07_review/output/review_SFIssueSET.md (SET table confirmed)
-- ---------------------------------------------------------------------------
-- SEM-05 (lines 1, 27, 50): SET-table dedup — reviewer confirmed
--   staging.wrk_target is a Teradata SET table. The buggy input collapsed 3
--   independent Teradata INSERTs into one INSERT ... UNION ... UNION, which
--   (a) de-duplicates ACROSS branches (wrong dedup axis) and (b) re-inserts
--   rows already present in the target. Split into 3 independent
--   INSERT INTO staging.wrk_target (col list) (SELECT ... EXCEPT SELECT *
--   FROM staging.wrk_target) statements. Removed UNION operators entirely.
--   Added explicit INSERT target column list so the EXCEPT positional match
--   is unambiguous.
-- [TODO(SME)] SEM-05 (sub): target physical column order is unknown (no DDL
--   supplied). The explicit column list below assumes the order
--   airline_cd, flgt_no, flgt_dt, company_cd, direction_ind,
--   operating_airline_cd, operating_flgt_no, operating_sfx_cd — matching the
--   SELECT projection order of the buggy input. Confirm against target DDL.
-- [TODO(SME)] SEM-02 / FN-LATEST (lines 5-10, 28-33, 51-56): latest-value
--   trick SUBSTR(MAX(src.effective_dt || <val>), 11, N). Correctness depends
--   on effective_dt being a fixed-width, lexicographically sortable string.
--   If effective_dt is DATE/TIMESTAMP, Snowflake's implicit cast may not be
--   zero-padded, so MAX can pick the wrong row. No SQL change pending DDL /
--   data-type confirmation. Consider TO_CHAR(effective_dt,'YYYY-MM-DD') || val.
-- [TODO(SME)] SEM-06 / DTX-10 (lines 18-22, 41-45, 64-68): implicit
--   param_value string->date cast in WHERE (src.flgt_dt > (SELECT param_value
--   ...)). If param_value is VARCHAR and flgt_dt is DATE, Snowflake's strict
--   casting may error/mismatch. Consider TO_DATE(param_value, '<fmt>').
--   Also effective_dt || <val> relies on implicit date->string cast.
-- [TODO(SME)] SEM-03: CHAR(n) padding drift — join/EXCEPT keys (airline_cd,
--   flgt_no, company_cd, *_stn_cd, etc.) may be CHAR(n). Teradata blank-pads
--   and ignores trailing spaces in =; Snowflake does not, so join/EXCEPT
--   matching can drift. Consider TRIM/RTRIM. Cannot confirm without DDL.
-- [TODO(SME)] SEM-04: TIMESTAMP vs TIMESTAMP_TZ on gmt_flgt_dt /
--   effective_dt — NTZ/TZ mismatch shifts values. Cannot confirm without DDL.
-- [TODO(SME)] SEM-10: join-key direction (marketing/operational/codeshare)
--   plausible from names but unverifiable without Teradata ground truth.
-- ===========================================================================

-- Branch 1: marketing leg
INSERT INTO staging.wrk_target (
      airline_cd
    , flgt_no
    , flgt_dt
    , company_cd
    , direction_ind
    , operating_airline_cd
    , operating_flgt_no
    , operating_sfx_cd
)
(
SELECT
      src.airline_cd
    , src.flgt_no
    , src.flgt_dt
    , SUBSTR(MAX(src.effective_dt || leg.company_cd), 11, 99)      AS company_cd
    , SUBSTR(MAX(src.effective_dt || leg.direction_ind), 11, 99)   AS direction_ind
    , SUBSTR(MAX(src.effective_dt || leg.operating_airline_cd), 11, 3)
          AS operating_airline_cd
    , SUBSTR(MAX(src.effective_dt || leg.operating_flgt_no), 11, 99)
          AS operating_flgt_no
    , SUBSTR(MAX(src.effective_dt || leg.operating_sfx_cd), 11, 99)
          AS operating_sfx_cd
FROM   synthetic_flgt_source src
JOIN   synthetic_mkg_flgt_leg leg
       ON  src.airline_cd = leg.marketing_airline_cd
       AND src.flgt_no    = leg.marketing_flgt_no
       AND src.flgt_dt    = leg.gmt_flgt_dt
WHERE  leg.dep_stn_cd <> leg.arr_stn_cd
AND    src.flgt_dt > (
           SELECT param_value
           FROM   synthetic_sys_param
           WHERE  param_id = 'UPDATE_CUTOFF'
       )
GROUP BY
      src.airline_cd
    , src.flgt_no
    , src.flgt_dt
EXCEPT
SELECT * FROM staging.wrk_target
)
;

-- Branch 2: operational leg
INSERT INTO staging.wrk_target (
      airline_cd
    , flgt_no
    , flgt_dt
    , company_cd
    , direction_ind
    , operating_airline_cd
    , operating_flgt_no
    , operating_sfx_cd
)
(
SELECT
      src.airline_cd
    , src.flgt_no
    , src.flgt_dt
    , SUBSTR(MAX(src.effective_dt || leg.company_cd), 11, 99)      AS company_cd
    , SUBSTR(MAX(src.effective_dt || leg.direction_ind), 11, 99)   AS direction_ind
    , SUBSTR(MAX(src.effective_dt || leg.operating_airline_cd), 11, 3)
          AS operating_airline_cd
    , SUBSTR(MAX(src.effective_dt || leg.operating_flgt_no), 11, 99)
          AS operating_flgt_no
    , SUBSTR(MAX(src.effective_dt || leg.operating_sfx_cd), 11, 99)
          AS operating_sfx_cd
FROM   synthetic_flgt_source src
JOIN   synthetic_operational_flgt_leg leg
       ON  src.airline_cd = leg.operating_airline_cd
       AND src.flgt_no    = leg.operating_flgt_no
       AND src.flgt_dt    = leg.gmt_flgt_dt
WHERE  leg.dep_stn_cd <> leg.arr_stn_cd
AND    src.flgt_dt > (
           SELECT param_value
           FROM   synthetic_sys_param
           WHERE  param_id = 'UPDATE_CUTOFF'
       )
GROUP BY
      src.airline_cd
    , src.flgt_no
    , src.flgt_dt
EXCEPT
SELECT * FROM staging.wrk_target
)
;

-- Branch 3: codeshare leg
INSERT INTO staging.wrk_target (
      airline_cd
    , flgt_no
    , flgt_dt
    , company_cd
    , direction_ind
    , operating_airline_cd
    , operating_flgt_no
    , operating_sfx_cd
)
(
SELECT
      src.airline_cd
    , src.flgt_no
    , src.flgt_dt
    , SUBSTR(MAX(src.effective_dt || cs.company_cd), 11, 99)      AS company_cd
    , SUBSTR(MAX(src.effective_dt || cs.direction_ind), 11, 99)   AS direction_ind
    , SUBSTR(MAX(src.effective_dt || cs.operating_airline_cd), 11, 3)
          AS operating_airline_cd
    , SUBSTR(MAX(src.effective_dt || cs.operating_flgt_no), 11, 99)
          AS operating_flgt_no
    , SUBSTR(MAX(src.effective_dt || cs.operating_sfx_cd), 11, 99)
          AS operating_sfx_cd
FROM   synthetic_flgt_source src
JOIN   synthetic_codeshare_flgt_leg cs
       ON  src.airline_cd = cs.codeshare_airline_cd
       AND src.flgt_no    = cs.codeshare_flgt_no
       AND src.flgt_dt    = cs.gmt_flgt_dt
WHERE  cs.dep_stn_cd <> cs.arr_stn_cd
AND    src.flgt_dt > (
           SELECT param_value
           FROM   synthetic_sys_param
           WHERE  param_id = 'UPDATE_CUTOFF'
       )
GROUP BY
      src.airline_cd
    , src.flgt_no
    , src.flgt_dt
EXCEPT
SELECT * FROM staging.wrk_target
)
;