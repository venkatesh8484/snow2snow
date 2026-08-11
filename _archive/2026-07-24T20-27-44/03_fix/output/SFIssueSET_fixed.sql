-- FIX LOG (issues repaired during remediation)
-- [SEM-05] lines 1,30,60: single INSERT ... UNION ... UNION collapsed three
--          independent Teradata SET-table INSERTs into one statement. UNION
--          de-duplicates ACROSS branches (wrong: each SET-table INSERT dedups
--          only against rows already in the target). Split back into THREE
--          independent INSERT INTO staging.wrk_target SELECT ... statements.
--          TODO(SME): confirm whether staging.wrk_target is a SET table; if so,
--          each INSERT must be wrapped as
--          INSERT INTO staging.wrk_target ( SELECT ... EXCEPT SELECT * FROM
--          staging.wrk_target ) to reproduce Teradata SET-table dedup.
-- [FN-LATEST] lines 4-9,34-39,64-69: SUBSTR(MAX(effective_dt || col),11,n)
--          latest-value trick relied on a fixed-width concatenation key. Wrapped
--          effective_dt in TO_CHAR(...,'YYYY-MM-DD') (fixed 10 chars) and col in
--          LPAD(col::VARCHAR,W,' ') so MAX picks the latest effective_dt row
--          deterministically. LTRIM() added on the result to strip the leading
--          pad and preserve the original unpadded output value.
--          TODO(SME): LPAD widths (company_cd=3, direction_ind=1,
--          operating_airline_cd=3, operating_flgt_no=5, operating_sfx_cd=2)
--          must be >= the max column length or LPAD will truncate; confirm
--          against source DDL. Flag if any value legitimately starts with a
--          space (SEM-03) since LTRIM would drop it.
-- [SEM-06] lines 4-9,34-39,64-69: implicit string cast in || concatenation made
--          explicit -- effective_dt via TO_CHAR(...,'YYYY-MM-DD'), each col via
--          ::VARCHAR.
-- [SEM-06] lines 17-24,47-54,77-84: src.flgt_dt > (SELECT param_value ...) relies
--          on an implicit cast of param_value. Left as-is (cannot confirm
--          param_value type/format from this script).
--          TODO(SME): if param_value is VARCHAR, wrap the subquery in
--          TO_DATE(param_value,'YYYY-MM-DD') (applies to all three branches).
--
-- TODO(SME): effective_dt assumed DATE; TO_CHAR(...,'YYYY-MM-DD') yields a
--            fixed 10-char key. If effective_dt is already a VARCHAR/timestamp,
--            confirm the format so the SUBSTR offset (11) stays correct.

INSERT INTO staging.wrk_target
SELECT
      src.airline_cd
    , src.flgt_no
    , src.flgt_dt
    , LTRIM(SUBSTR(MAX(TO_CHAR(src.effective_dt,'YYYY-MM-DD')
                       || LPAD(leg.company_cd::VARCHAR, 3, ' ')), 11, 99))
          AS company_cd
    , LTRIM(SUBSTR(MAX(TO_CHAR(src.effective_dt,'YYYY-MM-DD')
                       || LPAD(leg.direction_ind::VARCHAR, 1, ' ')), 11, 99))
          AS direction_ind
    , LTRIM(SUBSTR(MAX(TO_CHAR(src.effective_dt,'YYYY-MM-DD')
                       || LPAD(leg.operating_airline_cd::VARCHAR, 3, ' ')), 11, 3))
          AS operating_airline_cd
    , LTRIM(SUBSTR(MAX(TO_CHAR(src.effective_dt,'YYYY-MM-DD')
                       || LPAD(leg.operating_flgt_no::VARCHAR, 5, ' ')), 11, 99))
          AS operating_flgt_no
    , LTRIM(SUBSTR(MAX(TO_CHAR(src.effective_dt,'YYYY-MM-DD')
                       || LPAD(leg.operating_sfx_cd::VARCHAR, 2, ' ')), 11, 99))
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
;

INSERT INTO staging.wrk_target
SELECT
      src.airline_cd
    , src.flgt_no
    , src.flgt_dt
    , LTRIM(SUBSTR(MAX(TO_CHAR(src.effective_dt,'YYYY-MM-DD')
                       || LPAD(leg.company_cd::VARCHAR, 3, ' ')), 11, 99))
          AS company_cd
    , LTRIM(SUBSTR(MAX(TO_CHAR(src.effective_dt,'YYYY-MM-DD')
                       || LPAD(leg.direction_ind::VARCHAR, 1, ' ')), 11, 99))
          AS direction_ind
    , LTRIM(SUBSTR(MAX(TO_CHAR(src.effective_dt,'YYYY-MM-DD')
                       || LPAD(leg.operating_airline_cd::VARCHAR, 3, ' ')), 11, 3))
          AS operating_airline_cd
    , LTRIM(SUBSTR(MAX(TO_CHAR(src.effective_dt,'YYYY-MM-DD')
                       || LPAD(leg.operating_flgt_no::VARCHAR, 5, ' ')), 11, 99))
          AS operating_flgt_no
    , LTRIM(SUBSTR(MAX(TO_CHAR(src.effective_dt,'YYYY-MM-DD')
                       || LPAD(leg.operating_sfx_cd::VARCHAR, 2, ' ')), 11, 99))
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
;

INSERT INTO staging.wrk_target
SELECT
      src.airline_cd
    , src.flgt_no
    , src.flgt_dt
    , LTRIM(SUBSTR(MAX(TO_CHAR(src.effective_dt,'YYYY-MM-DD')
                       || LPAD(cs.company_cd::VARCHAR, 3, ' ')), 11, 99))
          AS company_cd
    , LTRIM(SUBSTR(MAX(TO_CHAR(src.effective_dt,'YYYY-MM-DD')
                       || LPAD(cs.direction_ind::VARCHAR, 1, ' ')), 11, 99))
          AS direction_ind
    , LTRIM(SUBSTR(MAX(TO_CHAR(src.effective_dt,'YYYY-MM-DD')
                       || LPAD(cs.operating_airline_cd::VARCHAR, 3, ' ')), 11, 3))
          AS operating_airline_cd
    , LTRIM(SUBSTR(MAX(TO_CHAR(src.effective_dt,'YYYY-MM-DD')
                       || LPAD(cs.operating_flgt_no::VARCHAR, 5, ' ')), 11, 99))
          AS operating_flgt_no
    , LTRIM(SUBSTR(MAX(TO_CHAR(src.effective_dt,'YYYY-MM-DD')
                       || LPAD(cs.operating_sfx_cd::VARCHAR, 2, ' ')), 11, 99))
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
;