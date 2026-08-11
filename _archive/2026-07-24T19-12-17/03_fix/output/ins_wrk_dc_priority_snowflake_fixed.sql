-- ============================================================================
-- Remediated: Snowflake -> Snowflake | source: 00_input/ins_wrk_dc_priority_snowflake.sql
-- Pipeline: snowflake2snowflake ICM | stage 03_fix | 2026-07-23
-- Semantic ground truth: ../teradata2snowflake/00_input/ins_wrk_dc_priority.bteq
--
-- SYNTAX / FUNCTION FIXES
-- [FNX-01] src 164-165: ZEROIFNULL(x) -> COALESCE(x, 0)  (Teradata fn, undefined on Snowflake)
-- [SFX-01] src 451,456: PERIOD `bus_efast_pd CONTAINS d` -> `d BETWEEN
--          bus_efast_start_dt AND bus_efast_end_dt` (assumed DDL split of PERIOD col)
-- [FNX-03] src ~300,331: `LAST_DAY(x) - 3` -> `DATEADD('day', -3, LAST_DAY(x))`
-- [SFX-03] QUALIFY kept as-is (native on Snowflake) — no rewrite
--
-- DEFECT REPAIRS
-- [DEF-01] src 80-81 & 236-237: duplicate `sac_cd` removed from INSERT + SELECT
-- [DEF-02] src 177-179: `ASallow_...` -> `AS allow_...` (missing space)
-- [DEF-03/04] src 210-230: malformed `CAST((col, 0, 9999999999) AS BIGINT)` +
--          unbalanced parens rebuilt as COALESCE-guarded casts. TODO(SME).
-- [DEF-05] INSERT expects `yq_curr_vlu` but SELECT had no matching expression
--          (131 vs 132). Synthesized from sibling `*_curr_vlu` pattern. TODO(SME).
-- [DEF-06] SELECT aliases normalized to INSERT target column names
--
-- SEMANTIC NOTES (see 06_explain/output/semantic_ins_wrk_dc_priority.md)
-- [SEM-01] yq_curr_vlu / ex_rte is decimal/decimal — no truncation. `/` kept.
-- [SEM-10] `gbp_to_usg_curr` alias also targets GBP; verified against Teradata —
--          join is correct, alias NOT renamed (would hide, not fix).
-- ============================================================================

