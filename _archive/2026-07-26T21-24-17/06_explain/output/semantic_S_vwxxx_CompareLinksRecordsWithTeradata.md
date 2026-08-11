# Stage 6 — Semantic explanation: `S_vwxxx_CompareLinksRecordsWithTeradata`

**Fixed SQL:** `03_fix/output/S_vwxxx_CompareLinksRecordsWithTeradata_fixed.snowsql`
**Teradata ground truth:** **Not supplied.** No
`00_input/S_vwxxx_CompareLinksRecordsWithTeradata.teradata.sql` exists. Every
semantic inference below is flagged `TODO(SME)` and must be confirmed by a
subject-matter expert before sign-off.
**Dialect target:** Snowflake (`.snowsql` — SnowSQL client layer; 14 `<% %>`
template tags preserved verbatim per SNZ-01).

---

## 1. Purpose

This script is a **flight-link reconciliation / finalise-inserts** pipeline that
compares the *old* (current production) set of flight-schedule links in
`BASE.FLT_SCHEDULE_LINKS` against a *new* candidate set in
`STAGING.WRK_FLT_SCHED_LINKS` for a reporting period bounded by two template
dates (`Period_start` / `Period_end`). It produces three transient staging
tables:

1. `staging.Lkp_InFltLegSeqNo` — a deduplicated lookup of **inbound** flight-leg
   sequence numbers from `BASE.schedule_sales_flt_leg` joined to
   `BASE.schedule_sales_mkg_leg` (marketing carrier `BA`), keyed on operating
   airline / flight number / suffix / scheduled-arrival time / station pair.
2. `STAGING.Rtr_DirectFlowOfLinksRecords` — a **FULL OUTER JOIN** of old vs new
   links, emitting one row per link key with `OLD_*` and `NEW_*` prefixed
   columns plus two concatenated "record" strings (`OLD_concat_record`,
   `NEW_concat_record`). A `filtered` CTE keeps only rows that are new, expired,
   or whose concatenated record differs — i.e. the net change set.
3. `STAGING.ExpFinalyseInserts` — the final insert-ready set: for each changed
   link it resolves the **inbound** and **outbound** flight-leg sequence numbers
   (looking up `Lkp_InFltLegSeqNo` and a sibling `Lkp_OutFltLegSeqNo`), validates
   that the resolved sequence numbers fall inside the reporting period, and
   emits two error-message columns (`v_AbortSessionBecauseOfNULLOutFltLegSeqNo`,
   `v_AbortSessionBecauseOfNULLInFltLegSeqNo`) that flag any link whose onward /
   inbound flight key does not exist on the sales schedule.

A trailing **Snowflake Scripting** block (commented out per SFX-16) would, at run
time, aggregate those error messages and `RAISE` an exception if any link is
unresolved — i.e. an error-abort guard. The grain of one output row in
`ExpFinalyseInserts` is **one changed link record** (one link key × one
direction of change).

---

## 2. Clause-by-clause walk-through

### Statement 1 — `staging.Lkp_InFltLegSeqNo` (inbound leg-sequence lookup)

- **Inner subquery** joins `BASE.schedule_sales_flt_leg ssfl` to
  `BASE.schedule_sales_mkg_leg ssml` on the full operating/marketing key
  (airline, flight no, suffix, scheduled-dep date, dep station, arr station),
  restricted to marketing carrier `BA`, current records
  (`ssfl.current_rec_ind = 'Y'`), and `effective_dt`/`expiry_dt` window coverage.
- **`QUALIFY ROW_NUMBER() OVER (PARTITION BY … ORDER BY ssfl.opg_flt_leg_id DESC) = 1`**
  keeps the **latest** leg per partition. This is the dedup tie-break flagged
  SEM-02/SEM-07: if `opg_flt_leg_id` is not unique per partition the winner is
  non-deterministic, and no `NULLS` clause is given.
- The outer `Lkp_InFltLegSeqNo` CTE projects the seven lookup columns
  (`FLT_LEG_SEQ_NO`, `OPERATING_AIRLINE_CD`, `OPERATING_FLT_NO`,
  `OPERATING_SFX_CD`, `GMT_SCHED_ARR_TM`, `DEP_STN_CD`, `ARR_STN_CD`).

