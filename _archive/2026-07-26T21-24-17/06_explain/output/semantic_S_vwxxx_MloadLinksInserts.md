# Semantic explanation — `S_vwxxx_MloadLinksInserts`

**Fixed SQL:** `03_fix/output/S_vwxxx_MloadLinksInserts_fixed.snowsql`
**Analysis:** `01_analyze/output/analysis_S_vwxxx_MloadLinksInserts.md`
**Teradata ground truth:** **Not supplied** (no `00_input/S_vwxxx_MloadLinksInserts.teradata.sql`).
All semantic inferences are therefore flagged `TODO(SME)` and derived from
`02_rules/` + the Snowflake input alone.

---

## 1. Purpose

This script is an **idempotent upsert-load** of new flight-folder-link rows. It
reads candidate rows from the staging table `STAGING.ExpFinalyseInserts`
(alias `S`) and inserts them into the base table `BASE.FLT_FOLDER_LINKS`
(alias `T`), but **only if an identical row does not already exist** on all 33
key columns. The grain of one output row is one complete flight-folder-link
record: an inbound flight leg (station, airline, flight number/suffix, dep/arr
date/time, terminal, ground activity, service type, leg sequence) paired with
an outbound flight leg, plus aircraft-owner / aircraft-type / timing
(midnight qty, buffer, standard working, tow time) / reason / effective-expiry
dates / current-record indicator. The `NOT EXISTS` anti-join on all 33 columns
makes the insert a "insert-if-absent" pattern: re-running the script against the
same staging data is a no-op, and duplicate candidate rows in staging are
suppressed once a matching base row exists.

No Teradata original was supplied, so the intent above is inferred from the
Snowflake input's structure and the `NEW_*` staging naming convention. Every
inference is flagged `TODO(SME)` in section 5.

---

## 2. Clause-by-clause walk-through

### 2.1 `INSERT INTO BASE.FLT_FOLDER_LINKS ( … 33 columns … )`

The target is `BASE.FLT_FOLDER_LINKS`. The 33-column list fixes the **ordinal
binding** of the SELECT to the target: position 1 → `LINK_STATION_CD`, …,
position 33 → `CURRENT_REC_IND`. Per DEF-06, `INSERT … SELECT` binds by ordinal
position, so the `NEW_*` aliases on the SELECT side are cosmetic and do not
affect correctness — only readability. The column count is 33 = 33 (DEF-05
PASS, no duplicates on either side).

### 2.2 `SELECT NEW_LINK_STATION_CD, … , NEW_CURRENT_REC_IND FROM STAGING.ExpFinalyseInserts S`

Projects the 33 `NEW_*` columns from staging. Several aliases carry a
`_SMALLINT` or `_DATE` suffix (e.g. `NEW_IN_FLT_NO_SMALLINT`,
`NEW_IN_DEP_FLTDT_DATE`, `NEW_IN_ARR_FLTTM_DATE`, `NEW_MIDNIGHT_QTY_SMALLINT`).
The suffix describes the **cast applied in the staging view/CTE upstream of
this script**, not the type of the target column. Two positions are notable:
position 8 maps `NEW_IN_ARR_FLTTM_DATE` onto target `IN_ARR_FLTTM`, and position
18 maps `NEW_OUT_DEP_FLTTM_DATE` onto target `OUT_DEP_FLTTM` — a `_DATE`-cast
value feeding a `_TM` (time-of-day) target, a possible type-grain mismatch
flagged under SEM-06.

### 2.3 `WHERE S.IN_FLT_LEG_SEQ_NO IS NOT NULL AND S.OUT_FLT_LEG_SEQ_NO IS NOT NULL`

Two guard predicates that drop staging rows missing the inbound or outbound
leg sequence number. These are the only row-level filters before the anti-join;
they ensure only fully-formed link candidates (both legs sequenced) are
considered for insert.

### 2.4 `AND NOT EXISTS ( SELECT 1 FROM BASE.FLT_FOLDER_LINKS T WHERE … 33 equality predicates … )`