INSERT INTO wrk_dc_priority
(
    usg_src_cd,
    sale_src_cd,
    src_feed_typ,
    air_no,
    pme_dc_no,
    pme_dc_id,
    dc_no,
    dc_id,
    cpn_no,
    opr_cab_cd,
    opr_cd,
    opr_flt_no,
    opr_flt_sfx_cd,
    up_stn_cd,
    dsg_stn_cd,
    up_dt,
    up_tm,
    arr_dt,
    arr_tm,
    grs_rev_vlu,
    grs_rev_curr_vlu,
    spc_vlu,
    spc_curr_vlu,
    std_comm_vlu,
    std_comm_curr_vlu,
    gsa_comm_vlu,
    gsa_comm_curr_vlu,
    isc_vlu,
    isc_curr_vlu,
    fast_prog_nm,
    fast_card_no_txt,
    cd,
    allow_piece_qty,
    allow_weight_qty,
    allow_weight_unit_cd,
    cdshr_typ_cd,
    opr_franchise_nm,
    consumed_at_issuance_ind,
    cou_status_expired_ind,
    myflight_dt,
    myflight_tm,
    myflightt_cls_cd,
    ex_to_sale_dt,
    ex_to_air_no,
    ex_to_pme_dc_no,
    ex_to_pme_dc_id,
    ex_to_dc_typ_cd,
    ex_to_event_no,
    myflightt_des_cd,
    corp_dealt_ind,
    agy_dealt_ind,
    dealt_ind,
    fl_cd,
    usg_acg_dt,
    intln_bill_dt,
    intln_bill_invoice_no_txt,
    assoc_dc_id,
    assoc_cou_no,
    bkg_cls_cd,
    mktg_cab_cd,
    mktg_cd,
    mktg_myflight_no,
    fr_MYsis_cd,
    cou_seq_no,
    cou_status_cd,
    valid_start_dt,
    valid_end_dt,
    surface_ind,
    dir_cd,
    sac_cd,                     -- [DEF-01] duplicate removed
    cdshr_comm_vlu,
    cdshr_comm_curr_vlu,
    rev_pax_ind,
    rev_src_cd,
    prte_mileage_qty,
    prte_factor_no,
    refund_cd,
    p_create_ts,
    reroute_ind,
    emd_rmk_email_addr_txt,
    cdshr_ind,
    yq_vlu,
    yq_curr_vlu,
    oc_yq_src_cd,
    sa_opr_cd,
    sa_opr_myflight_no,
    sa_opr_myflight_sfx_cd,
    sa_up_dt,
    sa_up_stn_cd,
    sa_dsg_stn_cd,
    sa_cab_cd,
    curr_cnvrt_dt,
    sa_curr_cd,
    cou_usg_receive_dt,
    sa_receive_dt,
    fr_MYse_grp_cd,
    issuance_sub_cd,
    e_issuance_rmk_txt,
    MY_acg_usg_cd,
    invol_ex_cd,
    invol_ex_ind,
    d_surchg_curr_vlu,
    d_surchg_vlu,
    equip_cd,
    seat_used_for_MYg_txt,
    sold_bkg_status_cd,
    stopover_ind,
    usg_usecase_nm,
    route_cd,
    e_fee_owner_cd,
    e_xsb_unit_typ_cd,
    e_xsb_unit_rte_curr_vlu_txt,
    e_xsb_unit_qty_txt,
    e_svc_typ_cd,
    e_svc_no,
    e_atr_grp_cd,
    e_atr_grp_sub_cd,
    e_air_industry_ind,
    degraded_ind,
    full_myflight_up_stn_cd,
    full_myflight_dsg_stn_cd,
    full_myflight_up_dt,
    full_myflight_up_tm,
    full_myflight_arr_dt,
    full_myflight_arr_tm,
    q_surchg_vlu,
    q_surchg_curr_vlu,
    status_change_dt,
    e_rmk_txt,
    chng_of_gauge_ind,
    sched_chng_ind
)
SELECT
    best_usg.src_cd                     AS usg_src_cd,
    best_sa.src_cd                      AS sale_src_cd,
    best_sa.src_feed_typ,
    best_sa.air_no,
    best_sa.pme_dc_no,
    best_sa.pme_dc_id,
    best_sa.dc_no,
    best_sa.dc_id,
    best_sa.cou_no                      AS cpn_no,
    best_usg.opr_cab_cd                 AS opr_cab_cd,
    best_usg.opr_cd                     AS opr_cd,
    best_usg.opr_myflight_no            AS opr_flt_no,
    best_usg.opr_myflight_sfx_cd        AS opr_flt_sfx_cd,
    best_usg.up_stn_cd                  AS up_stn_cd,
    best_usg.dsg_stn_cd                 AS dsg_stn_cd,
    best_usg.up_dt                      AS up_dt,
    best_usg.up_tm                      AS up_tm,
    best_usg.arr_dt                     AS arr_dt,
    best_usg.arr_tm                     AS arr_tm,
    COALESCE(best_usg.grs_rev_vlu, 0)   AS grs_rev_vlu,        -- [FNX-01]
    COALESCE(best_usg.grs_rev_curr_vlu, 0) AS grs_rev_curr_vlu,   -- [FNX-01]
    best_usg.spc_vlu                    AS spc_vlu,
    best_usg.spc_curr_vlu               AS spc_curr_vlu,
    best_usg.std_comm_vlu               AS std_comm_vlu,
    best_usg.std_comm_curr_vlu          AS std_comm_curr_vlu,
    best_usg.gsa_comm_vlu               AS gsa_comm_vlu,
    best_usg.gsa_comm_curr_vlu          AS gsa_comm_curr_vlu,
    best_usg.isc_vlu                    AS isc_vlu,
    best_usg.isc_curr_vlu               AS isc_curr_vlu,
    MY_src.fast_prog_nm                 AS fast_prog_nm,
    best_usg.fast_card_no_txt           AS fast_card_no_txt,
    best_usg.alliance_cd                AS cd,
    best_usg.MYg_allow_piece_qty        AS allow_piece_qty,       -- [DEF-02]
    best_usg.MYg_allow_weight_qty       AS allow_weight_qty,      -- [DEF-02]
    best_usg.MYg_allow_weight_unit_cd   AS allow_weight_unit_cd,  -- [DEF-02]
    best_usg.cdshr_typ_cd               AS cdshr_typ_cd,
    best_usg.opr_franchise_nm           AS opr_franchise_nm,
    best_usg.consumed_at_issuance_ind   AS consumed_at_issuance_ind,
    best_usg.cou_status_expired_ind     AS cou_status_expired_ind,
    best_usg.myflight_dt,
    best_usg.myflight_tm,
    best_usg.myflightt_cls_cd           AS myflightt_cls_cd,
    best_usg.ex_to_sa_dt                AS ex_to_sale_dt,
    best_usg.ex_to_air_no               AS ex_to_air_no,
    best_usg.ex_to_pme_dc_no            AS ex_to_pme_dc_no,
    best_usg.ex_to_pme_dc_id            AS ex_to_pme_dc_id,
    best_usg.ex_to_dc_typ_cd            AS ex_to_dc_typ_cd,
    best_usg.ex_to_event_no             AS ex_to_event_no,
    best_sa.myflightt_des_cd            AS myflightt_des_cd,
    best_sa.corp_dealt_ind              AS corp_dealt_ind,
    best_sa.agy_dealt_ind               AS agy_dealt_ind,
    best_sa.dealt_ind                   AS dealt_ind,
    best_usg.fl_cd                      AS fl_cd,
    MY_src.usg_acg_dt                   AS usg_acg_dt,
    MY_src.intln_bill_dt                AS intln_bill_dt,
    MY_src.intln_bill_invoice_no_txt    AS intln_bill_invoice_no_txt,
    COALESCE(MY_src.assoc_dc_id,  best_sa.assoc_dc_id)  AS assoc_dc_id,
    COALESCE(MY_src.assoc_cou_no, best_sa.assoc_cou_no) AS assoc_cou_no,
    best_sa.bkg_cls_cd                  AS bkg_cls_cd,
    best_sa.mktg_cab_cd                 AS mktg_cab_cd,
    best_sa.mktg_cd                     AS mktg_cd,
    best_sa.mktg_myflight_no            AS mktg_myflight_no,
    best_sa.fr_MYsis_cd                 AS fr_MYsis_cd,

    -- [DEF-03/04] rebuilt from malformed source (src 200-220).
    -- TODO(SME): confirm intent of literal 9999999999 in the original
    -- `(dc_no, 0, 9999999999)` — treated here as COALESCE default 0 with the
    -- range bound dropped.
    CASE
        WHEN (
            COALESCE(
                (CAST(COALESCE(best_sa.dc_no, 0) AS BIGINT)
                 - CAST(COALESCE(best_sa.pme_dc_no, 0) AS BIGINT)
                ) * 4
            , 0) + best_sa.cou_no
        ) BETWEEN 1 AND 16
        THEN (
            COALESCE(
                (CAST(COALESCE(best_sa.dc_no, 0) AS BIGINT)
                 - CAST(COALESCE(best_sa.pme_dc_no, 0) AS BIGINT)
                ) * 4
            , 0) + best_sa.cou_no
        )
        ELSE NULL
    END AS cou_seq_no,

    best_usg.cou_status_cd              AS cou_status_cd,
    MY_src.valid_start_dt               AS valid_start_dt,
    MY_src.valid_end_dt                 AS valid_end_dt,

    COALESCE(best_usg.surface_ind, MY_src.surface_ind) AS surface_ind,
    COALESCE(best_usg.dir_cd, MY_src.dir_cd)           AS dir_cd,
    COALESCE(best_usg.sac_cd, MY_src.sac_cd)           AS sac_cd,  -- [DEF-01] duplicate removed

    MY_src.cdshr_comm_vlu               AS cdshr_comm_vlu,

    CASE
        WHEN best_usg.src_cd = 'MY'
        THEN best_usg.cdshr_comm_curr_vlu
        ELSE MY_src.cdshr_comm_vlu * gbp_to_usg_curr.ex_rte
    END AS cdshr_comm_curr_vlu,

    best_usg.rev_pax_ind                AS rev_pax_ind,
    best_usg.rev_src_cd                 AS rev_src_cd,

    MY_src.prte_mileage_qty,
    MY_src.prte_factor_no,
    MY_src.refund_cd,

    MY_src.p_create_ts,
    MY_src.reroute_ind,
    MY_src.e_rmk_email_addr_txt         AS emd_rmk_email_addr_txt,

    CASE
        WHEN (
            NULLIF(best_usg.opr_cd, '') IS NOT NULL
            AND NULLIF(best_sa.mktg_cd, '') IS NOT NULL
            AND best_sa.mktg_cd <> best_usg.opr_cd
        )
        THEN 'Y'
        ELSE 'N'
    END AS cdshr_ind,

    CASE
        WHEN (best_sa.air_no = '000' AND best_usg.src_cd <> 'MY')
        THEN (best_sa.yq_curr_vlu / sa_curr_to_gbp.ex_rte)

        WHEN best_sa.air_no = '000'
        THEN MY_src.yq_vlu

        WHEN (best_usg.opr_cd = 'MY' AND MY_src.oc_yq_src_cd = 'R')
        THEN MY_src.yq_vlu

        WHEN (
                best_usg.opr_cd = 'MY'
            AND ty_t5.air_des_cd IS NOT NULL
            AND best_sa.sa_priority_no = 1
        )
        THEN (best_sa.yq_curr_vlu / sa_curr_to_gbp.ex_rte)

        WHEN (
                best_usg.opr_cd = 'MY'
            AND best_usg.myflightt_cls_cd IN ('Z','U','P','X')
            AND (
                    (up_ctry_grp.grouping_sub_typ_txt = 'EU' AND disch_ctry_grp.grouping_sub_typ_txt = 'AM')
                 OR (up_ctry_grp.grouping_sub_typ_txt = 'AM' AND disch_ctry_grp.grouping_sub_typ_txt = 'EU')
                )
        )
        THEN 0

        WHEN (
                best_usg.opr_cd = 'MY'
            AND best_sa.sa_priority_no = 1
            AND dtrp.air_no IS NOT NULL
            AND best_usg.up_dt > DATEADD('day', -3, LAST_DAY(dtrp.remittance_received_to_dt))  -- [FNX-03]
            AND (best_sa.yq_curr_vlu / sa_curr_to_gbp.ex_rte) < 1000
        )
        THEN (best_sa.yq_curr_vlu / sa_curr_to_gbp.ex_rte)

        WHEN best_usg.opr_cd = 'MY'
        THEN 0

        WHEN best_sa.yq_vlu > 0
        THEN (best_sa.yq_curr_vlu / sa_curr_to_gbp.ex_rte)

        WHEN best_usg.yq_vlu > 0
        THEN best_usg.yq_vlu
    END AS yq_vlu,

    -- [DEF-05] synthesized: source SELECT had no expression for yq_curr_vlu.
    -- TODO(SME): confirm business rule for original-currency YQ value.
    COALESCE(best_sa.yq_curr_vlu, best_usg.yq_curr_vlu) AS yq_curr_vlu,

    CASE
        WHEN best_sa.air_no = '000'
        THEN ''

        WHEN (best_usg.opr_cd = 'MY' AND MY_src.oc_yq_src_cd = 'R')
        THEN 'R'

        WHEN (
                best_usg.opr_cd = 'MY'
            AND ty_t5.air_des_cd IS NULL
            AND dtrp.air_no IS NOT NULL
            AND best_usg.up_dt <= DATEADD('day', -3, LAST_DAY(dtrp.remittance_received_to_dt))  -- [FNX-03]
        )
        THEN 'R'

        WHEN (
                best_usg.opr_cd = 'MY'
            AND best_sa.sa_priority_no = 1
            AND dtrp.air_no IS NOT NULL
            AND (best_sa.yq_curr_vlu / sa_curr_to_gbp.ex_rte) < 1000
        )
        THEN 'F'

        ELSE ''
    END AS oc_yq_src_cd,

    COALESCE(best_sa.sa_opr_cd,              MY_src.sa_opr_cd)              AS sa_opr_cd,               -- [DEF-06]
    COALESCE(best_sa.sa_opr_myflight_no,     MY_src.sa_opr_myflight_no)     AS sa_opr_myflight_no,      -- [DEF-06]
    COALESCE(best_sa.sa_opr_myflight_sfx_cd, MY_src.sa_opr_myflight_sfx_cd) AS sa_opr_myflight_sfx_cd,  -- [DEF-06]
    COALESCE(best_sa.sa_up_dt,               MY_src.sa_up_dt)               AS sa_up_dt,                -- [DEF-06]
    COALESCE(best_sa.sa_up_stn_cd,           MY_src.sa_up_stn_cd)           AS sa_up_stn_cd,            -- [DEF-06]
    COALESCE(best_sa.sa_dsg_stn_cd,          MY_src.sa_dsg_stn_cd)          AS sa_dsg_stn_cd,           -- [DEF-06]
    COALESCE(best_sa.sa_cab_cd,              MY_src.sa_cab_cd)              AS sa_cab_cd,               -- [DEF-06]

    best_usg.curr_cnvrt_dt,
    best_usg.sa_curr_cd,
    best_usg.cou_usg_receive_dt,
    best_sa.sa_receive_dt,
    best_usg.fr_MYse_grp_cd,
    best_sa.issuance_sub_cd,
    best_sa.e_issuance_rmk_txt,

    CASE WHEN MY_src.air_no IS NOT NULL THEN 'Y' ELSE 'N' END AS MY_acg_usg_cd,

    MY_src.invol_ex_cd,
    best_usg.invol_ex_ind,

    best_usg.d_surchg_curr_vlu,
    best_usg.d_surchg_vlu,
    best_usg.equip_cd,
    best_usg.seat_used_for_MYg_txt,
    best_usg.sold_bkg_status_cd,
    best_usg.stopover_ind,
    best_usg.usg_usecase_nm,
    best_usg.route_cd,

    best_usg.e_fee_owner_cd,
    best_usg.e_xsb_unit_typ_cd,
    best_usg.e_xsb_unit_rte_curr_vlu_txt,
    best_usg.e_xsb_unit_qty_txt,
    best_usg.e_svc_typ_cd,
    best_usg.e_svc_no,
    best_usg.e_atr_grp_cd,
    best_usg.e_atr_grp_sub_cd,
    best_usg.e_air_industry_ind,
    best_usg.degraded_ind,

    MY_src.full_myflight_up_stn_cd,
    MY_src.full_myflight_dsg_stn_cd,
    MY_src.full_myflight_up_dt,
    MY_src.full_myflight_up_tm,
    MY_src.full_myflight_arr_dt,
    MY_src.full_myflight_arr_tm,

    best_usg.q_surchg_vlu,
    best_usg.q_surchg_curr_vlu,

    MY_src.status_change_dt,
    MY_src.e_rmk_txt,
    MY_src.chng_of_gauge_ind,
    MY_src.sched_chng_ind