### Statement 2 — `STAGING.Rtr_DirectFlowOfLinksRecords` (old vs new compare)

- **`old_links`** — current production links from `BASE.FLT_SCHEDULE_LINKS`
  where `CURRENT_REC_IND = 'Y'` and `IN_DEP_GMT_FLT_DT` falls in the reporting
  period. Projects the raw link columns plus two derived string helpers:
  `IN_FLT_NO_STR = RPAD(TO_CHAR(IN_FLT_NO),4,' ')` and
  `IN_DEP_DT_STR = TO_CHAR(IN_DEP_GMT_FLT_DT,'DDMONYY')`. These exist so the
  join keys match the (string-typed) `new_links` side.
- **`new_links`** — candidate links from `STAGING.WRK_FLT_SCHED_LINKS`.
  `TRIM`s the suffix codes (`IN_FLT_SFX_CD`, `OUT_FLT_SFX_CD`) but **not** the
  numeric/`FLT_NO` columns — an asymmetry flagged SEM-03 (CHAR padding drift).
- **`joined`** — `FULL OUTER JOIN old_links o / new_links n` on link station,
  inbound origin, airline, flight no (string-padded), suffix, and dep-date
  string. **SFX-17 fix:** the buggy input used `SELECT o.*, n.*` expecting
  Snowflake to auto-prefix columns with `OLD_`/`NEW_`; it does not. The fix
  replaces the star with **explicit `OLD_`/`NEW_`-prefixed column lists** so
  every downstream `OLD_*`/`NEW_*` reference resolves. Two concatenated
  "record" strings are built:
  - `OLD_concat_record` — `TO_CHAR`-formatted dates/times + `IFNULL`-guarded
    raw columns, joined with `||`.
  - `NEW_concat_record` — same shape but uses `RTRIM` on the numeric/`FLT_NO`
    columns and leaves dates as raw strings (no `TO_CHAR`), an asymmetry flagged
    SEM-03/SEM-08.
- **`filtered`** — keeps a row if **any** of:
  1. the link is **new** (`NEW_LINK_STN_CD IS NULL` is false ⇒ old-only is
     kept) **and** the old link is still "open" (`OLD_LINK_EXPIRY_DT =
     TO_TIMESTAMP('31122050','DDMMYYYY')` — the far-future sentinel; SEM-04
     flags the TIMESTAMP-vs-DATE type question);
  2. the link is **old-only** (`OLD_LINK_STN_CD IS NULL` ⇒ new-only insert);
  3. the concatenated records **differ** (`OLD_concat_record <>
     NEW_concat_record`);
  4. the records are **equal but the old link is already closed** (expiry ≠
     sentinel) ⇒ re-open / update.

  The buggy input referenced `NEW_LINK_STN_CD`, `OLD_LINK_EXPIRY_DT`,
  `OLD_LINK_STN_CD` that did not exist because of the SFX-17 star-expansion
  bug; the fix makes them resolve against the prefixed `joined` columns.

### Statement 3 — `STAGING.ExpFinalyseInserts` (finalise inserts)

This is the most complex statement and the one most affected by remediation.
The buggy input used **intra-SELECT-list alias forward references**
(`v_IN_FLT_LEG_SEQ_NO`, `v_OUT_FLT_LEG_SEQ_NO`, `NEW_IN_FLT_LEG_SEQ_NO`,
`NEW_OUT_FLT_LEG_SEQ_NO` referenced later in the same SELECT list), which
Teradata allows but Snowflake does not (aliases are only visible in
`ORDER BY`/`HAVING`). The **SFX-18 fix** restructures the single SELECT into a
**CTE chain `base → mid → final`** so each alias becomes a real column in its
own scope.

