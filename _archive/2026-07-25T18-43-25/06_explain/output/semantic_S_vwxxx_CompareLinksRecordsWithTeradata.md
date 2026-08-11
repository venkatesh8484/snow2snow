# Stage 6 — Semantic explanation: S_vwxxx_CompareLinksRecordsWithTeradata

**Fixed SQL:** `03_fix/output/S_vwxxx_CompareLinksRecordsWithTeradata_fixed.snowsql`
**Teradata ground truth:** Not supplied. Intent is inferred from the buggy
Snowflake input and the `02_rules/` catalogue; every inference is flagged
`TODO(SME)`.

---

## 1. Purpose

This script reconciles the **current ("old") flight-link schedule** stored in
`BASE.FLT_SCHEDULE_LINKS` against a **new/working copy** in
`STAGING.WRK_FLT_SCHED_LINKS`, and produces the set of link records that must be
**inserted** into the live schedule. A "link" is a paired inbound→outbound
flight connection at a station (`LINK_STN_CD`): an inbound leg (airline, flight
number, suffix, departure/arrival GMT date-time, terminal, ground handling,
service type) joined to an outbound leg with the same attributes plus aircraft
owner, carrier type, and timing durations (midnight qty, buffer, standard
working, tow time).

The script builds three transient tables in sequence:

1. **`STAGING.Lkp_InFltLegSeqNo`** — a deduplicated lookup of BA-marketed
   flight legs (from `BASE.schedule_sales_flt_leg` joined to
   `BASE.schedule_sales_mkg_leg`) keyed by airline / flight number / suffix /
   arrival GMT time / station pair, yielding the canonical
   `FLT_LEG_SEQ_NO` for each inbound leg.
2. **`STAGING.Rtr_DirectFlowOfLinksRecords`** — a FULL OUTER JOIN of old vs new
   links, filtered down to rows that are **new, changed, or expired** (the
   "delta" set).
3. **`STAGING.ExpFinalyseInserts`** — the finalized insert set: for each delta
   row whose action is an insert (`I`) or both-insert-and-update (`B`), it
   resolves the inbound and outbound `FLT_LEG_SEQ_NO` from the lookup tables,
   validates that the leg sequence falls inside the reporting period, and
   emits a human-readable error message when a referenced flight does not exist
   in the schedule.

The **grain of one output row** in `ExpFinalyseInserts` is a single link record
(one inbound→outbound connection at one station) that is candidate for insert,
carrying its resolved leg sequence numbers and any validation error text.

A trailing (commented-out) Snowflake Scripting block checks whether any error
message was produced and raises an exception to abort the batch if so.

---

## 2. Clause-by-clause walk-through

### 2.1 `Lkp_InFltLegSeqNo` — inbound leg-sequence lookup (CTAS #1)

**Inner subquery** joins `BASE.schedule_sales_flt_leg` (`ssfl`) to
`BASE.schedule_sales_mkg_leg` (`ssml`) on the full flight-leg key (airline,
flight number, suffix, scheduled departure date, departure station, arrival
station). It keeps only legs **marketed by BA**
(`ssml.marketing_airline_cd = 'BA'`) and only current rows
(`ssfl.current_rec_ind = 'Y'`), further restricted to legs whose effective date
falls inside the marketing leg's effective→expiry window.

**`QUALIFY ROW_NUMBER() OVER (PARTITION BY … ORDER BY opg_flt_leg_id DESC) = 1`**
deduplicates the lookup to one row per (airline, flight number, suffix, GMT
scheduled arrival time, station pair), keeping the **highest** leg id. This is
the canonical inbound leg sequence number used later to validate new link
records.

> **Buggy input would have done the same** — this block had no syntax errors.
> The only risk is SEM-02/SEM-07 (tie-breaking determinism), flagged below.

### 2.2 `Rtr_DirectFlowOfLinksRecords` — old-vs-new comparison (CTAS #2)

#### `old_links` CTE
Reads current (`CURRENT_REC_IND = 'Y'`) links from `BASE.FLT_SCHEDULE_LINKS`
whose inbound departure date falls inside the reporting period
(`Period_start` … `Period_end`, supplied as SNZ-01 template tags). It projects
all link attributes plus two derived string columns:
`IN_FLT_NO_STR = RPAD(TO_CHAR(IN_FLT_NO),4,' ')` and
`IN_DEP_DT_STR = TO_CHAR(IN_DEP_GMT_FLT_DT,'DDMONYY')`. These pre-formatted
strings are needed because the new-links side stores the flight number and date
as strings of differing width/format, and the join must align them.