FROM (
        SELECT *
        FROM wrk_dc_priority_ranked
        QUALIFY ROW_NUMBER() OVER (        -- [SFX-03] QUALIFY kept
            PARTITION BY dc_id, cou_no
            ORDER BY sa_priority_no
        ) = 1
     ) best_sa

INNER JOIN (
        SELECT *
        FROM wrk_dc_priority_ranked
        QUALIFY ROW_NUMBER() OVER (        -- [SFX-03] QUALIFY kept
            PARTITION BY dc_id, cou_no
            ORDER BY usg_priority_no
        ) = 1
     ) best_usg
     ON  best_sa.dc_id  = best_usg.dc_id
     AND best_sa.cou_no = best_usg.cou_no

LEFT JOIN wrk_dc_priority_ranked MY_src
     ON  best_sa.dc_id  = MY_src.dc_id
     AND best_sa.cou_no = MY_src.cou_no
     AND MY_src.src_cd  = 'MY'

LEFT JOIN wrkange_rate sa_curr_to_gbp
     ON  best_sa.sa_curr_cd        = sa_curr_to_gbp.curr_from_cd
     AND sa_curr_to_gbp.curr_to_cd = 'GBP'
     AND sa_curr_to_gbp.ex_rte_typ = 'I5D'
     AND best_usg.curr_cnvrt_dt BETWEEN sa_curr_to_gbp.efast_dt AND sa_curr_to_gbp.exp_dt