- **`base` CTE** — starts from `STAGING.Rtr_DirectFlowOfLinksRecords r` and
  LEFT JOINs the two leg-sequence lookups:
  - `Lkp_InFltLegSeqNo inlk` on inbound airline/flight/suffix/arrival-time/
    origin→link-station.
  - `Lkp_OutFltLegSeqNo outlk` on outbound airline/flight/suffix/departure-time/
    link-station→destination. **`Lkp_OutFltLegSeqNo` is never created in this
    file** (DEF-07) — flagged `TODO(SME)`; it must be built by a sibling
    script.
  - Computes `v_IN_FLT_LEG_SEQ_NO`: if the new inbound airline is not `BA` → 0;
    else if `Action_code = 'I'` → take the looked-up `inlk.FLT_LEG_SEQ_NO`,
    else fall back to `r.OLD_IN_FLT_LEG_SEQ_NO`. **`r.Action_code` is not
    projected by `Rtr_DirectFlowOfLinksRecords`** (DEF-07) — flagged
    `TODO(SME)`.
  - Computes `v_OUT_FLT_LEG_SEQ_NO`: if the new outbound airline is not `BA` →
    0; else if `Action_code = 'B'` → if the old and new outbound keys match on
    airline/flight-no(int cast)/suffix/dep-date(`TRY_TO_TIMESTAMP`)/link-station/
    destination, reuse `OLD_OUT_FLT_LEG_SEQ_NO`, else take `outlk.FLT_LEG_SEQ_NO`;
    else take `outlk.FLT_LEG_SEQ_NO`.
  - `WHERE r.Action_code IN ('I','B')` keeps only Insert / Both-change rows.
- **`mid` CTE** — carries `base.*` and computes the **boundary-validated**
  sequence numbers:
  - `NEW_IN_FLT_LEG_SEQ_NO` — if `v_IN_FLT_LEG_SEQ_NO IS NULL`, then keep it
    only when `NEW_IN_ARR_GMT_FLT_DT` is one of the period bounds (else NULL);
    else keep `v_IN_FLT_LEG_SEQ_NO`. SEM-06 flags the implicit string→date cast
    in the `IN ('<% Period_start %>', '<% Period_end %>')` list.
  - `NEW_OUT_FLT_LEG_SEQ_NO` — symmetric, keyed on `NEW_OUT_DEP_GMT_FLT_DT`.
- **final `SELECT`** — projects the insert-ready columns: inbound fields,
  `v_IN_FLT_LEG_SEQ_NO` + `NEW_IN_FLT_LEG_SEQ_NO`, outbound fields,
  `v_OUT_FLT_LEG_SEQ_NO` + `NEW_OUT_FLT_LEG_SEQ_NO`, the two error-message IIFs,
  the remaining aircraft/duration fields (with `CAST(… AS INT)` for the
  `_smallint` aliases), and the effective/expiry/current-rec indicators
  (`NEW_LINK_EFFECTIVE_DT = TO_TIMESTAMP('<% Current_date %>','DDMONYY')`,
  `NEW_LINK_EXPIRY_DT = TO_TIMESTAMP('31122050','DDMMYYYY')`,
  `NEW_CURRENT_REC_IND = 'Y'`).
  - **DEF-07 fix (line ~252):** `NEW_OUT_ARR_GMT_FLT_TM_date` was populated from
    `r.NEW_OUT_DEP_GMT_FLT_TM` (copy-paste from the departure slot); corrected
    to `r.NEW_OUT_ARR_GMT_FLT_TM`. Flagged `TODO(SME)` for confirmation.
  - **Inbound error message (left as-is):** the message labels fields
    `IN_DEP_GMT_FLT_TM` and `IN_DESTN_STN_CD` but concatenates
    `NEW_OUT_DEP_GMT_FLT_TM` and `NEW_OUT_DESTN_STN_CD` (suspected copy-paste
    from the outbound message). Per DEF-07 we do **not** guess a column swap —
    message text is cosmetic, not logic — but it is flagged `TODO(SME)`.

### Trailing Snowflake Scripting block (commented out — SFX-16)

The original contained `LET err_text …; IF … THEN SYSTEM$LOG_ERROR; RAISE EXC;
END IF; COMMIT;`. These are procedural constructs valid only inside an
anonymous block / stored procedure, not as bare top-level SQL. Per SFX-16 they
are **commented out** so the batch validates mechanically; the orchestrator is
expected to run them as a Snowflake Scripting anonymous block. Flagged
`TODO(SME)` to confirm the orchestrator executes the guard.

### Duplicate block (DEF-07, removed)