#### `new_links` CTE
Reads the working copy from `STAGING.WRK_FLT_SCHED_LINKS` and **TRIMs** the
suffix codes (`IN_FLT_SFX_CD`, `OUT_FLT_SFX_CD`). It does **not** project
`IN_FLT_LEG_SEQ_NO`, `OUT_FLT_LEG_SEQ_NO`, `LINK_EFFECTIVE_DT`,
`LINK_EXPIRY_DT`, or `CURRENT_REC_IND` — those are old-side-only attributes
(the new side has no leg sequence yet; that is what `ExpFinalyseInserts`
computes).

#### `joined` CTE — FULL OUTER JOIN
Performs a **FULL OUTER JOIN** of `old_links o` and `new_links n` on the link
identity key: link station, origin station, inbound airline, inbound flight
number (string-aligned via `IN_FLT_NO_STR`), inbound suffix, and inbound
departure date (string-aligned via `IN_DEP_DT_STR`).

It projects **every** old and new column with explicit `OLD_`/`NEW_` prefixes
(SFX-17 fix), then builds two concatenated "fingerprint" strings:

- **`OLD_concat_record`** — concatenates the old-side attributes (arrival date,
  arrival time, terminals, service types, outbound key, aircraft, durations,
  fixed-link reason) using `IFNULL(x,'')` so a NULL does not nullify the whole
  string. Dates/times are formatted with `TO_CHAR(…,'DDMONYY')` / `'HH24MI'`.
- **`NEW_concat_record`** — the same fingerprint from the new side, but the new
  side stores dates as strings already, so several `TO_CHAR` wrappers are
  dropped and `RTRIM` is applied to numeric-as-string columns
  (`OUT_FLT_NO`, `MIDNIGHT_QTY`, `BUFFER_DUR`, `STD_WORKING_DUR`,
  `TOW_TIME_DUR`).

> **Buggy input:** used `SELECT o.*, n.*` and then referenced `OLD_LINK_STN_CD`,
> `NEW_LINK_STN_CD`, etc. downstream. Snowflake does **not** auto-prefix
> `o.*`/`n.*`, so every `OLD_*`/`NEW_*` reference was unresolved → the script
> could not compile. The fix (SFX-17) replaces the star-projections with
> explicit prefixed column lists. Semantics are identical; only naming changed.

#### `filtered` CTE — the delta
Keeps rows matching **any** of:

1. **Expired:** the link exists only on the old side (`NEW_LINK_STN_CD IS NULL`)
   and is still "live" in the old side (`OLD_LINK_EXPIRY_DT = 31122050`).
2. **New:** the link exists only on the new side (`OLD_LINK_STN_CD IS NULL`).
3. **Changed:** both sides exist but the fingerprints differ
   (`OLD_concat_record <> NEW_concat_record`).
4. **Re-activated:** fingerprints are identical but the old side is already
   expired (`OLD_LINK_EXPIRY_DT <> 31122050`) — i.e. the same link is being
   reinstated.

The final `SELECT * FROM filtered` materialises the delta into
`STAGING.Rtr_DirectFlowOfLinksRecords`.

> **Buggy input:** the `filtered` WHERE referenced `NEW_LINK_STN_CD`,
> `OLD_LINK_EXPIRY_DT`, `OLD_LINK_STN_CD` which did not exist in `joined`
> (same SFX-17 root cause). The fix makes them resolve. The boolean logic is
> unchanged.

### 2.3 `ExpFinalyseInserts` — finalized inserts with leg-sequence validation (CTAS #3)

Restructured into a **CTE chain (`base → mid → final`)** by SFX-18 because the
original referenced SELECT-list aliases (`v_IN_FLT_LEG_SEQ_NO`,
`v_OUT_FLT_LEG_SEQ_NO`, `NEW_IN_FLT_LEG_SEQ_NO`, `NEW_OUT_FLT_LEG_SEQ_NO`)
later in the same SELECT list — legal in Teradata, illegal in Snowflake.

