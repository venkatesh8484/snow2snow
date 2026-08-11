-- FIX LOG (issues repaired during remediation)
-- Unit: SFIssueSET.sql
-- Date: 2026-07-24
-- Source: 00_input/SFIssueSET.sql
-- Analysis: 01_analyze/output/analysis_SFIssueSET.md
--
-- No mechanical syntax/defect fixes required — file parses clean on Snowflake.
-- All findings are SME-classified semantic risks (see TODO(SME) markers below).
--
-- Findings inventory (all SME, no AUTO/FIX):
--   S1 [SEM-05]        SET-table dedup signal — single INSERT with 3 UNION
--                      branches into staging.wrk_target, no DDL supplied.
--   S2 [SEM-05/lesson] UNION vs UNION ALL set-semantics (2 UNION operators).
--   S3 [SEM-02/FN-LATEST] Latest-value trick needs fixed-width key.
--   S4 [SEM-02]        MAX over string concat tie-break non-determinism.
--   S5 [SEM-06/DTX-10] Scalar subquery param_value implicit string->date cast.
--   S6 [SEM]           operating_airline_cd width-3 truncation consistency.
--
-- Per SEM-05: SET vs MULTISET lives in the target's CREATE TABLE DDL, not in
-- an INSERT-only script. No DDL for staging.wrk_target is supplied, so SET
-- cannot be confirmed. Do NOT split the UNION into separate INSERTs or change
-- UNION to UNION ALL without SME confirmation. Structure preserved as-is.
-- ============================================================

-- TODO(SME) [SEM-05]: Is staging.wrk_target a SET table? If yes, each UNION branch must be a separate INSERT INTO staging.wrk_target (SELECT ... EXCEPT SELECT * FROM staging.wrk_target). Do not assume SET.
INSERT INTO staging.wrk_target
SELECT
      src.airline_cd
    , src.flgt_no
    , src.flgt_dt
    -- TODO(SME) [SEM-02/FN-LATEST]: Latest-value trick needs fixed-width key — format as TO_CHAR(effective_dt,'YYYY-MM-DD') || LPAD(val::VARCHAR,n,' ') before MAX. Confirm effective_dt type and value display widths.
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
           -- TODO(SME) [SEM-06/DTX-10]: param_value implicit string→date cast — confirm format and consider TO_DATE(param_value,'YYYY-MM-DD').
           SELECT param_value
           FROM   synthetic_sys_param
           WHERE  param_id = 'UPDATE_CUTOFF'
       )
GROUP BY
      src.airline_cd
    , src.flgt_no
    , src.flgt_dt

-- TODO(SME) [SEM-05]: UNION vs UNION ALL — confirm set-semantics. UNION de-duplicates across branches; if the original used separate INSERTs (SET-table dedup) or UNION ALL, this UNION is wrong.
UNION

SELECT
      src.airline_cd
    , src.flgt_no
    , src.flgt_dt
    -- TODO(SME) [SEM-02/FN-LATEST]: Latest-value trick needs fixed-width key — format as TO_CHAR(effective_dt,'YYYY-MM-DD') || LPAD(val::VARCHAR,n,' ') before MAX. Confirm effective_dt type and value display widths.
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
           -- TODO(SME) [SEM-06/DTX-10]: param_value implicit string→date cast — confirm format and consider TO_DATE(param_value,'YYYY-MM-DD').
           SELECT param_value
           FROM   synthetic_sys_param
           WHERE  param_id = 'UPDATE_CUTOFF'
       )
GROUP BY
      src.airline_cd
    , src.flgt_no
    , src.flgt_dt

-- TODO(SME) [SEM-05]: UNION vs UNION ALL — confirm set-semantics. UNION de-duplicates across branches; if the original used separate INSERTs (SET-table dedup) or UNION ALL, this UNION is wrong.
UNION

SELECT
      src.airline_cd
    , src.flgt_no
    , src.flgt_dt
    -- TODO(SME) [SEM-02/FN-LATEST]: Latest-value trick needs fixed-width key — format as TO_CHAR(effective_dt,'YYYY-MM-DD') || LPAD(val::VARCHAR,n,' ') before MAX. Confirm effective_dt type and value display widths.
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
           -- TODO(SME) [SEM-06/DTX-10]: param_value implicit string→date cast — confirm format and consider TO_DATE(param_value,'YYYY-MM-DD').
           SELECT param_value
           FROM   synthetic_sys_param
           WHERE  param_id = 'UPDATE_CUTOFF'
       )
GROUP BY
      src.airline_cd
    , src.flgt_no
    , src.flgt_dt
;