The buggy input duplicated the entire 6-statement block verbatim (lines
364–726 = lines 1–363). The second copy re-ran the same `CREATE OR REPLACE
TRANSIENT TABLE` statements, overwriting the same tables with no effect. The
fix **removes the duplicate**; behaviour is unchanged (the second run was a
no-op overwrite).

---

## 3. Semantic checks table

| SEM ID | Risk | Present? | Corrected how? | Equivalent to Teradata? |
|---|---|---|---|---|
| SEM-01 | Integer division | No | n/a — no `/` on integer columns | n/a |
| SEM-02 | `QUALIFY` / dedup ordering | Yes (stmt 1) | Kept `QUALIFY ROW_NUMBER() OVER (… ORDER BY opg_flt_leg_id DESC) = 1` (Snowflake supports `QUALIFY`). Added `TODO(SME)` to confirm `opg_flt_leg_id` is unique per partition. | **SME** — tie-break uniqueness unconfirmed |
| SEM-03 | `CHAR(n)` padding & comparison | Yes (stmt 2) | `new_links` `TRIM`s suffix codes; `old_links` does not. `NEW_concat_record` uses `RTRIM` on numeric cols; `OLD_concat_record` does not. Asymmetry flagged `TODO(SME)`: if `FLT_SCHEDULE_LINKS` suffix cols are `CHAR(n)`, add `TRIM` to `old_links` to avoid padding drift in the FULL OUTER JOIN and the `<>` filter. | **SME** |
| SEM-04 | Timestamp / timezone | Yes (stmts 2 & 3) | `TO_TIMESTAMP('31122050','DDMMYYYY')` sentinel and `TO_TIMESTAMP('<% Current_date %>','DDMONYY')` produce `TIMESTAMP_NTZ`; no session `TIMEZONE` pinned. `TRY_TO_TIMESTAMP` used for the outbound dep-date compare. Flagged `TODO(SME)` to confirm source has no timezone semantics and sentinel cast matches source DDL type (TIMESTAMP vs DATE). | **SME** |
| SEM-05 | SET-table dedup | No | n/a — all statements are `CREATE OR REPLACE TRANSIENT TABLE … AS SELECT` (overwrite semantics); no `INSERT` into a SET target. | n/a |
| SEM-06 | Implicit cast / NULL in comparison | Yes (stmt 3 `mid`) | `NEW_IN_ARR_GMT_FLT_DT IN ('<% Period_start %>','<% Period_end %>')` relies on implicit string→date cast. Flagged `TODO(SME)` to confirm template tags resolve to parseable date strings and that `NULL` handling in the `IN` matches intent. | **SME** |
| SEM-07 | `NULL` ordering | Yes (stmt 1) | No `NULLS` clause on the `QUALIFY` `ORDER BY`. Snowflake defaults: `NULLS LAST` for ASC, `NULLS FIRST` for DESC. Flagged `TODO(SME)` to confirm matches Teradata. | **SME** |
| SEM-08 | Empty string vs NULL | Yes (stmt 2) | `IFNULL(col,'')` guards the concat records; `''` is a real empty string in Snowflake, not NULL. Behaviour matches the buggy input; flagged for awareness. | Yes (unchanged) |
| SEM-09 | Aggregate of empty set / `SUM` NULL | No | n/a — no aggregates over potentially empty sets. | n/a |
| SEM-10 | Lookup join direction | Yes (stmts 2 & 3) | `joined` FULL OUTER JOIN keys and the `inlk`/`outlk` LEFT JOINs were verified against column names; the SFX-17 explicit prefixes make direction visible. `TODO(SME)` to confirm lookup tables and link records are at the same grain (operating airline / flt no / suffix / station pair). | **SME** |

---

## 4. Divergences from the original (buggy Snowflake input)

These are the **intentional** non-bit-identical changes, each justified by a
rule. No Teradata ground truth exists, so "the original" below means the buggy
Snowflake input.

