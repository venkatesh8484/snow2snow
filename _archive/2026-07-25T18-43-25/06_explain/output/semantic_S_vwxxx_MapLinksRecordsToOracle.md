# Stage 6 — Semantic explanation: `S_vwxxx_MapLinksRecordsToOracle.snowsql`

**Fixed SQL:** `03_fix/output/S_vwxxx_MapLinksRecordsToOracle_fixed.snowsql`
**Analysis:** `01_analyze/output/analysis_S_vwxxx_MapLinksRecordsToOracle.md`
**Teradata ground truth:** none supplied (no `00_input/<name>.teradata.sql`).
Every semantic inference below is flagged `TODO(SME)`.

---

## 1. Purpose

This SnowSQL ETL script ingests a flight-schedule **links** CSV file from a
local directory, stages it into a 28-column transient table
(`STAGING.Sq_Src_LinksCSVFile`), extracts the single header record (the row
where `FIELD1 = 'LINKS'`) into a one-line output CSV containing the current
date, schedule name, and reporting period, then inserts every detail link
record (rows where `FIELD1` is neither `'LINKS'` nor `'TRAILER'`) into
`STAGING.WRK_FLT_SCHED_LINKS` via `INSERT OVERWRITE`. One output row in
`WRK_FLT_SCHED_LINKS` represents one scheduled flight **link** — an inbound
leg (origin station, airline, flight number, arrival GMT date/time) paired
with its outbound leg (destination station, airline, flight number, departure
GMT date/time) plus aircraft and ground-handling attributes. The script is a
pure load-and-map step: no joins, no aggregation, no dedup — it reshapes a
flat 28-field CSV into the typed link table.

---

## 2. Clause-by-clause walk-through

### 2.1 `CREATE OR REPLACE TRANSIENT TABLE STAGING.Sq_Src_LinksCSVFile`

Creates a throwaway transient staging table with 28 `VARCHAR` columns
(`FIELD1` … `FIELD28`), each sized to its expected CSV field width. All
columns are `VARCHAR` because the raw CSV is loaded as text; type conversion
happens later in the `INSERT … SELECT`. `TRANSIENT` means Snowflake does not
retain fail-safe backups — appropriate for a re-loadable staging table.

### 2.2 `PUT file://<% … %> @<% … %> OVERWRITE = TRUE AUTO_COMPRESS = FALSE`

**SNZ-02 — preserved verbatim.** Uploads the local CSV file from the
orchestrator-supplied input directory (`ctx.env.…InputFile_DIR`) to the
landing stage (`ctx.env.LANDING_STAGE`). `OVERWRITE = TRUE` replaces any
prior file of the same name; `AUTO_COMPRESS = FALSE` keeps the file as plain
CSV so the subsequent `COPY INTO` can read it with `TYPE='CSV'`. This is a
SnowSQL client command, not SQL — it is never rewritten.

### 2.3 `COPY INTO STAGING.Sq_Src_LinksCSVFile FROM @<% … %>/<% … %>`

**SNZ-04 — valid Snowflake SQL.** Loads the staged CSV into the transient
table. `FILE_FORMAT = (TYPE='CSV', FIELD_DELIMITER=',',
ERROR_ON_COLUMN_COUNT_MISMATCH=FALSE)` tolerates rows whose field count
differs from 28 — necessary because the file contains a `'LINKS'` header row
and a `'TRAILER'` footer row that do not have 28 fields. Extra or short
fields are NULL-padded / truncated by position.

### 2.4 `REMOVE @<% … %>/<% … %>`

**SNZ-04.** Deletes the uploaded CSV from the landing stage after it has been
copied into the table, keeping the stage clean.

### 2.5 `COPY INTO @<% … %>/<% … %> FROM (SELECT … WHERE FIELD1 = 'LINKS')`

**SNZ-04.** Extracts the header record into a single output CSV file on the
stage. The inner `SELECT` picks four fields from the one row where
`FIELD1 = 'LINKS'`:

- `FIELD2 AS CURRENT_DATE` — the run/report date.
- `FIELD3 AS SCHEDULE_NAME` — the schedule identifier.
- `FIELD5 AS PERIOD_START` — reporting period start.
- `FIELD6 AS PERIOD_END` — reporting period end.

