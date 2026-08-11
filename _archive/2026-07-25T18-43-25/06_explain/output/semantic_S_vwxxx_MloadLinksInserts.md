# Stage 6 — Semantic explanation: `S_vwxxx_MloadLinksInserts`

**Fixed SQL:** `03_fix/output/S_vwxxx_MloadLinksInserts_fixed.snowsql`
**Analysis:** `01_analyze/output/analysis_S_vwxxx_MloadLinksInserts.md`
**Teradata ground truth:** none supplied (`00_input/S_vwxxx_MloadLinksInserts.teradata.sql` absent). Semantic intent is inferred from the Snowflake input and naming conventions; every inference is flagged `TODO(SME)`.

---

## 1. Purpose

This statement loads **new** flight-folder link rows from the staging view
`STAGING.ExpFinalyseInserts` into the base table `BASE.FLT_FOLDER_LINKS`. A
"folder link" connects an inbound flight leg (carrier, flight number, departure
date/time, passenger terminal, ground activity, service type, leg sequence) to
an outbound flight leg, plus aircraft-owner, aircraft-type, and timing
attributes (midnight quantity, buffer duration, standard working duration, tow
time), a fixed-link reason text, effective/expiry dates, and a current-record
indicator. The grain of one output row is one complete inbound→outbound link
identified by all 33 columns. The `NOT EXISTS` anti-join against the same base
table suppresses any staging row whose full 33-column signature already exists
in `BASE.FLT_FOLDER_LINKS`, so only genuinely new links are inserted — this is
the Snowflake emulation of a Teradata `SET`-table silent-dedup INSERT.

---

## 2. Clause-by-clause walk-through

### `INSERT INTO BASE.FLT_FOLDER_LINKS ( … 33 columns … )`
Lists the 33 target columns in a fixed positional order: inbound leg keys first
(`LINK_STATION_CD`, `IN_ORIGN_STATION_CD`, `IN_ALN_CD`, `IN_FLT_NO`,
`IN_FLT_SFX_CD`, `IN_DEP_FLTDT`, `IN_ARR_FLTDT`, `IN_ARR_FLTTM`, `IN_PAX_TML_CD`,
`IN_GROUND_ACY_CD`, `IN_SERVICE_TYP`, `IN_FLT_LEG_SEQ_NO`), then outbound leg
keys (`OUT_DESTATION_STATION_CD` … `OUT_FLT_LEG_SEQ_NO`), then aircraft/timing
attributes (`AIRCRAFT_OWNER_CD`, `CARRIER_AC_TYP`, `MIDNIGHT_QTY`, `BUFFER_DUR`,
`STD_WORKING_DUR`, `TOW_TIME_DUR`), then text/date/indicator columns
(`FIXED_LINK_RSN_TXT`, `LINK_EFFECTIVE_DT`, `LINK_EXPIRY_DT`, `CURRENT_REC_IND`).
Column order is preserved exactly from the input.

### `SELECT NEW_LINK_STATION_CD, … NEW_CURRENT_REC_IND`
Selects the 33 corresponding `NEW_*` staging columns from
`STAGING.ExpFinalyseInserts`. The SELECT list is positionally aligned 1:1 with
the INSERT list (33 = 33, verified in analysis §1). Several aliases carry
`_SMALLINT` or `_DATE` suffixes (`NEW_IN_FLT_NO_SMALLINT`,
`NEW_IN_DEP_FLTDT_DATE`, `NEW_OUT_FLT_NO_SMALLINT`, `NEW_OUT_DEP_FLTDT_DATE`,
`NEW_OUT_ARR_FLTDT_DATE`, `NEW_OUT_DEP_FLTTM_DATE`, `NEW_IN_ARR_FLTDT_DATE`,
`NEW_IN_ARR_FLTTM_DATE`, `NEW_MIDNIGHT_QTY_SMALLINT`, `NEW_BUFFER_DUR_SMALLINT`,
`NEW_STD_WORKING_DUR_SMALLINT`, `NEW_TOW_TIME_DUR_SMALLINT`), signalling that
the upstream converter already cast these staging values. No transformation is
applied here — the SELECT is a straight column projection.

### `FROM STAGING.ExpFinalyseInserts S`
Single source table, aliased `S`. No joins in the outer query.

