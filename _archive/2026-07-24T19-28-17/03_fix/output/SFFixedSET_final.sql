-- ============================================================================
-- Remediated: Snowflake -> Snowflake | source: 00_input/SFFixedSET.sql
-- Pipeline: snowflake2snowflake ICM | stage 03_fix | 2026-07-24
-- Semantic ground truth: 00_input/SFFixedSET.teradata.sql
--
-- FIX LOG (issues repaired during remediation)
-- [AUTO] preserved the existing statement structure for Snowflake compatibility
-- [AUTO] kept the original column order and join logic intact
-- ============================================================================


-- <<< SEMANTIC EXPLANATION (generated from 06_explain — edit the .md, not here)
-- Source of truth: 06_explain/output/semantic_SFFixedSET.md
--
-- PURPOSE
-- A set-based staging load using EXCEPT to keep only rows not already present in
-- the target table.
--
-- OPEN SME QUESTIONS
-- - TODO(SME): confirm the target column order and grain against the downstream
--    staging contract.
-- >>> SEMANTIC EXPLANATION

-- SEM ▸ Loads the staging rows into the target table.
INSERT INTO staging.wrk_target
(
SELECT
      src.airline_cd
    , src.flgt_no
    , src.flgt_dt
    , SUBSTR(MAX(src.effective_dt || cs.company_cd), 11, 99)      AS company_cd
    , SUBSTR(MAX(src.effective_dt || cs.direction_ind), 11, 99)   AS direction_ind
    , SUBSTR(MAX(src.effective_dt || cs.operating_airline_cd), 11, 3)
          AS operating_airline_cd
    , SUBSTR(
          MAX(
              TO_CHAR(src.effective_dt, 'YYYY-MM-DD')
              || LPAD(cs.operating_flgt_no::VARCHAR, 5, ' ')
          ),
          11,
          99
      ) AS operating_flgt_no
    , SUBSTR(MAX(src.effective_dt || cs.operating_sfx_cd), 11, 99)
          AS operating_sfx_cd

-- SEM ▸ Reads the source rows used by the statement.
FROM   synthetic_flgt_source src
JOIN   synthetic_mkg_flgt_leg cs
       ON  src.airline_cd = cs.marketing_airline_cd
       AND src.flgt_no    = cs.marketing_flgt_no
       AND src.flgt_dt    = cs.gmt_flgt_dt

WHERE  cs.dep_stn_cd <> cs.arr_stn_cd
AND    src.flgt_dt > (
           SELECT param_value
           FROM   synthetic_sys_param
           WHERE  param_id = 'UPDATE_CUTOFF'
       )
-- SEM ▸ Preserves the grouping grain of the branch query.
GROUP BY
      src.airline_cd
    , src.flgt_no
    , src.flgt_dt

EXCEPT

SELECT *
FROM   staging.wrk_target
);

INSERT INTO staging.wrk_target
(
SELECT
      src.airline_cd
    , src.flgt_no
    , src.flgt_dt
    , SUBSTR(MAX(src.effective_dt || leg.company_cd), 11, 99)      AS company_cd
    , SUBSTR(MAX(src.effective_dt || leg.direction_ind), 11, 99)   AS direction_ind
    , SUBSTR(MAX(src.effective_dt || leg.operating_airline_cd), 11, 3)
          AS operating_airline_cd
    , SUBSTR(
          MAX(
              TO_CHAR(src.effective_dt, 'YYYY-MM-DD')
              || LPAD(leg.operating_flgt_no::VARCHAR, 5, ' ')
          ),
          11,
          99
      ) AS operating_flgt_no
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

SELECT *
FROM   staging.wrk_target
);
INSERT INTO staging.wrk_target
(
SELECT
      src.airline_cd
    , src.flgt_no
    , src.flgt_dt
    , SUBSTR(MAX(src.effective_dt || cs.company_cd), 11, 99)      AS company_cd
    , SUBSTR(MAX(src.effective_dt || cs.direction_ind), 11, 99)   AS direction_ind
    , SUBSTR(MAX(src.effective_dt || cs.operating_airline_cd), 11, 3)
          AS operating_airline_cd
    , SUBSTR(
          MAX(
              TO_CHAR(src.effective_dt, 'YYYY-MM-DD')
              || LPAD(cs.operating_flgt_no::VARCHAR, 5, ' ')
          ),
          11,
          99
      ) AS operating_flgt_no
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

SELECT *
FROM   staging.wrk_target
);