`FILE_FORMAT = (TYPE='CSV', ENCODING='WINDOWS1252', FIELD_DELIMITER=',',
COMPRESSION=NONE)`, `SINGLE = TRUE`, `OVERWRITE = TRUE` guarantee one
uncompressed, Windows-1252-encoded CSV file. `CURRENT_DATE` is used as a
column alias here, not as the Snowflake function — inside a
`COPY INTO … FROM (SELECT …)` it is an output column name, so it parses.

### 2.6 `GET @<% … %>/<% … %> file://<% … %> OVERWRITE = TRUE`

**SNZ-03 — preserved verbatim.** Downloads the header CSV from the stage back
to the orchestrator-supplied output directory. SnowSQL client command — never
rewritten.

### 2.7 `REMOVE @<% … %>/<% … %>`

**SNZ-04.** Cleans the header CSV off the stage after the `GET`.

### 2.8 `INSERT OVERWRITE INTO STAGING.WRK_FLT_SCHED_LINKS (… 28 cols …) SELECT … 28 exprs …`

The core mapping step. `INSERT OVERWRITE` truncates the target table first,
then inserts the selected rows — so this is a full refresh of
`WRK_FLT_SCHED_LINKS`, not an append. The `SELECT` reads from
`STAGING.Sq_Src_LinksCSVFile` and filters out the header (`'LINKS'`) and
footer (`'TRAILER'`) rows, leaving only detail link records.

The 28 SELECT expressions map CSV fields to typed link columns positionally:

- **Station / airline / flight number** — `SUBSTR(FIELD2,1,3)` →
  `LINK_STN_CD`; `FIELD25` → `IN_ORIGN_STN_CD`; `SUBSTR(FIELD3,1,3)` →
  `IN_ALN_CD`; `SUBSTR(FIELD4,1,4)` → `IN_FLT_NO`; and symmetrically
  `FIELD27` → `OUT_DESTN_STN_CD`, `FIELD11` → `OUT_ALN_CD`,
  `FIELD12` → `OUT_FLT_NO`.
- **Flight suffix code** — `IFF(SUBSTR(FIELD5,1,1) IS NULL,' ',
  SUBSTR(FIELD5,1,1))` → `IN_FLT_SFX_CD` and the same pattern on `FIELD13`
  → `OUT_FLT_SFX_CD`. A NULL suffix is replaced with a single space `' '`,
  not an empty string or NULL (SEM-08).
- **GMT dates** — `FIELD26` → `IN_DEP_GMT_FLT_DT`, `FIELD6` →
  `IN_ARR_GMT_FLT_DT`, `FIELD14` → `OUT_DEP_GMT_FLT_DT`, `FIELD28` →
  `OUT_ARR_GMT_FLT_DT`. These are stored as raw strings (the CSV date
  field), not converted.
- **GMT times** — `TO_TIMESTAMP(FIELD6 || FIELD7,'DDMONYYHH24MI')` →
  `IN_ARR_GMT_FLT_TM` and `TO_TIMESTAMP(FIELD14 || FIELD15,'DDMONYYHH24MI')`
  → `OUT_DEP_GMT_FLT_TM`. The date string (`FIELD6`/`FIELD14`, e.g.
  `01JAN23`) is concatenated with the time string (`FIELD7`/`FIELD15`, e.g.
  `1430`) and parsed with the `DDMONYYHH24MI` mask into a `TIMESTAMP_NTZ`
  (SEM-04, SEM-06, OBS-01). Note `FIELD6` and `FIELD14` are reused: once as
  the raw date column and once inside the timestamp concatenation — this is
  intentional.
- **Remaining attributes** — terminal codes, ground activity codes, service
  types, aircraft owner, carrier aircraft type, midnight quantity, buffer
  duration, standard working duration, tow time duration, and fixed-link
  reason text are mapped 1:1 from their respective `FIELD` columns
  (`FIELD9`, `FIELD18`, `FIELD20`, `FIELD10`, `FIELD19`, `FIELD21`,
  `FIELD22`, `SUBSTR(FIELD1,1,3)`, `FIELD8`, `FIELD16`, `FIELD17`,
  `FIELD23`, `FIELD24`).

No joins, no `GROUP BY`, no `QUALIFY`, no `ORDER BY` — the grain of the
output is exactly the grain of the filtered CSV rows.

---

## 3. Semantic checks table