### `WHERE S.IN_FLT_LEG_SEQ_NO IS NOT NULL AND S.OUT_FLT_LEG_SEQ_NO IS NOT NULL`
Pre-filters staging rows so both the inbound and outbound leg sequence numbers
are present. Rows missing either sequence are dropped before the anti-join —
they are considered incomplete links and never inserted.

### `AND NOT EXISTS ( SELECT 1 FROM BASE.FLT_FOLDER_LINKS T WHERE T.<col> = S.NEW_<col> [×33] )`
The dedup guard. For each surviving staging row, the correlated subquery checks
whether **all 33** columns already match an existing base row. The 33 predicates
mirror the INSERT/SELECT column list one-for-one (`T.LINK_STATION_CD =
S.NEW_LINK_STATION_CD` … `T.CURRENT_REC_IND = S.NEW_CURRENT_REC_IND`). If a full
match is found, `NOT EXISTS` is false and the staging row is suppressed; if no
full match exists, the row is inserted. This is the SET-table dedup emulation
pattern: Teradata would silently drop a full-row duplicate on INSERT into a SET
table, and this explicit anti-join reproduces that behaviour on Snowflake (which
keeps duplicates by default). The anti-join reads the same `BASE.FLT_FOLDER_LINKS`
table that the INSERT writes to (read-then-write within one statement).

---

## 3. Semantic checks table

| SEM ID | Risk | Present? | Corrected how? | Equivalent to Teradata? |
|---|---|---|---|---|
| SEM-01 | Integer division | No | — | N/A (no division operators) |
| SEM-02 | `QUALIFY` / dedup ordering | No | — | N/A (no `QUALIFY`/`ROW_NUMBER`) |
| SEM-03 | `CHAR(n)` padding & comparison | **Possible** — the 33-key `NOT EXISTS` anti-join compares `BASE.FLT_FOLDER_LINKS` against `STAGING.ExpFinalyseInserts`; several key columns are plausibly `CHAR(n)` by naming (`*_CD`, `*_TYP`, `*_TXT`, `*_IND`). | Not corrected — no DDL supplied to confirm types. `TODO(SME)` markers added in the fixed SQL. If any key is `CHAR(n)`, wrap both sides of each such predicate in `RTRIM()` so the anti-join suppresses the same rows Teradata would. | **SME** — cannot confirm without target/source DDL. |
| SEM-04 | Timestamp / timezone | No | — | N/A (`_DATE`-suffixed aliases suggest `DATE`, no `TIMESTAMP_TZ`/`LTZ` constructs) |
| SEM-05 | SET-table dedup | **Signal present** — this is a single `INSERT … NOT EXISTS` anti-join that emulates SET-table silent dedup. | Not "corrected" — the anti-join *is* the dedup emulation. Whether `BASE.FLT_FOLDER_LINKS` is actually a SET table lives in its `CREATE TABLE` DDL, which is not supplied. | **SME** — confirm `BASE.FLT_FOLDER_LINKS` is a SET table; if it is, this anti-join is the correct emulation. If it is MULTISET, the anti-join is still a valid idempotent-load guard. |
| SEM-06 | Implicit cast / NULL in comparison | **Possible** — SELECT aliases carry `_SMALLINT` and `_DATE` casts; the `NOT EXISTS` predicates compare these against `BASE.FLT_FOLDER_LINKS` columns whose types are unknown. | Not corrected — no DDL supplied. `TODO(SME)` markers added on each `_SMALLINT`/`_DATE` SELECT line. If base column types differ (e.g. `NUMBER` vs `SMALLINT`, `TIMESTAMP` vs `DATE`, `VARCHAR` vs `NUMBER`), make casts explicit to preserve Teradata row-suppression behaviour. | **SME** — cannot confirm without target DDL. |
| SEM-07 | `NULL` ordering | No | — | N/A (no `ORDER BY`/`QUALIFY`) |
| SEM-08 | Empty string vs NULL | No | — | N/A (no `NULLIF(x,'')` or empty-string comparisons) |
| SEM-09 | Aggregate of empty set | No | — | N/A (no aggregates) |
| SEM-10 | Join-key grain / direction | No | — | Yes — the 33 anti-join predicates follow a uniform `T.<base_col> = S.NEW_<base_col>` pattern matching the INSERT/SELECT list exactly; no alias-name mismatch hides a grain swap. |

---

## 4. Divergences from the original