The dedup core. For each surviving staging row, the subquery probes the target
table on **all 33 columns** with equality (`=`). If any base row matches on all
33 keys, `NOT EXISTS` is false and the staging row is suppressed; otherwise the
staging row is inserted. This is an explicit anti-join dedup pattern written
into the SQL itself — it is **not** reliance on a Teradata SET table's implicit
duplicate suppression (SEM-05 does not fire; see section 3). The 33 predicates
are a pure conjunction of `T.<col> = S.NEW_<col>`; there is no `OR`, no range,
no `IN`, so the match is exact-full-row.

The fixed SQL is **byte-for-byte identical** to the buggy input in its SQL
logic. The only additions are the `FIX LOG` header and inline `TODO(SME)`
comments. There were **0 mechanical fixes** (no SFX/FNX/DTX/DEF findings), so
there is no "what the input would have done instead" divergence to describe —
the input already parsed and ran on Snowflake. The remediation here is purely
semantic-risk flagging, not rewriting.

---

## 3. Semantic checks table

| SEM ID | Risk | Present? | Corrected how? | Equivalent to Teradata? |
|---|---|---|---|---|
| SEM-01 | Integer division | **No** | n/a — no `/` in the statement | Yes (n/a) |
| SEM-02 | `QUALIFY` / dedup ordering | **No** | n/a — no `QUALIFY`/`ROW_NUMBER` | Yes (n/a) |
| SEM-03 | `CHAR(n)` padding & comparison | **Likely** (cannot confirm — no DDL) | **Not corrected** — flagged `TODO(SME)`. The 33-key `NOT EXISTS` compares `BASE.FLT_FOLDER_LINKS` against `STAGING.ExpFinalyseInserts`. Several keys are plausibly `CHAR(n)` (`*_CD`, `*_TYP`, `*_TXT`, `*_IND`, `*_SFX_CD`). Teradata blank-pads `CHAR(n)` and ignores trailing spaces in `=`; Snowflake does **not** pad, so `'A' <> 'A '` and the anti-join would suppress a different row set. **SME must confirm DDL; if any key is `CHAR(n)`, wrap both sides of each such predicate in `RTRIM(...)`.** | **SME** |
| SEM-04 | Timestamp / timezone | **No** | n/a — no `TIMESTAMP`/`TIMESTAMP_TZ`/`CURRENT_TIMESTAMP` constructs; `_DATE`/`_TM` columns are date/time grain, not timestamp-with-TZ (any residual TZ concern is folded into SEM-06) | Yes (n/a) |
| SEM-05 | SET-table dedup | **Not triggered** | n/a — this is a **single** `INSERT` with an **explicit** `NOT EXISTS` anti-join, not multiple INSERTs into one target nor a `UNION`/`UNION ALL` writing to one target. Per SEM-05 the SET-table signal does not fire from a single INSERT. The dedup is explicit in the SQL, not assumed from table DDL. | Yes (n/a) |
| SEM-06 | Implicit cast / type mismatch in comparison | **Likely** (cannot confirm — no DDL) | **Not corrected** — flagged `TODO(SME)`. The `_SMALLINT`/`_DATE`-suffixed SELECT aliases signal pre-cast staging values; the `NOT EXISTS` predicates then compare these against `BASE.FLT_FOLDER_LINKS` columns of unknown type. A mismatch (e.g. `DATE` vs `TIMESTAMP`, `VARCHAR` vs `NUMBER`, `TIME` vs `TIMESTAMP`) could silently change which rows the anti-join suppresses. Positions 8 (`IN_ARR_FLTTM`) and 18 (`OUT_DEP_FLTTM`) map a `_DATE`-cast alias onto a `_TM` target — a possible grain mismatch. **SME must confirm DDL types for both tables for every `_SMALLINT`/`_DATE`-suffixed column and confirm the `_TM` targets accept the `_DATE`-cast value.** | **SME** |
| SEM-07 | `NULL` ordering | **No** | n/a — no `ORDER BY` feeding `QUALIFY`/`TOP` | Yes (n/a) |
| SEM-08 | Empty string vs NULL | **No** | n/a — no `NULLIF(x,'')` or empty-string handling | Yes (n/a) |
| SEM-09 | Aggregate of empty set | **No** | n/a — no aggregates | Yes (n/a) |
| SEM-10 | Lookup join direction | **No** | n/a — the only join is the `NOT EXISTS` anti-join against the same target table; no exchange-rate/lookup join | Yes (n/a) |