#### `base` CTE
Starts from `STAGING.Rtr_DirectFlowOfLinksRecords r` (carrying all `OLD_*`/`NEW_*`
columns from `filtered`), restricted to rows whose `Action_code IN ('I','B')`
(insert-only or insert-and-update). It LEFT JOINs:

- **`STAGING.Lkp_InFltLegSeqNo inlk`** on the inbound flight key (airline,
  flight number cast to INT, suffix, GMT arrival time, origin→link station
  pair) to fetch the inbound leg sequence.
- **`STAGING.Lkp_OutFltLegSeqNo outlk`** on the outbound flight key (airline,
  flight number, suffix, GMT **departure** time, link→destination station
  pair) to fetch the outbound leg sequence. **This table is not created in
  this file** — it is an external dependency (see SME questions).

It computes two leg-sequence candidates:

- **`v_IN_FLT_LEG_SEQ_NO`** — if the inbound airline is not BA, the leg
  sequence is `0` (non-BA legs are not in the BA-marketed lookup); otherwise,
  if the action is `I` (pure insert) take the looked-up `inlk.FLT_LEG_SEQ_NO`,
  else (`B`) keep the old `r.OLD_IN_FLT_LEG_SEQ_NO`.
- **`v_OUT_FLT_LEG_SEQ_NO`** — if the outbound airline is not BA, `0`;
  otherwise, if the action is `B` **and** the outbound flight key is unchanged
  (same airline, flight number, suffix, departure date, link station,
  destination), reuse `r.OLD_OUT_FLT_LEG_SEQ_NO`; otherwise take the looked-up
  `outlk.FLT_LEG_SEQ_NO`. For a pure insert (`I`) the outer `IFF` falls through
  to `outlk.FLT_LEG_SEQ_NO`.

> **Buggy input:** defined `v_IN_FLT_LEG_SEQ_NO` and `v_OUT_FLT_LEG_SEQ_NO` as
> aliases and then referenced them in the very same SELECT list to compute
> `NEW_IN_FLT_LEG_SEQ_NO` / `NEW_OUT_FLT_LEG_SEQ_NO`. Snowflake rejects this
> forward reference. The fix (SFX-18) splits the computation across `base` and
> `mid` so each alias is a real column in its own scope. The arithmetic is
> identical.

#### `mid` CTE
Carries all `base` columns and applies **boundary validation**: if the resolved
leg sequence is NULL, keep it NULL only when the corresponding departure date
is **outside** the reporting period (`Period_start`/`Period_end`); if the
departure date is exactly at a period boundary, retain the (NULL) value as-is
rather than forcing NULL. Concretely:

- `NEW_IN_FLT_LEG_SEQ_NO` — if `v_IN_FLT_LEG_SEQ_NO` is NULL and
  `NEW_IN_ARR_GMT_FLT_DT` is **not** one of the period boundary dates, force
  NULL; otherwise pass `v_IN_FLT_LEG_SEQ_NO` through.
- `NEW_OUT_FLT_LEG_SEQ_NO` — same logic against `NEW_OUT_DEP_GMT_FLT_DT`.

This implements the Teradata behaviour where a missing leg is only treated as a
hard error when it lies inside the reporting window.

#### final `SELECT`
Projects the finalized insert row: basic inbound/outbound fields (with explicit
casts to INT for flight numbers and durations, and `TO_DATE(…,'DDMONYY')` for
date strings), the two leg-sequence candidates and their validated versions,
two **error-message** IFF columns, the aircraft/duration/reason fields, and the
effective/expiry/current-rec indicators (`NEW_LINK_EFFECTIVE_DT` = current
date, `NEW_LINK_EXPIRY_DT` = `31122050`, `NEW_CURRENT_REC_IND = 'Y'`).

The error messages:

- **`v_AbortSessionBecauseOfNULLOutFltLegSeqNo`** — if
  `NEW_OUT_FLT_LEG_SEQ_NO` is NULL, emit a human-readable string naming the
  missing outbound flight key; else `'N'`.
- **`v_AbortSessionBecauseOfNULLInFltLegSeqNo`** — same for the inbound leg.

> **DEF-07 fix (line ~252):** `NEW_OUT_ARR_GMT_FLT_TM_date` was populated from
> `r.NEW_OUT_DEP_GMT_FLT_TM` (copy-paste from the departure slot); corrected to
> `r.NEW_OUT_ARR_GMT_FLT_TM` so the outbound **arrival** time slot actually
> carries the arrival time.