| # | Divergence | Rule | Justification |
|---|---|---|---|
| 1 | `joined` CTE: `SELECT o.*, n.*` → explicit `OLD_`/`NEW_`-prefixed column lists | SFX-17 | Snowflake does not auto-prefix star-expanded columns; the buggy form failed to resolve every downstream `OLD_*`/`NEW_*` reference. |
| 2 | `filtered` CTE `WHERE`: `NEW_LINK_STN_CD`, `OLD_LINK_EXPIRY_DT`, `OLD_LINK_STN_CD` now resolve against prefixed `joined` columns | SFX-17 | Direct consequence of #1. |
| 3 | `ExpFinalyseInserts`: single SELECT → CTE chain `base → mid → final` | SFX-18 | Intra-SELECT-list alias forward references are invalid on Snowflake; each alias is now a real column in its own scope. |
| 4 | `ExpFinalyseInserts` final SELECT: bare column refs in error-message IIFs (`NEW_OUT_ALN_CD`, `NEW_OUT_FLT_NO`, `NEW_OUT_DEP_GMT_FLT_DT`, …) now resolve via the `base` CTE carrying raw `r.NEW_*` columns | SFX-18 | The buggy aliases were type-suffixed (`_smallint`, `_date`) and did not match the bare names; the CTE chain exposes the unprefixed names. |
| 5 | `NEW_OUT_ARR_GMT_FLT_TM_date` source column: `r.NEW_OUT_DEP_GMT_FLT_TM` → `r.NEW_OUT_ARR_GMT_FLT_TM` | DEF-07 | Copy-paste defect: the arrival-time slot was populated from the departure-time column. **Flagged `TODO(SME)` for confirmation.** |
| 6 | Removed verbatim duplicate of the 6-statement block (lines 364–726) | DEF-07 | The second copy was a no-op overwrite of the same transient tables. |
| 7 | Snowflake Scripting block (`LET`/`IF`/`RAISE`/`COMMIT`) commented out | SFX-16 | Procedural constructs are not parseable as bare SQL; the orchestrator must run them as an anonymous block. **Flagged `TODO(SME)`.** |
| 8 | 14 `<% ctx.env.* %>` template tags preserved verbatim | SNZ-01 | Resolved by the orchestrator at run time, not by Snowflake; never rewritten. |

**Not changed (intentionally):**
- The inbound error message still concatenates `NEW_OUT_DEP_GMT_FLT_TM` for the
  `IN_DEP_GMT_FLT_TM` field and `NEW_OUT_DESTN_STN_CD` for `IN_DESTN_STN_CD`
  (suspected copy-paste). Per DEF-07 we do not guess a column swap — message
  text is cosmetic, not logic — but it is flagged `TODO(SME)`.
- `QUALIFY` is kept (Snowflake supports it; not wrapped in a `ROW_NUMBER`
  subquery).
- Column order, JOIN keys, and CASE-branch order are preserved exactly.

---

## 5. Open SME questions

Each is phrased as a decision for a human reviewer. There are **19**
`TODO(SME)` items in the fixed SQL; they group into the questions below.

1. **`Action_code` source (3 sites).** `r.Action_code` is referenced in
   `ExpFinalyseInserts` (`base` CTE IIFs and `WHERE`) but is **not projected**
   by `Rtr_DirectFlowOfLinksRecords`. Decision: is `Action_code` a column of
   `Rtr_DirectFlowOfLinksRecords` supplied by a prior/sibling statement, or
   should it be added to the `new_links` projection? What is its value domain
   (`'I'`/`'B'`/others)?