**Net:** Two SME-classified risks (SEM-03, SEM-06), both unresolved pending DDL
for `BASE.FLT_FOLDER_LINKS` and `STAGING.ExpFinalyseInserts`. All other SEM-*
risks are absent.

---

## 4. Divergences from the original

There are **no intentional divergences** from the buggy Snowflake input. The
fixed SQL's statement body is identical to the input; only the `FIX LOG`
header block and inline `TODO(SME)` comments were added. Because 0 mechanical
fixes were required and no Teradata ground truth was supplied, there is nothing
to diverge from — the script already parsed and ran on Snowflake, and the
remediation is purely the semantic-risk inventory above.

The two open SME risks (SEM-03, SEM-06) are **potential** divergences from the
*intended* Teradata semantics, not from the buggy input. They are unresolved
because the DDL for both tables was not supplied. If the SME confirms either
risk is real, a follow-up fix (RTRIM wrapping for SEM-03; explicit casts for
SEM-06) will be applied and recorded as a new rule or lesson.

---

## 5. Open SME questions

Each `TODO(SME)` is phrased as a decision for a human reviewer.

1. **(SEM-03 — CHAR padding in the 33-key anti-join)** Are any of the 33
   `NOT EXISTS` comparison keys declared `CHAR(n)` (vs `VARCHAR`) in
   `BASE.FLT_FOLDER_LINKS` or `STAGING.ExpFinalyseInserts`? If yes, which
   ones, and should each `CHAR(n)` predicate be wrapped in `RTRIM(...)` on
   **both** sides so the anti-join suppresses the same rows Teradata would
   (blank-padding semantics)?
2. **(SEM-06 — `_SMALLINT`/`_DATE` suffix type compatibility)** Confirm the DDL
   types for both tables for every `_SMALLINT`- and `_DATE`-suffixed SELECT
   alias (`NEW_IN_FLT_NO_SMALLINT`, `NEW_IN_DEP_FLTDT_DATE`,
   `NEW_IN_ARR_FLTDT_DATE`, `NEW_IN_ARR_FLTTM_DATE`, `NEW_OUT_FLT_NO_SMALLINT`,
   `NEW_OUT_DEP_FLTDT_DATE`, `NEW_OUT_DEP_FLTTM_DATE`, `NEW_OUT_ARR_FLTDT_DATE`,
   `NEW_MIDNIGHT_QTY_SMALLINT`, `NEW_BUFFER_DUR_SMALLINT`,
   `NEW_STD_WORKING_DUR_SMALLINT`, `NEW_TOW_TIME_DUR_SMALLINT`). Do the
   `BASE.FLT_FOLDER_LINKS` target/probe columns match these types so
   Snowflake's implicit casts in the `NOT EXISTS` predicates produce the same
   row-suppression behaviour as Teradata?
3. **(SEM-06 — `_TM` target grain)** Positions 8 (`IN_ARR_FLTTM`) and 18
   (`OUT_DEP_FLTTM`) map a `_DATE`-cast staging alias onto a `_TM`
   (time-of-day) target. Is the `_DATE` cast actually a date, or does the
   staging view cast it to a `TIMESTAMP`/`TIME` that carries the time-of-day?
   If it is a pure `DATE`, the time-of-day component is lost — confirm whether
   that is intended or a staging-view bug.

---

## 6. Inline anchors

