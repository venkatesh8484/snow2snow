-- ============================================================================
-- Remediated: Snowflake -> Snowflake | source: 00_input/SFIssueSET.sql
-- Pipeline: snowflake2snowflake ICM | stage 03_fix | MANUAL correction
-- Semantic ground truth: 00_input/SFIssueSET.teradata.sql
--
-- REAL ISSUES (missed by the earlier automated run, which changed 0 SQL lines)
-- [SEM-05] SET-table dedup was lost. The Teradata original ran THREE independent
--          INSERTs into a SET table -> rows already present are dropped on insert.
--          The delivered file collapsed them into ONE INSERT with `UNION`, which
--          (a) removed the "don't re-insert rows already in the target" guarantee
--          and (b) added cross-branch de-duplication that never existed.
--          Restored as three separate INSERTs, each guarded with
--          `EXCEPT SELECT * FROM staging.wrk_target` (matches SFFixedSET).
-- [FN-LATEST] `SUBSTR(MAX(effective_dt || operating_flgt_no), 11, ...)` "keep the
--          latest value" trick needs fixed-width formatting so MAX() orders by
--          effective_dt then flgt_no. Wrapped as
--          TO_CHAR(effective_dt,'YYYY-MM-DD') || LPAD(operating_flgt_no::VARCHAR,5,' ').
-- ============================================================================

-- Branch 1: marketing leg
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
          ), 11, 99
      ) AS operating_flgt_no
    , SUBSTR(MAX(src.effective_dt || leg.operating_sfx_cd), 11, 99)
          AS operating_sfx_cd
FROM   synthetic_flgt_source src
JOIN   synthetic_mkg_flgt_leg leg
       ON  src.airline_cd = leg.marketing_airline_cd
       AND src.flgt_no    = leg.marketing_flgt_no
       AND src.flgt_dt    = leg.gmt_flgt_dt
WHERE  leg.dep_stn_cd <> leg.arr_stn_cd
AND    src.flgt_dt > (
           SELECT param_value FROM synthetic_sys_param WHERE param_id = 'UPDATE_CUTOFF'
       )
GROUP BY src.airline_cd, src.flgt_no, src.flgt_dt
EXCEPT
SELECT * FROM staging.wrk_target
);

-- Branch 2: operational leg
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
          ), 11, 99
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
           SELECT param_value FROM synthetic_sys_param WHERE param_id = 'UPDATE_CUTOFF'
       )
GROUP BY src.airline_cd, src.flgt_no, src.flgt_dt
EXCEPT
SELECT * FROM staging.wrk_target
);

-- Branch 3: codeshare leg
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
          ), 11, 99
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
           SELECT param_value FROM synthetic_sys_param WHERE param_id = 'UPDATE_CUTOFF'
       )
GROUP BY src.airline_cd, src.flgt_no, src.flgt_dt
EXCEPT
SELECT * FROM staging.wrk_target
);