2. **`Lkp_OutFltLegSeqNo` missing table.** It is joined in `ExpFinalyseInserts`
   but never created in this file. Decision: is it built by a sibling script,
   and is `GMT_SCHED_DEP_TM` its departure-time column (mirroring
   `Lkp_InFltLegSeqNo`'s `GMT_SCHED_ARR_TM`)?
3. **`NEW_OUT_ARR_GMT_FLT_TM_date` source column (DEF-07).** Corrected from
   `r.NEW_OUT_DEP_GMT_FLT_TM` to `r.NEW_OUT_ARR_GMT_FLT_TM`. Decision: confirm
   the outbound arrival-time slot should source `NEW_OUT_ARR_GMT_FLT_TM`.
4. **Inbound error-message field values (DEF-07).** The inbound message uses
   `NEW_OUT_DEP_GMT_FLT_TM` for `IN_DEP_GMT_FLT_TM` and `NEW_OUT_DESTN_STN_CD`
   for `IN_DESTN_STN_CD`. Decision: are these copy-paste errors that should
   read `NEW_IN_DEP_GMT_FLT_DT` and `NEW_IN_ORIGN_STN_CD` (or similar), or is
   the message text acceptable as-is?
5. **SEM-02 / SEM-07 — `QUALIFY` tie-break.** `ORDER BY ssfl.opg_flt_leg_id DESC`
   with no `NULLS` clause. Decision: is `opg_flt_leg_id` unique per partition
   and non-nullable? Should `NULLS LAST` be added?
6. **SEM-03 — CHAR padding drift.** `new_links` `TRIM`s suffix codes and
   `NEW_concat_record` `RTRIM`s numeric cols; `old_links` / `OLD_concat_record`
   do not. Decision: are `FLT_SCHEDULE_LINKS` suffix/numeric columns `CHAR(n)`?
   If so, add `TRIM`/`RTRIM` to the old side to preserve Teradata comparison
   semantics.
7. **SEM-04 — timestamp/timezone.** `TO_TIMESTAMP('31122050','DDMMYYYY')`
   sentinel and `TO_TIMESTAMP('<% Current_date %>','DDMONYY')` produce
   `TIMESTAMP_NTZ`; no session `TIMEZONE` pinned. Decision: confirm the source
   has no timezone semantics and the sentinel cast matches the source DDL type
   (TIMESTAMP vs DATE).
8. **SEM-06 — implicit string→date cast.** `NEW_IN_ARR_GMT_FLT_DT IN ('<%
   Period_start %>','<% Period_end %>')` relies on implicit cast. Decision:
   confirm the template tags resolve to parseable date strings and that `NULL`
   handling in the `IN` matches intent.
9. **SEM-10 — lookup grain.** Decision: confirm the lookup tables
   (`Lkp_InFltLegSeqNo`, `Lkp_OutFltLegSeqNo`) and the link records are at the
   same grain (operating airline / flt no / suffix / station pair).
10. **SFX-16 — error-handling block execution.** Decision: confirm the
    orchestrator runs the commented-out Snowflake Scripting block (LET / IF /
    RAISE / COMMIT) as an anonymous block / stored procedure, and that
    `COMMIT` is issued by the orchestrator after the guard.

---

## 6. Inline anchors

```anchors
CREATE OR REPLACE TRANSIENT TABLE staging.Lkp_InFltLegSeqNo AS :: Statement 1 — inbound leg-sequence lookup: dedups BASE.schedule_sales_flt_leg (marketing carrier BA, current rec) by opg_flt_leg_id DESC; SEM-02/SEM-07 tie-break unconfirmed.
QUALIFY ROW_NUMBER() OVER ( :: SEM-02/SEM-07: dedup tie-break on opg_flt_leg_id DESC with no NULLS clause — confirm uniqueness and NULL ordering.
CREATE OR REPLACE TRANSIENT TABLE STAGING.Rtr_DirectFlowOfLinksRecords AS :: Statement 2 — FULL OUTER JOIN of old (BASE.FLT_SCHEDULE_LINKS) vs new (STAGING.WRK_FLT_SCHED_LINKS) links; emits OLD_/NEW_-prefixed columns + two concat records.
RPAD(TO_CHAR(IN_FLT_NO),4,' ') AS IN_FLT_NO_STR :: old_links pads flight no to 4 chars so it joins against the string-typed new_links side.
TRIM(IN_FLT_SFX_CD) AS IN_FLT_SFX_CD :: SEM-03: new_links TRIMs suffix codes; old_links does not — confirm whether FLT_SCHEDULE_LINKS suffix cols are CHAR(n) (padding drift risk).
o.LINK_STN_CD           AS OLD_LINK_STN_CD :: SFX-17: explicit OLD_/NEW_-prefixed column lists replace the buggy o.*,n.* star expansion (Snowflake does not auto-prefix).
FULL OUTER JOIN new_links n :: FULL OUTER JOIN keeps old-only (delete), new-only (insert), and matched (update) link rows.
IFNULL(TO_CHAR(o.IN_ARR_GMT_FLT_DT,'DDMONYY'),'') || :: OLD_concat_record: TO_CHAR-formatted dates/times + IFNULL-guarded raw columns; SEM-08 empty-string-vs-NULL guard.
IFNULL(n.IN_ARR_GMT_FLT_DT,'') || :: NEW_concat_record: raw date strings + RTRIM on numeric cols — asymmetry vs OLD side flagged SEM-03.
OLD_LINK_EXPIRY_DT = TO_TIMESTAMP('31122050','DDMMYYYY') :: SEM-04: far-future sentinel cast to TIMESTAMP_NTZ; confirm matches source DDL type (TIMESTAMP vs DATE).
OLD_concat_record <> NEW_concat_record :: keeps rows whose concatenated old/new records differ — the net change set.
CREATE OR REPLACE TRANSIENT TABLE STAGING.ExpFinalyseInserts AS :: Statement 3 — finalise inserts: resolves inbound/outbound leg sequence numbers and emits error messages for unresolved links.
WITH base AS ( :: SFX-18: restructured into a CTE chain (base -> mid -> final) so SELECT-list aliases become real columns (Teradata allows intra-SELECT-list alias refs; Snowflake does not).
IFF(
            TRIM(r.NEW_IN_ALN_CD) <> 'BA', :: inbound leg-seq logic: non-BA -> 0; else Action_code='I' -> lookup, else OLD_IN_FLT_LEG_SEQ_NO.
r.Action_code = 'I',  -- TODO(SME): Action_code not projected :: DEF-07: Action_code is not projected by Rtr_DirectFlowOfLinksRecords — confirm source column.
LEFT JOIN STAGING.Lkp_InFltLegSeqNo inlk :: inbound lookup join on airline/flt-no/suffix/arrival-time/origin->link-station.
LEFT JOIN STAGING.Lkp_OutFltLegSeqNo outlk  -- TODO(SME) :: DEF-07: Lkp_OutFltLegSeqNo is never created in this file — confirm it is built by a sibling script and GMT_SCHED_DEP_TM is its departure-time column.
WHERE r.Action_code IN ('I','B')  -- TODO(SME) :: keeps only Insert / Both-change rows; Action_code source unconfirmed.
NEW_IN_ARR_GMT_FLT_DT IN ( :: SEM-06: implicit string->date cast via template tags — confirm tags resolve to parseable date strings.
NEW_OUT_ARR_GMT_FLT_TM AS NEW_OUT_ARR_GMT_FLT_TM_date,  -- [DEF-07] :: DEF-07 fix: was NEW_OUT_DEP_GMT_FLT_TM (copy-paste); corrected to arrival time — confirm.
IFF(
        NEW_OUT_FLT_LEG_SEQ_NO IS NULL, :: outbound error message: flags links whose onward flight key does not exist on FLT_SCHEDULE_SALES.
IFF(
        NEW_IN_FLT_LEG_SEQ_NO IS NULL, :: inbound error message: flags links whose inbound flight key does not exist on FLT_SCHEDULE_SALES.
IN_DEP_GMT_FLT_TM="' || NEW_OUT_DEP_GMT_FLT_TM || :: DEF-07 (left as-is): inbound message reuses outbound dep time — confirm whether this is a copy-paste error.
IN_DESTN_STN_CD="' || NEW_OUT_DESTN_STN_CD || :: DEF-07 (left as-is): inbound message reuses outbound destination — confirm whether this is a copy-paste error.
TO_TIMESTAMP('<% ctx.env.S_vw6122_CompareLinksRecordsWithTeradata_Current_date %>','DDMONYY') AS NEW_LINK_EFFECTIVE_DT :: SEM-04: effective date from Current_date template tag, cast to TIMESTAMP_NTZ.
TO_TIMESTAMP('31122050','DDMMYYYY') AS NEW_LINK_EXPIRY_DT :: SEM-04: far-future expiry sentinel.
-- SFX-16: Snowflake Scripting constructs :: procedural error-abort guard (LET/IF/RAISE/COMMIT) commented out — orchestrator must run as anonymous block.
--     LET err_text VARCHAR := ( :: aggregates the two error-message columns and raises if any link is unresolved.
--     IF (err_text IS NOT NULL) THEN :: error-abort guard: logs and raises EXC if any unresolved link is found.
-- COMMIT; -- transaction control :: COMMIT handled by orchestrator/session, not a compilable SQL statement.
```