```anchors
INSERT INTO BASE.FLT_FOLDER_LINKS :: Idempotent upsert-load: insert staging rows into BASE.FLT_FOLDER_LINKS only if no identical row exists on all 33 keys (NOT EXISTS anti-join).
NEW_IN_FLT_NO_SMALLINT :: SEM-06: _SMALLINT-suffixed alias — confirm BASE.IN_FLT_NO type matches so the NOT EXISTS predicate suppresses the same rows as Teradata.
NEW_IN_DEP_FLTDT_DATE :: SEM-06: _DATE-suffixed alias — confirm BASE.IN_DEP_FLTDT type matches the _DATE-cast staging value.
NEW_IN_ARR_FLTDT_DATE :: SEM-06: _DATE-suffixed alias — confirm BASE.IN_ARR_FLTDT type matches the _DATE-cast staging value.
NEW_IN_ARR_FLTTM_DATE :: SEM-06: _DATE alias onto a _TM target (IN_ARR_FLTTM) — possible time-grain mismatch; confirm staging cast carries the time-of-day.
NEW_OUT_FLT_NO_SMALLINT :: SEM-06: _SMALLINT-suffixed alias — confirm BASE.OUT_FLT_NO type matches.
NEW_OUT_DEP_FLTDT_DATE :: SEM-06: _DATE-suffixed alias — confirm BASE.OUT_DEP_FLTDT type matches.
NEW_OUT_DEP_FLTTM_DATE :: SEM-06: _DATE alias onto a _TM target (OUT_DEP_FLTTM) — possible time-grain mismatch; confirm staging cast carries the time-of-day.
NEW_OUT_ARR_FLTDT_DATE :: SEM-06: _DATE-suffixed alias — confirm BASE.OUT_ARR_FLTDT type matches.
NEW_MIDNIGHT_QTY_SMALLINT :: SEM-06: _SMALLINT-suffixed alias — confirm BASE.MIDNIGHT_QTY type matches.
NEW_BUFFER_DUR_SMALLINT :: SEM-06: _SMALLINT-suffixed alias — confirm BASE.BUFFER_DUR type matches.
NEW_STD_WORKING_DUR_SMALLINT :: SEM-06: _SMALLINT-suffixed alias — confirm BASE.STD_WORKING_DUR type matches.
NEW_TOW_TIME_DUR_SMALLINT :: SEM-06: _SMALLINT-suffixed alias — confirm BASE.TOW_TIME_DUR type matches.
WHERE S.IN_FLT_LEG_SEQ_NO IS NOT NULL :: Guard: drop staging rows missing the inbound or outbound leg sequence number before the anti-join.
AND NOT EXISTS :: Dedup core: suppress any staging row that already exists in BASE.FLT_FOLDER_LINKS on all 33 keys (explicit anti-join, not SET-table dedup — SEM-05 does not fire).
WHERE T.LINK_STATION_CD = S.NEW_LINK_STATION_CD :: SEM-03: if LINK_STATION_CD is CHAR(n), Teradata blank-pads and ignores trailing spaces; Snowflake does not — confirm DDL and RTRIM both sides if CHAR(n).
AND T.IN_FLT_NO = S.NEW_IN_FLT_NO_SMALLINT :: SEM-03/SEM-06: CHAR padding + _SMALLINT cast — confirm both column types.
AND T.IN_DEP_FLTDT = S.NEW_IN_DEP_FLTDT_DATE :: SEM-03/SEM-06: CHAR padding + _DATE cast — confirm both column types.
AND T.FIXED_LINK_RSN_TXT = S.NEW_FIXED_LINK_RSN_TXT :: SEM-03: *_TXT is a likely CHAR(n) key — confirm DDL and RTRIM both sides if CHAR(n).
AND T.CURRENT_REC_IND = S.NEW_CURRENT_REC_IND :: SEM-03: *_IND is a likely CHAR(n) key — confirm DDL and RTRIM both sides if CHAR(n).
```