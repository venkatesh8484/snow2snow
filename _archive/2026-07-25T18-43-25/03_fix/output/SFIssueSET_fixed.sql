-- FIX LOG (issues repaired during remediation)
-- [SEM-05] line 1, 32, 64: SET-table dedup (confirmed by reviewer in
--          07_review/output/review_SFIssueSET.md) — split the single
--          INSERT INTO staging.wrk_target SELECT … UNION … SELECT … UNION …
--          into 3 independent INSERT INTO staging.wrk_target (col1,…,col8)
--          ( SELECT … EXCEPT SELECT * FROM staging.wrk_target ) statements.
--          Added an explicit INSERT column list to make the EXCEPT positional
--          match unambiguous. UNION operators removed entirely.
-- No syntax (SFX-*/FNX-*/DTX-*) or defect (DEF-*) fixes were required — the input
-- file parsed clean on Snowflake with 0 residual-Teradata constructs. The only
-- change is the SEM-05 SET-table dedup split.
-- TODO(SME) items (markers only, no SQL change):
--   [SEM-02/FN-LATEST] Latest-value trick SUBSTR(MAX(src.effective_dt || val),11,…)
--                      needs a fixed-width, lexicographically sortable key.
--   [SEM-02]           MAX tie-break non-determinism (resolved with the above).
--   [SEM-06/DTX-10]    param_value implicit string→date cast in the scalar
--                      subquery comparison.
--   [SEM-03]           operating_airline_cd uses SUBSTR(…,11,3) (width 3) while
--                      all other values use SUBSTR(…,11,99) — confirm declared width.

INSERT INTO staging.wrk_target
( airline_cd, flgt_no, flgt_dt, company_cd, direction_ind, operating_airline_cd, operating_flgt_no, operating_sfx_cd )
-- TODO(SME) [SEM-05]: Confirm target column order matches the explicit INSERT list — no DDL supplied.
(
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
    -- TODO(SME) [SEM-06/DTX-10]: param_value implicit string→date cast — confirm format and consider TO_DATE(param_value,'YYYY-MM-DD').
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
);

INSERT INTO staging.wrk_target
( airline_cd, flgt_no, flgt_dt, company_cd, direction_ind, operating_airline_cd, operating_flgt_no, operating_sfx_cd )
(
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
    -- TODO(SME) [SEM-06/DTX-10]: param_value implicit string→date cast — confirm format and consider TO_DATE(param_value,'YYYY-MM-DD').
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
);

INSERT INTO staging.wrk_target
( airline_cd, flgt_no, flgt_dt, company_cd, direction_ind, operating_airline_cd, operating_flgt_no, operating_sfx_cd )
(
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
    -- TODO(SME) [SEM-06/DTX-10]: param_value implicit string→date cast — confirm format and consider TO_DATE(param_value,'YYYY-MM-DD').
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
);