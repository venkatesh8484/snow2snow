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


-- <<< SEMANTIC EXPLANATION (generated from 06_explain — edit the .md, not here)
-- Source of truth: 06_explain/output/semantic_SFIssueSET.md
--
-- PURPOSE
-- This statement builds a flight-issue staging table, `staging.wrk_target`, at
-- the grain of **one row per `(airline_cd, flgt_no, flgt_dt)`** — i.e. one row
-- per airline / flight-number / flight-date triple. It reads the common flight
-- source `synthetic_flgt_source` (`src`) and enriches each flight with the
-- **latest effective** descriptive attributes (company code, direction
-- indicator, and the operating airline / flight-number / suffix triplet) drawn
-- from **three leg sources unioned together**: the marketing leg table
-- (`synthetic_mkg_flgt_leg`), the operational leg table
-- (`synthetic_operational_flgt_leg`), and the codeshare leg table
-- (`synthetic_codeshare_flgt_leg`). The three branches are joined by `UNION`, so
-- the output is the de-duplicated union of marketing-, operational-, and
-- codeshare-derived flight attributes. Only legs that actually move (departure
-- station differs from arrival station) and only flights dated after the
-- `UPDATE_CUTOFF` system parameter are retained. The "latest effective" value
-- for each attribute is selected per group via the `SUBSTR(MAX(effective_dt ||
-- val), 11, N)` latest-value trick.
--
-- ---
--
-- OPEN SME QUESTIONS
-- Each is phrased as a decision the reviewer must make. All are also present as
-- `TODO(SME)` markers in `03_fix/output/SFIssueSET_fixed.sql`.
--
-- 1. **[SEM-05] Is `staging.wrk_target` a SET table?** If yes, each `UNION`
--    branch must be ported as a separate `INSERT INTO staging.wrk_target (SELECT …
--    EXCEPT SELECT * FROM staging.wrk_target)` — never a single cross-branch
--    `UNION`. Do **not** assume SET.
-- 2. **[SEM-05] Should the three branches be `UNION ALL` or separate INSERTs?**
--    Confirm the intended set-semantics. `UNION` de-duplicates across branches; if
--    the original used separate INSERTs (SET-table dedup) or `UNION ALL`, the
--    current `UNION` is wrong.
-- 3. **[SEM-02 / FN-LATEST] Is `src.effective_dt` a DATE or a TIMESTAMP, and
--    what are the max display widths of the concatenated value columns?** The
--    latest-value trick needs a fixed-width key — format as
--    `TO_CHAR(effective_dt,'YYYY-MM-DD') || LPAD(val::VARCHAR, N, ' ')` before
--    `MAX`. Confirm the type and the per-column `N` for `LPAD`.
-- 4. **[SEM-02] Is `effective_dt` unique per `(airline_cd, flgt_no, flgt_dt)`
--    group, or can ties occur?** If ties are possible, `MAX(effective_dt || val)`
--    picks the lexicographically larger *value*, not necessarily the intended row;
--    a deterministic tie-break is needed.
-- 5. **[SEM-06 / DTX-10] Is `synthetic_sys_param.param_value` a date-formatted
--    string (e.g. `YYYY-MM-DD`)?** Should the comparison be `src.flgt_dt >
--    TO_DATE(param_value, 'YYYY-MM-DD')` to make the cast explicit and avoid
--    Snowflake's stricter implicit-cast behaviour?
-- 6. **[consistency] Is the width-3 truncation on `operating_airline_cd`
--    (`SUBSTR(..., 11, 3)`) intentional?** All other value columns use `SUBSTR(...,
--    11, 99)`. Likely intentional (airline codes are 2–3 chars) but unconfirmable
--    without ground truth.
--
-- ---
-- >>> SEMANTIC EXPLANATION

-- TODO(SME) [SEM-05]: Is staging.wrk_target a SET table? If yes, each UNION branch must be a separate INSERT INTO staging.wrk_target (SELECT ... EXCEPT SELECT * FROM staging.wrk_target). Do not assume SET.
-- SEM ▸ SEM-05: Is staging.wrk_target a SET table? If yes, each branch must be a separate INSERT … EXCEPT; never a single cross-branch UNION.
INSERT INTO staging.wrk_target
SELECT
      src.airline_cd
    , src.flgt_no
    , src.flgt_dt
    -- TODO(SME) [SEM-02/FN-LATEST]: Latest-value trick needs fixed-width key — format as TO_CHAR(effective_dt,'YYYY-MM-DD') || LPAD(val::VARCHAR,n,' ') before MAX. Confirm effective_dt type and value display widths.
    -- SEM ▸ SEM-02/FN-LATEST: Latest-value trick needs fixed-width key (TO_CHAR(effective_dt,'YYYY-MM-DD') || LPAD(val,N,' ')) before MAX.
    , SUBSTR(MAX(src.effective_dt || leg.company_cd), 11, 99)      AS company_cd
    , SUBSTR(MAX(src.effective_dt || leg.direction_ind), 11, 99)   AS direction_ind
    -- SEM ▸ SEM-02/consistency: width-3 truncation on operating_airline_cd — confirm intentional vs other columns' width 99.
    , SUBSTR(MAX(src.effective_dt || leg.operating_airline_cd), 11, 3)
          AS operating_airline_cd
    , SUBSTR(MAX(src.effective_dt || leg.operating_flgt_no), 11, 99)
          AS operating_flgt_no
    , SUBSTR(MAX(src.effective_dt || leg.operating_sfx_cd), 11, 99)
          AS operating_sfx_cd
FROM   synthetic_flgt_source src
-- SEM ▸ Branch 1: marketing-leg attribution — joins src to marketing carrier/flight/date keys.
JOIN   synthetic_mkg_flgt_leg leg
       ON  src.airline_cd = leg.marketing_airline_cd
       AND src.flgt_no    = leg.marketing_flgt_no
       AND src.flgt_dt    = leg.gmt_flgt_dt
-- SEM ▸ WHERE filter: excludes same-station (ground-only/cancellation) legs; only point-to-point legs survive.
WHERE  leg.dep_stn_cd <> leg.arr_stn_cd
AND    src.flgt_dt > (
           -- TODO(SME) [SEM-06/DTX-10]: param_value implicit string→date cast — confirm format and consider TO_DATE(param_value,'YYYY-MM-DD').
           -- SEM ▸ SEM-06: param_value implicit string→date cast — confirm ISO format and consider TO_DATE(param_value,'YYYY-MM-DD').
           SELECT param_value
           FROM   synthetic_sys_param
           WHERE  param_id = 'UPDATE_CUTOFF'
       )
-- SEM ▸ Grain: one output row per (airline_cd, flgt_no, flgt_dt); five non-key columns resolved by the latest-value trick.
GROUP BY
      src.airline_cd
    , src.flgt_no
    , src.flgt_dt

-- TODO(SME) [SEM-05]: UNION vs UNION ALL — confirm set-semantics. UNION de-duplicates across branches; if the original used separate INSERTs (SET-table dedup) or UNION ALL, this UNION is wrong.
-- SEM ▸ SEM-05: UNION (not UNION ALL) de-duplicates across the three branches — confirm this matches original set-semantics.
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
-- SEM ▸ Branch 2: operational-leg attribution — joins src to operating carrier/flight/date keys.
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
-- SEM ▸ Branch 3: codeshare-leg attribution — joins src to codeshare carrier/flight/date keys; attributes read from cs alias.
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