LEFT JOIN wrkange_rate gbp_to_usg_curr
     ON  gbp_to_usg_curr.curr_from_cd = best_usg.sa_curr_cd
     AND gbp_to_usg_curr.curr_to_cd   = 'GBP'
     AND gbp_to_usg_curr.ex_rte_typ   = 'I5D'
     AND best_usg.curr_cnvrt_dt BETWEEN gbp_to_usg_curr.efast_dt AND gbp_to_usg_curr.exp_dt

LEFT JOIN wrkg_loc_hierarchy dep_loc_hierarchy
     ON best_usg.up_stn_cd = dep_loc_hierarchy.stn_cd

LEFT JOIN wrkg_loc_hierarchy arr_loc_hierarchy
     ON best_usg.dsg_stn_cd = arr_loc_hierarchy.stn_cd

LEFT JOIN ref_ctry up_ctry_grp
     ON  dep_loc_hierarchy.country_cd     = up_ctry_grp.country_cd
     AND up_ctry_grp.grouping_typ_txt     = 'QY'
     -- [SFX-01] PERIOD CONTAINS -> BETWEEN on split columns.
     -- TODO(SME): confirm PERIOD column split names in migrated ref_ctry DDL.
     AND best_usg.up_dt BETWEEN up_ctry_grp.bus_efast_start_dt AND up_ctry_grp.bus_efast_end_dt   /* v1.26 */