> **Buggy input:** the error-message IFFs referenced bare column names
> (`NEW_OUT_FLT_NO`, `NEW_OUT_DEP_GMT_FLT_DT`, …) that did not match any
> SELECT alias (the aliases were `NEW_OUT_FLT_NO_smallint`,
> `NEW_OUT_DEP_GMT_FLT_DT_date`, etc.). The CTE chain fix (SFX-18) carries the
> raw `r.NEW_*` columns through `base` so the final SELECT can reference them
> by their unprefixed names.

### 2.4 Error-handling / Snowflake Scripting block (commented out)

The original file ended with a Snowflake Scripting block:

```
LET err_text VARCHAR := (SELECT ANY_VALUE(err_text) FROM (… UNION ALL …) WHERE err_text <> 'N');
IF (err_text IS NOT NULL) THEN
    SYSTEM$LOG_ERROR(err_text);
    LET EXC EXCEPTION := EXCEPTION(-20002, err_text);
    RAISE EXC;
END IF;
```

It aggregates the two error-message columns from `ExpFinalyseInserts`, and if
any row has a real message (not `'N'`), logs it and raises exception `-20002`
to abort the batch.

> **SFX-16 fix:** these procedural constructs (`LET`, `IF … THEN`, `RAISE`,
> `EXCEPTION`) are only valid inside a `BEGIN … END;` anonymous block or stored
> procedure. The buggy input placed them as bare top-level statements separated
> by semicolons, which Snowflake cannot parse. The fix **comments the block
> out** so the SQL batch validates mechanically; the orchestrator is expected
> to execute it separately as a Snowflake Scripting anonymous block. The
> `COMMIT;` is likewise commented out (transaction control is the
> orchestrator's responsibility).

---

## 3. Semantic checks table

| SEM ID | Risk | Present? | Corrected how? | Equivalent to Teradata? |
|---|---|---|---|---|
| SEM-01 | Integer division | No | N/A — no division operators. | N/A |
| SEM-02 | `QUALIFY` / dedup ordering | Yes — `Lkp_InFltLegSeqNo` dedup orders by `opg_flt_leg_id DESC` only. | Not corrected; flagged. If `opg_flt_leg_id` is unique per partition the winner is deterministic; if not, tie-break is non-deterministic in both Teradata and Snowflake. | **SME** — confirm `opg_flt_leg_id` is unique within the partition key. |
| SEM-03 | `CHAR(n)` padding & comparison | Yes — `new_links` TRIMs `IN_FLT_SFX_CD`/`OUT_FLT_SFX_CD`; `old_links` does **not**. The `joined` FULL OUTER JOIN compares `n.IN_FLT_SFX_CD` (trimmed) to `o.IN_FLT_SFX_CD` (untrimmed). | Not corrected; flagged. If the source columns are `CHAR(n)`, Teradata blank-pads and the untrimmed old side may mismatch the trimmed new side, dropping match rows. | **SME** — confirm whether `FLT_SCHEDULE_LINKS` suffix columns are `CHAR(n)`; if so, add `TRIM` to the `old_links` projections (or the join keys). |
| SEM-04 | Timestamp / timezone | Yes — `TO_TIMESTAMP('31122050','DDMMYYYY')`, `TRY_TO_TIMESTAMP(…,'DDMONYY')`, `TO_TIMESTAMP(Current_date,'DDMONYY')` all produce `TIMESTAMP_NTZ`. | Not corrected; no session `TIMEZONE` pinned. | **SME** — confirm source data has no timezone semantics and NTZ is intended. |
| SEM-05 | SET-table dedup | No — all targets are CTAS (`CREATE OR REPLACE TRANSIENT TABLE`), no INSERT-into-SET-table pattern. | N/A | N/A |
| SEM-06 | Implicit cast / NULL in comparison | Yes — `NEW_IN_ARR_GMT_FLT_DT IN ('<% Period_start %>','<% Period_end %>')` compares a date/timestamp column to template-string literals. | Not corrected; relies on Snowflake's implicit string→date cast. | **SME** — confirm the column type and that the template tags resolve to parseable date strings in the session format. |
| SEM-07 | `NULL` ordering | Yes — `ORDER BY opg_flt_leg_id DESC` has no explicit `NULLS FIRST/LAST`. | Not corrected; Snowflake defaults to `NULLS FIRST` for `DESC`. | **SME** — confirm `opg_flt_leg_id` is non-nullable; if nullable, add explicit `NULLS LAST`. |
| SEM-08 | Empty string vs NULL | Yes — `IFNULL(x,'')` in both concat fingerprints. | Intentional and correct: `''` is a real empty string in Snowflake, used precisely to prevent NULL propagation through `\|\|`. | **Yes** — behaviour matches Teradata intent. |
| SEM-09 | Aggregate of empty set | No — the only aggregate is `ANY_VALUE` in the commented-out scripting block, which is safe. | N/A | N/A |
| SEM-10 | Lookup join direction | Yes — `inlk.OPERATING_AIRLINE_CD = r.NEW_IN_ALN_CD`, `outlk.OPERATING_AIRLINE_CD = r.NEW_OUT_ALN_CD`, with `CAST(r.NEW_*_FLT_NO AS INT)` on both sides. | Not corrected; direction inferred from naming. | **SME** — confirm the lookup tables and the link records are at the same grain (operating airline / flight number / suffix / station pair). |

---

## 4. Divergences from the original

| # | Divergence | Justification |
|---|---|---|
| 1 | `joined` CTE uses explicit `OLD_`/`NEW_`-prefixed column lists instead of `o.*, n.*` (SFX-17). | Snowflake does not auto-prefix star-projections; the downstream `OLD_*`/`NEW_*` references were unresolved. Semantics identical — only column naming changed. |
| 2 | `ExpFinalyseInserts` restructured into a `base → mid → final` CTE chain (SFX-18). | Snowflake forbids referencing a SELECT-list alias elsewhere in the same SELECT list. The chain makes each alias a real column in its own scope. The computed values are identical. |
| 3 | `NEW_OUT_ARR_GMT_FLT_TM_date` now sources `r.NEW_OUT_ARR_GMT_FLT_TM` instead of `r.NEW_OUT_DEP_GMT_FLT_TM` (DEF-07). | Copy-paste defect: the outbound **arrival** time slot was populated with the outbound **departure** time. Corrected to carry the arrival time. **Pending SME confirmation.** |
| 4 | The verbatim duplicate of the 6-statement block (original lines 364–726) was removed (DEF-07). | The second copy overwrote the same transient tables with identical content — accidental duplication with no semantic effect. |
| 5 | The Snowflake Scripting error-handling block and the trailing `COMMIT;` are commented out (SFX-16). | The procedural constructs are only valid inside a `BEGIN … END;` anonymous block; as bare top-level statements they prevented the batch from parsing. The orchestrator is expected to run them as a scripting block. **Pending SME confirmation.** |
| 6 | 14 `<% ctx.env.* %>` SNZ-01 template tags preserved verbatim. | Per SNZ-01, template tags are resolved by the orchestrator at run time, never rewritten by the pipeline. |

No other intentional divergences. Column order, JOIN keys, CASE/IFF branch
order, and the `QUALIFY` dedup are preserved exactly.

---

## 5. Open SME questions

1. **`Action_code` source.** `base` filters on `r.Action_code IN ('I','B')` and
   branches on `r.Action_code = 'I'` / `'B'`, but `Action_code` is not
   projected by `old_links`, `new_links`, `joined`, or `filtered`. Is
   `Action_code` a column of `Rtr_DirectFlowOfLinksRecords` supplied by a prior
   or sibling statement? If not, where should it come from?

2. **`STAGING.Lkp_OutFltLegSeqNo` DDL.** This table is joined but never created
   in this file. Confirm it is built by a sibling script, and that
   `GMT_SCHED_DEP_TM` is its departure-time column (mirroring
   `Lkp_InFltLegSeqNo.GMT_SCHED_ARR_TM`).

3. **`NEW_OUT_ARR_GMT_FLT_TM_date` correction (DEF-07).** The fix changed the
   source from `r.NEW_OUT_DEP_GMT_FLT_TM` to `r.NEW_OUT_ARR_GMT_FLT_TM`.
   Confirm the outbound arrival time slot should indeed source the arrival
   time.

4. **Inbound error-message field values.** The inbound error message reuses
   `NEW_OUT_DEP_GMT_FLT_TM` for the `IN_DEP_GMT_FLT_TM` field and
   `NEW_OUT_DESTN_STN_CD` for the `IN_DESTN_STN_CD` field (suspected
   copy-paste from the outbound message). Left as-is because message text is
   cosmetic, not logic. Confirm whether the inbound message should instead use
   `NEW_IN_DEP_GMT_FLT_TM` and `NEW_LINK_STN_CD` (the inbound destination is
   the link station).

5. **Error-handling block execution.** The Snowflake Scripting block
   (`LET`/`IF`/`RAISE`) and the trailing `COMMIT;` are commented out. Confirm
   the orchestrator executes them as a Snowflake Scripting anonymous block
   after the three CTAS statements, and issues the `COMMIT`.

6. **SEM-02 / SEM-07 — dedup determinism.** Confirm `opg_flt_leg_id` is unique
   within the `Lkp_InFltLegSeqNo` partition key and non-nullable; otherwise
   add a deterministic tie-breaker and explicit `NULLS LAST`.

7. **SEM-03 — CHAR padding.** Confirm whether the suffix columns
   (`IN_FLT_SFX_CD`, `OUT_FLT_SFX_CD`) in `BASE.FLT_SCHEDULE_LINKS` are
   `CHAR(n)`. If so, `old_links` should `TRIM` them (or the join keys) to
   match the trimmed `new_links` side.

8. **SEM-04 / SEM-06 — timestamp & implicit cast.** Confirm source date/time
   columns carry no timezone semantics (NTZ is intended), and that the
   `<% Period_start %>` / `<% Period_end %>` template tags resolve to strings
   parseable as dates in the session format.

9. **SEM-10 — lookup join grain.** Confirm `Lkp_InFltLegSeqNo` /
   `Lkp_OutFltLegSeqNo` and the link records are at the same grain (operating
   airline / flight number / suffix / station pair) so the LEFT JOINs do not
   fan out or drop rows.

---

## 6. Inline anchors

```anchors
MATCH CREATE OR REPLACE TRANSIENT TABLE staging.Lkp_InFltLegSeqNo :: Inbound leg-sequence lookup: BA-marketed flight legs deduplicated to one FLT_LEG_SEQ_NO per (airline, flt no, suffix, arr GMT time, station pair).
MATCH QUALIFY ROW_NUMBER() OVER :: Dedup keeps the highest opg_flt_leg_id per partition; tie-break determinism flagged SEM-02/SEM-07.
MATCH FROM BASE.FLT_SCHEDULE_LINKS :: old_links: current live links within the reporting period (Period_start…Period_end SNZ-01 tags).
MATCH FROM STAGING.WRK_FLT_SCHED_LINKS :: new_links: working copy of links; suffix codes TRIMmed (SEM-03 risk vs untrimmed old side).
MATCH FULL OUTER JOIN new_links n :: joined: old vs new links on link identity key; explicit OLD_/NEW_ prefixes (SFX-17) replace o.*/n.*.
MATCH OLD_concat_record <> NEW_concat_record :: filtered delta: rows that are new, changed, expired, or re-activated.
MATCH WITH base AS :: ExpFinalyseInserts base: resolves inbound/outbound FLT_LEG_SEQ_NO via Lkp_InFltLegSeqNo / Lkp_OutFltLegSeqNo; CTE chain (SFX-18) fixes intra-SELECT alias references.
MATCH r.Action_code IN ('I','B') :: Only insert ('I') and insert-and-update ('B') actions are finalized; Action_code source is an open SME question.
MATCH LEFT JOIN STAGING.Lkp_OutFltLegSeqNo outlk :: Outbound leg lookup; table is an external dependency not created in this file (SME).
MATCH NEW_OUT_ARR_GMT_FLT_TM AS NEW_OUT_ARR_GMT_FLT_TM_date :: DEF-07 fix: arrival time slot now sources arrival time, not departure time.
MATCH v_AbortSessionBecauseOfNULLOutFltLegSeqNo :: Outbound error message emitted when NEW_OUT_FLT_LEG_SEQ_NO is NULL.
MATCH v_AbortSessionBecauseOfNULLInFltLegSeqNo :: Inbound error message; reuses outbound fields for IN_DEP_GMT_FLT_TM / IN_DESTN_STN_CD (SME).
MATCH -- BEGIN :: SFX-16: Snowflake Scripting error-handling block commented out; orchestrator must run it as an anonymous block.
MATCH -- COMMIT; :: Transaction control commented out; orchestrator issues COMMIT after the error-handling block.
```