
-- <<< SEMANTIC EXPLANATION (generated from 06_explain — edit the .md, not here)
-- Source of truth: 06_explain/output/semantic_SFIssueSET.md
--
-- PURPOSE
-- `SFIssueSET.sql` populates the target table `staging.wrk_target` with one row
-- per `(airline_cd, flgt_no, flgt_dt)` flight key, attaching the **latest**
-- known `company_cd`, `direction_ind`, `operating_airline_cd`,
-- `operating_flgt_no`, and `operating_sfx_cd` attributes for that flight. The
-- data is sourced from `synthetic_flgt_source` joined to three leg tables —
-- `synthetic_mkg_flgt_leg` (marketing), `synthetic_operational_flgt_leg`
-- (operational), and `synthetic_codeshare_flgt_leg` (codeshare) — one branch per
-- leg type. Each branch groups by the flight key, picks the most recent
-- `effective_dt` per attribute using the `SUBSTR(MAX(effective_dt || val), 11,
-- N)` "latest-value trick", and filters to flights after the `UPDATE_CUTOFF`
-- parameter. The target is a **SET table** (reviewer-confirmed), so each branch
-- must dedup its rows **against the target's existing rows** — not against the
-- other branches. The remediation therefore splits the original single `INSERT …
-- UNION … UNION` into three independent `INSERT … ( SELECT … EXCEPT SELECT *
-- FROM staging.wrk_target )` statements, which reproduces Teradata SET-table
-- "drop rows already present" semantics on Snowflake.
--
-- ---
--
-- OPEN SME QUESTIONS
-- 1. **SEM-05 (sub) — target column order.** Does the physical column order of
--    `staging.wrk_target` match the explicit INSERT list `(airline_cd, flgt_no,
--    flgt_dt, company_cd, direction_ind, operating_airline_cd, operating_flgt_no,
--    operating_sfx_cd)`? If not, the `EXCEPT SELECT * FROM staging.wrk_target`
--    positional match will mismatch. Supply the target `CREATE TABLE` DDL to
--    confirm.
-- 2. **SEM-02 / FN-LATEST — latest-value trick key width.** Is `effective_dt` a
--    `DATE` or `TIMESTAMP`, and are the concatenated values fixed-width? If not,
--    `MAX(effective_dt || val)` can pick the wrong row. Confirm to apply the safe
--    form `TO_CHAR(effective_dt,'YYYY-MM-DD') || LPAD(val::VARCHAR,n,' ')`.
-- 3. **SEM-06 / DTXX-10 — `param_value` cast.** What is the string format of
--    `synthetic_sys_param.param_value` for `param_id = 'UPDATE_CUTOFF'`? Should the
--    comparison be `src.flgt_dt > TO_DATE(param_value,'YYYY-MM-DD')`?
-- 4. **SEM-03 — `CHAR(n)` padding.** Are any of the join/`EXCEPT` keys
--    (`airline_cd`, `flgt_no`, `company_cd`, `*_stn_cd`, `operating_*`) declared
--    `CHAR(n)`? If so, wrap both sides of each predicate in `RTRIM`/`TRIM` to
--    preserve Teradata blank-padding semantics.
-- 5. **SEM-04 — timezone.** Are `flgt_dt` / `gmt_flgt_dt` / `effective_dt`
--    `TIMESTAMP_TZ`, `TIMESTAMP_NTZ`, or `DATE`? Pin the session `TIMEZONE` or pick
--    NTZ/TZ to match the source.
-- 6. **SEM-10 — join-key direction.** Do the three branches correctly join
--    `synthetic_flgt_source` to the marketing / operational / codeshare leg tables
--    on the keys shown? Confirm against Teradata ground truth when supplied.
--
-- ---
-- >>> SEMANTIC EXPLANATION