LEFT JOIN ref_ctry disch_ctry_grp
     ON  arr_loc_hierarchy.country_cd     = disch_ctry_grp.country_cd
     AND disch_ctry_grp.grouping_typ_txt  = 'QY'
     -- [SFX-01] PERIOD CONTAINS -> BETWEEN on split columns.
     AND best_usg.up_dt BETWEEN disch_ctry_grp.bus_efast_start_dt AND disch_ctry_grp.bus_efast_end_dt   /* v1.26 */

LEFT JOIN b_dc_tax_remittance_partner dtrp
     ON  best_usg.air_no = dtrp.air_no
     AND best_usg.up_dt >= dtrp.agmt_start_dt

LEFT JOIN (
        SELECT
            fna.air_des_cd,
            fng.myflight_no,
            fng.efast_dt,
            fng.exp_dt
        FROM QYtna_burst fna
        INNER JOIN QYtng fng
                ON fna.myflightno_grp_cd = fng.myflightno_grp_cd
        WHERE fna.air_des_cd  = 'MY'
          AND fng.bus_unit_cd IN ('tyR','tyS')
     ) ty_t5
     ON  best_usg.opr_cd          = ty_t5.air_des_cd
     AND best_usg.opr_myflight_no = ty_t5.myflight_no
     AND best_usg.up_dt BETWEEN ty_t5.efast_dt AND ty_t5.exp_dt

QUALIFY ROW_NUMBER() OVER (                -- [SFX-03] QUALIFY kept
            PARTITION BY best_sa.dc_id, best_sa.cou_no
            ORDER BY sa_curr_to_gbp.efast_dt DESC,
                     gbp_to_usg_curr.efast_dt DESC
        ) = 1;
