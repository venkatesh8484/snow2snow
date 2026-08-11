
-- <<< SEMANTIC EXPLANATION (generated from 06_explain — edit the .md, not here)
-- Source of truth: 06_explain/output/semantic_SFIssueSET.md
--
-- PURPOSE
-- `SFIssueSET` refreshes `staging.wrk_target` — a **SET table** (confirmed by
-- the reviewer) — with the latest effective flight attributes from three leg
-- sources: the **marketing** leg (`synthetic_mkg_flgt_leg`), the **operational**
-- leg (`synthetic_operational_flgt_leg`), and the **codeshare** leg
-- (`synthetic_codeshare_flgt_leg`). The grain of one output row is one
-- `(airline_cd, flgt_no, flgt_dt)`; for each grain key the statement carries the
-- most-recent `effective_dt` snapshot of five attributes — `company_cd`,
-- `direction_ind`, `operating_airline_cd`, `operating_flgt_no`,
-- `operating_sfx_cd` — sourced from `synthetic_flgt_source` joined to the
-- corresponding leg table. Each of the three leg sources is inserted
-- **independently** with SET-table deduplication reproduced as `EXCEPT SELECT *
-- FROM staging.wrk_target`, so a row that already exists in the target is
-- silently dropped (the Teradata SET-table no-op) and rows two branches produce
-- in common are *not* collapsed across branches (the original Teradata had three
-- independent INSERTs, not one `UNION`). The `UPDATE_CUTOFF` parameter in
-- `synthetic_sys_param` bounds which flight dates are eligible.
--
-- ---
--
-- OPEN SME QUESTIONS
-- 1. **[SEM-05]** Confirm the target `staging.wrk_target` physical column order
--    matches the explicit INSERT list `(airline_cd, flgt_no, flgt_dt, company_cd,
--    direction_ind, operating_airline_cd, operating_flgt_no, operating_sfx_cd)`. No
--    DDL was supplied; the list mirrors the SELECT expression order in every
--    branch.
-- 2. **[SEM-02/FN-LATEST]** Is `effective_dt` a `DATE` or `TIMESTAMP`? What are
--    the display widths of each attribute value (`company_cd`, `direction_ind`,
--    `operating_airline_cd`, `operating_flgt_no`, `operating_sfx_cd`) for `LPAD`?
--    The latest-value trick `SUBSTR(MAX(effective_dt || val), 11, N)` needs a
--    fixed-width, lexicographically sortable key — recommend
--    `TO_CHAR(effective_dt,'YYYY-MM-DD') || LPAD(val::VARCHAR,n,' ')` before `MAX`.
-- 3. **[SEM-02]** Is `effective_dt` unique per `(airline_cd, flgt_no, flgt_dt)`
--    group, or can ties occur? If ties are possible, the `MAX` tie-break is non-
--    deterministic without a fixed-width value suffix.
-- 4. **[SEM-06/DTX-10]** Is `param_value` in `synthetic_sys_param` a date-
--    formatted string (e.g. `'YYYY-MM-DD'`)? Should the comparison be `src.flgt_dt
--    > TO_DATE(param_value, 'YYYY-MM-DD')` to make the cast explicit?
-- 5. **[SEM-02/width consistency]** Is the width-3 truncation on
--    `operating_airline_cd` (`SUBSTR(…, 11, 3)` vs `SUBSTR(…, 11, 99)` for all
--    other attributes) intentional? Confirm the declared width of
--    `operating_airline_cd` in the source DDL — if it can exceed 3 chars, the
--    truncation drops data.
--
-- ---
-- >>> SEMANTIC EXPLANATION

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