-- FIX LOG (issues repaired during remediation)
-- [SEM-05] line 1, 32, 64: SET-table dedup (confirmed by reviewer in
--          02_rules/06_lessons_learned.md — "This is a SET table in teradata.
--          So, there should not be any duplicates. You need to handle the dedup
--          logic in the query.") — split the single
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
--   [SEM-04]           flgt_dt / gmt_flgt_dt / effective_dt TIMESTAMP vs
--                      TIMESTAMP_TZ vs DATE — confirm to pin NTZ/TZ.
--   [SEM-10]           Join-key direction (marketing/operating/codeshare) —
--                      confirm against Teradata ground truth.
--   [SEM-05(sub)]      Target column order unknown (no DDL) — confirm the
--                      explicit INSERT list matches the physical column order.

-- SEM ▸ SEM-05 SET-table dedup: 3 independent INSERT…EXCEPT statements replace the single INSERT…UNION…UNION (reviewer-confirmed SET)
INSERT INTO staging.wrk_target
( airline_cd, flgt_no, flgt_dt, company_cd, direction_ind, operating_airline_cd, operating_flgt_no, operating_sfx_cd )
-- TODO(SME) [SEM-05]: Confirm target column order matches the explicit INSERT list — no DDL supplied.
(
    SELECT
          src.airline_cd
        , src.flgt_no
        , src.flgt_dt
        -- TODO(SME) [SEM-02/FN-LATEST]: Latest-value trick needs fixed-width key — format as TO_CHAR(effective_dt,'YYYY-MM-DD') || LPAD(val::VARCHAR,n,' ') before MAX. Confirm effective_dt type and value display widths.
        -- SEM ▸ SEM-02/FN-LATEST: latest-value trick needs a fixed-width sortable key (TO_CHAR(effective_dt,'YYYY-MM-DD') || LPAD(val,n,' '))
        , SUBSTR(MAX(src.effective_dt || leg.company_cd), 11, 99)      AS company_cd
        , SUBSTR(MAX(src.effective_dt || leg.direction_ind), 11, 99)   AS direction_ind
        -- SEM ▸ SEM-03: width 3 vs 99 elsewhere — confirm declared width of operating_airline_cd
        , SUBSTR(MAX(src.effective_dt || leg.operating_airline_cd), 11, 3)
              AS operating_airline_cd
        , SUBSTR(MAX(src.effective_dt || leg.operating_flgt_no), 11, 99)
              AS operating_flgt_no
        , SUBSTR(MAX(src.effective_dt || leg.operating_sfx_cd), 11, 99)
              AS operating_sfx_cd
    FROM   synthetic_flgt_source src
    -- SEM ▸ SEM-10: join-key direction (marketing) — confirm against Teradata ground truth
    JOIN   synthetic_mkg_flgt_leg leg
           ON  src.airline_cd = leg.marketing_airline_cd
           AND src.flgt_no    = leg.marketing_flgt_no
           AND src.flgt_dt    = leg.gmt_flgt_dt
    WHERE  leg.dep_stn_cd <> leg.arr_stn_cd
    -- TODO(SME) [SEM-06/DTX-10]: param_value implicit string→date cast — confirm format and consider TO_DATE(param_value,'YYYY-MM-DD').
    -- SEM ▸ SEM-06/DTX-10: param_value implicit cast feeds this cutoff comparison
    AND    src.flgt_dt > (
               -- SEM ▸ SEM-06/DTX-10: implicit string→date cast — consider TO_DATE(param_value,'YYYY-MM-DD')
               SELECT param_value
               FROM   synthetic_sys_param
               WHERE  param_id = 'UPDATE_CUTOFF'
           )
    GROUP BY
          src.airline_cd
        , src.flgt_no
        , src.flgt_dt
    -- SEM ▸ SEM-05: EXCEPT SELECT * FROM staging.wrk_target reproduces Teradata SET "drop rows already present" per branch
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
    -- SEM ▸ SEM-10: join-key direction (operational) — confirm against Teradata ground truth
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
    -- SEM ▸ SEM-10: join-key direction (codeshare) — confirm against Teradata ground truth
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