| SEM ID | Risk | Present? | Corrected how? | Equivalent? |
|---|---|---|---|---|
| SEM-01 | Integer division | **No.** No `/` arithmetic in the script. | n/a | Yes |
| SEM-02 | `QUALIFY` / dedup ordering | **No.** No `QUALIFY` or `ROW_NUMBER()`. | n/a | Yes |
| SEM-03 | `CHAR(n)` padding & comparison | **No.** All staging columns are `VARCHAR(n)`; no `CHAR(n)` comparisons. | n/a | Yes |
| SEM-04 | Timestamp / timezone | **Yes.** Two `TO_TIMESTAMP(…,'DDMONYYHH24MI')` calls (lines 80, 88) produce `TIMESTAMP_NTZ` by default. Target columns are named `*_GMT_FLT_TM`. | Not corrected — no rule forces a change. NTZ is plausibly correct for a GMT-named column, but the session `TIMEZONE` and intended TZ must be confirmed. Flagged `TODO(SME)`. | **SME** |
| SEM-05 | SET-table dedup | **Yes — low priority.** `INSERT OVERWRITE INTO STAGING.WRK_FLT_SCHED_LINKS`; target DDL not supplied in this script. | Not corrected — `INSERT OVERWRITE` truncates first, so SET-vs-MULTISET dedup is irrelevant for this statement. Flagged for awareness only. | **Yes-with-assumption** (OVERWRITE makes dedup moot) |
| SEM-06 | Implicit cast / NULL in comparison | **Yes.** `FIELD6 \|\| FIELD7` and `FIELD14 \|\| FIELD15` concatenation: Snowflake `\|\|` returns `NULL` if any operand is `NULL`. No `IFF`/`COALESCE` guard wraps these, unlike the suffix fields. | Not corrected — no rule forces a change. If `FIELD7` or `FIELD15` is NULL, the whole timestamp becomes NULL and `TO_TIMESTAMP` yields NULL (not an error). Confirm whether NULL timestamps are acceptable. Flagged `TODO(SME)`. | **SME** |
| SEM-07 | NULL ordering | **No.** No `ORDER BY` feeding `QUALIFY`/`TOP`. | n/a | Yes |
| SEM-08 | Empty string vs NULL | **Yes.** `IFF(SUBSTR(FIELD5,1,1) IS NULL,' ',SUBSTR(FIELD5,1,1))` and the same on `FIELD13` substitute a single space `' '` for NULL — not `''` and not NULL. | Not corrected — this matches a likely Teradata pad-with-space intent, but confirm the target column expects `' '` vs `''` vs NULL. Flagged `TODO(SME)`. | **SME** |
| SEM-09 | Aggregate of empty set | **No.** No aggregates. | n/a | Yes |
| SEM-10 | Join-key grain mismatch | **No.** No joins; single-table SELECT. | n/a | Yes |

**Additional observation (no rule ID yet — proposed for review):**

| ID | Observation | Equivalent? |
|---|---|---|
| OBS-01 | `TO_TIMESTAMP(…,'DDMONYYHH24MI')` — the `MON` element is locale-dependent and case-sensitive. If the CSV uses a different month abbreviation case or locale, parsing fails or mis-parses. Confirm the CSV date format and locale. | **SME** |

---

## 4. Divergences from the original

**None.** The fixed file is byte-for-byte identical to the buggy input except
for the `FIX LOG` header block and inline `-- TODO(SME)` comments added at the
top and around the flagged expressions. Zero mechanical fixes (`SFX-*`,
`FNX-*`, `DTX-*`, `DEF-*`) were applied — the SQL body was already
parse-clean Snowflake. Column count is 28 = 28 (PASS). All 14 template tags
(SNZ-01), the `PUT` (SNZ-02), and the `GET` (SNZ-03) are preserved verbatim;
the `COPY INTO` / `REMOVE` statements (SNZ-04) are valid Snowflake SQL and
were not modified. The only additions are explanatory comments — no SQL logic
changed.

---

## 5. Open SME questions

Each item is a decision for a human reviewer. No Teradata ground truth is
available, so every inference is an assumption until confirmed.

1. **SEM-04 — Timestamp timezone:** `TO_TIMESTAMP(FIELD6 || FIELD7,
   'DDMONYYHH24MI')` yields `TIMESTAMP_NTZ`. The target columns
   `IN_ARR_GMT_FLT_TM` and `OUT_DEP_GMT_FLT_TM` are GMT-named. **Decision:**
   is `TIMESTAMP_NTZ` the correct type for these GMT flight times, or should
   they be `TIMESTAMP_TZ` / `TIMESTAMP_LTZ` with an explicit GMT offset?