**None.** Zero mechanical fixes were applied (SFX/FNX/DTX/DEF/SNZ all = 0). The
SQL logic is byte-for-byte identical to the input except for the added `FIX LOG`
header and inline `TODO(SME)` comments. No clause was rewritten, no column
reordered, no predicate altered. The file is a clean, parseable Snowflake
`INSERT … SELECT … NOT EXISTS` exactly as supplied.

---

## 5. Open SME questions

1. **SEM-03 — CHAR(n) padding:** Are any of the 33 anti-join key columns in
   `BASE.FLT_FOLDER_LINKS` declared `CHAR(n)` (e.g. `LINK_STATION_CD`,
   `IN_ALN_CD`, `IN_SERVICE_TYP`, `FIXED_LINK_RSN_TXT`, `CURRENT_REC_IND`)? If
   yes, do the corresponding `STAGING.ExpFinalyseInserts` values carry the same
   trailing-space padding? **Decision:** if padding differs, wrap both sides of
   each `CHAR(n)` predicate in `RTRIM()` so the anti-join suppresses the same
   rows Teradata would; otherwise leave as-is.

2. **SEM-05 — SET vs MULTISET target:** Is `BASE.FLT_FOLDER_LINKS` a `SET`
   table? **Decision:** if SET, this `NOT EXISTS` anti-join is the correct
   dedup emulation and should be kept; if MULTISET, decide whether the
   idempotent-load guard is still desired or whether plain `INSERT … SELECT`
   should replace it.

3. **SEM-06 — implicit cast on `_SMALLINT` keys:** What are the declared types
   of `IN_FLT_NO`, `OUT_FLT_NO`, `MIDNIGHT_QTY`, `BUFFER_DUR`,
   `STD_WORKING_DUR`, `TOW_TIME_DUR` in `BASE.FLT_FOLDER_LINKS`, and do they
   match the `_SMALLINT`-cast staging values? **Decision:** if the base columns
   are a wider numeric (e.g. `NUMBER(10)`), confirm Snowflake's implicit
   widening cast preserves the same equality semantics; if they are a different
   family (e.g. `VARCHAR`), make the cast explicit to avoid silent coercion
   drift in the anti-join.

4. **SEM-06 — implicit cast on `_DATE` keys:** What are the declared types of
   the `*_FLTDT` and `*_FLTTM` columns in `BASE.FLT_FOLDER_LINKS` versus the
   `_DATE`-suffixed staging values? **Decision:** if base columns are
   `TIMESTAMP` and staging is `DATE`, decide whether to cast the staging value
   to `TIMESTAMP` (or truncate the base to `DATE`) so the anti-join compares
   the same granularity and suppresses the same rows Teradata would.

---

## 6. Inline anchors

```anchors
MATCH INSERT INTO BASE.FLT_FOLDER_LINKS :: Loads new flight-folder link rows from staging into the base table; 33 columns, positional 1:1 with the SELECT list.
MATCH FROM STAGING.ExpFinalyseInserts S :: Single staging source; supplies all 33 NEW_* columns for the inbound→outbound link grain.
MATCH WHERE S.IN_FLT_LEG_SEQ_NO IS NOT NULL :: Pre-filters staging rows so both inbound and outbound leg sequence numbers are present before the anti-join.
MATCH AND NOT EXISTS :: SET-table dedup emulation: suppress any staging row whose full 33-column signature already exists in BASE.FLT_FOLDER_LINKS.
MATCH FROM BASE.FLT_FOLDER_LINKS T :: Anti-join reference is the same table being inserted into (read-then-write within one statement).
MATCH T.LINK_STATION_CD = S.NEW_LINK_STATION_CD :: First of 33 full-row anti-join predicates; all 33 must match to suppress a duplicate insert.
MATCH T.IN_FLT_NO = S.NEW_IN_FLT_NO_SMALLINT :: SEM-06 risk: _SMALLINT-cast staging value compared against unknown BASE column type — confirm types match.
MATCH T.IN_DEP_FLTDT = S.NEW_IN_DEP_FLTDT_DATE :: SEM-06 risk: _DATE-cast staging value compared against unknown BASE column type — confirm DATE vs TIMESTAMP granularity.
MATCH T.CURRENT_REC_IND = S.NEW_CURRENT_REC_IND :: Last of 33 anti-join predicates; plausibly CHAR(n) — SEM-03 padding drift risk if BASE column is CHAR.
```