-- SEM ▸ SEM-05: SET table (confirmed by reviewer) — 3 independent INSERT…EXCEPT statements reproduce SET-table dedup.
INSERT INTO staging.wrk_target
-- SEM ▸ SEM-05: Explicit INSERT column list added for unambiguous EXCEPT positional match (no DDL supplied — TODO(SME)).
( airline_cd, flgt_no, flgt_dt, company_cd, direction_ind, operating_airline_cd, operating_flgt_no, operating_sfx_cd )
-- TODO(SME) [SEM-05]: Confirm target column order matches the explicit INSERT list — no DDL supplied.
(
    SELECT
          src.airline_cd
        , src.flgt_no
        , src.flgt_dt
        -- TODO(SME) [SEM-02/FN-LATEST]: Latest-value trick needs fixed-width key — format as TO_CHAR(effective_dt,'YYYY-MM-DD') || LPAD(val::VARCHAR,n,' ') before MAX. Confirm effective_dt type and value display widths.
        -- SEM ▸ SEM-02/FN-LATEST: Latest-value trick — needs fixed-width key (TO_CHAR(effective_dt,'YYYY-MM-DD') || LPAD(val,n,' ')) before MAX.
        , SUBSTR(MAX(src.effective_dt || leg.company_cd), 11, 99)      AS company_cd
        , SUBSTR(MAX(src.effective_dt || leg.direction_ind), 11, 99)   AS direction_ind
        -- SEM ▸ SEM-02/width: operating_airline_cd uses width 3 while others use 99 — confirm declared width (TODO(SME)).
        , SUBSTR(MAX(src.effective_dt || leg.operating_airline_cd), 11, 3)
              AS operating_airline_cd
        , SUBSTR(MAX(src.effective_dt || leg.operating_flgt_no), 11, 99)
              AS operating_flgt_no
        , SUBSTR(MAX(src.effective_dt || leg.operating_sfx_cd), 11, 99)
              AS operating_sfx_cd
    FROM   synthetic_flgt_source src
    -- SEM ▸ Branch 1 — marketing carrier view; joins src to leg on marketing_airline_cd / marketing_flgt_no / gmt_flgt_dt.
    JOIN   synthetic_mkg_flgt_leg leg
           ON  src.airline_cd = leg.marketing_airline_cd
           AND src.flgt_no    = leg.marketing_flgt_no
           AND src.flgt_dt    = leg.gmt_flgt_dt
    -- SEM ▸ WHERE filter — excludes no-op legs where departure station equals arrival station.
    WHERE  leg.dep_stn_cd <> leg.arr_stn_cd
    -- TODO(SME) [SEM-06/DTX-10]: param_value implicit string→date cast — confirm format and consider TO_DATE(param_value,'YYYY-MM-DD').
    AND    src.flgt_dt > (
               -- SEM ▸ SEM-06: param_value implicit string→date cast in the UPDATE_CUTOFF scalar subquery — confirm format, consider TO_DATE(param_value,'YYYY-MM-DD').
               SELECT param_value
               FROM   synthetic_sys_param
               -- SEM ▸ UPDATE_CUTOFF parameter bounds eligible flight dates to those after the cutoff.
               WHERE  param_id = 'UPDATE_CUTOFF'
           )
    -- SEM ▸ Grain key (airline_cd, flgt_no, flgt_dt) — collapses to one output row per flight per date.
    GROUP BY
          src.airline_cd
        , src.flgt_no
        , src.flgt_dt
    -- SEM ▸ SEM-05: EXCEPT SELECT * FROM staging.wrk_target deduplicates each branch against existing target rows (SET-table "drop rows already present" semantics).
    EXCEPT
    -- SEM ▸ SEM-05: Target dedup — each branch is deduped against the target independently, not cross-branch via UNION.
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
    -- SEM ▸ Branch 2 — operating carrier view; joins src to leg on operating_airline_cd / operating_flgt_no / gmt_flgt_dt.
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
    -- SEM ▸ Branch 3 — codeshare view; joins src to cs on codeshare_airline_cd / codeshare_flgt_no / gmt_flgt_dt.
    JOIN   synthetic_codeshare_flgt_leg cs
           ON  src.airline_cd = cs.codeshare_airline_cd
           AND src.flgt_no    = cs.codeshare_flgt_no
           AND src.flgt_dt    = cs.gmt_flgt_dt
    -- SEM ▸ WHERE filter (Branch 3) — same dep<>arr exclusion on the codeshare leg alias.
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