2. **SEM-06 — NULL in timestamp concatenation:** `FIELD6 || FIELD7` (and
   `FIELD14 || FIELD15`) returns `NULL` if either operand is `NULL`, which
   makes `TO_TIMESTAMP` return `NULL` silently. The suffix fields use an
   `IFF(… IS NULL, …)` guard; these do not. **Decision:** should a NULL
   `FIELD7`/`FIELD15` produce a NULL timestamp (current behavior), or should
   it be guarded (e.g. `COALESCE(FIELD7,'')` or a default time)?

3. **SEM-08 — Space vs empty-string vs NULL for suffix code:**
   `IFF(SUBSTR(FIELD5,1,1) IS NULL,' ',SUBSTR(FIELD5,1,1))` substitutes a
   single space `' '` for a NULL suffix. **Decision:** does the target
   `IN_FLT_SFX_CD` / `OUT_FLT_SFX_CD` expect `' '`, `''`, or `NULL` when the
   suffix is absent?

4. **SEM-05 — Target table SET vs MULTISET:** the DDL for
   `STAGING.WRK_FLT_SCHED_LINKS` is not in this script. **Decision:** is the
   target a SET or MULTISET table? (Low priority — `INSERT OVERWRITE`
   truncates first, so dedup does not apply to this statement, but the
   table's nature matters for any other writers.)

5. **OBS-01 — Date format mask and locale:** `'DDMONYYHH24MI'` assumes the
   CSV date field looks like `01JAN23` and the time field like `1430`, and
   that `MON` matches the session locale's month abbreviations. **Decision:**
   confirm the CSV date/time format and the Snowflake session locale so the
   mask parses correctly.

---

## 6. Inline anchors

```anchors
CREATE OR REPLACE TRANSIENT TABLE STAGING.Sq_Src_LinksCSVFile :: Transient 28-VARCHAR staging table for the raw links CSV; re-loadable, no fail-safe.
PUT file://<% ctx.env.S_vwxxxx_MapLinksRecordsToOracle_InputFile_DIR %> :: SNZ-02 PUT — uploads local CSV to landing stage; preserved verbatim, never rewritten.
COPY INTO STAGING.Sq_Src_LinksCSVFile :: SNZ-04 — loads staged CSV into the transient table; ERROR_ON_COLUMN_COUNT_MISMATCH=FALSE tolerates the LINKS header and TRAILER footer rows.
REMOVE @<% ctx.env.LANDING_STAGE %>/<% ctx.env.S_vwxxxx_MapLinksRecordsToOracle_InputFileName %> :: SNZ-04 — cleans the input CSV off the stage after the COPY INTO.
COPY INTO @<% ctx.env.LANDING_STAGE %>/<% ctx.env.S_vwxxxx_MapLinksRecordsToOracle_OutputFileName %> :: SNZ-04 — extracts the single LINKS header row into a one-line output CSV (CURRENT_DATE, SCHEDULE_NAME, PERIOD_START, PERIOD_END).
WHERE FIELD1 = 'LINKS' :: Header-row filter — selects only the LINKS record for the header-extract COPY INTO.
GET @<% ctx.env.LANDING_STAGE %>/<% ctx.env.S_vwxxxx_MapLinksRecordsToOracle_OutputFileName %> :: SNZ-03 GET — downloads the header CSV back to the local output directory; preserved verbatim.
INSERT OVERWRITE INTO STAGING.WRK_FLT_SCHED_LINKS :: Core mapping step — truncates then inserts detail link rows; full refresh, not append. SEM-05: target DDL not supplied.
IFF(SUBSTR(FIELD5,1,1) IS NULL,' ',SUBSTR(FIELD5,1,1)) :: SEM-08 — substitutes a single space ' ' for a NULL flight suffix; confirm ' ' vs '' vs NULL intent.
TO_TIMESTAMP(FIELD6 || FIELD7,'DDMONYYHH24MI') :: SEM-04 (TIMESTAMP_NTZ for GMT-named target), SEM-06 (|| returns NULL if either operand NULL, no guard), OBS-01 (DDMONYYHH24MI mask is locale-dependent).
TO_TIMESTAMP(FIELD14 || FIELD15,'DDMONYYHH24MI') :: SEM-04 / SEM-06 / OBS-01 — same timestamp risks as the inbound leg, applied to the outbound departure time.
WHERE FIELD1 NOT IN ('LINKS','TRAILER') :: Detail-row filter — excludes the header and footer so only link detail records reach WRK_FLT_SCHED_LINKS.
```