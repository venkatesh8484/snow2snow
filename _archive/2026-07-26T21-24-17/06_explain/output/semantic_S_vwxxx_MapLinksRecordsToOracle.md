# Semantic Explanation — `S_vwxxx_MapLinksRecordsToOracle.snowsql`

**Fixed SQL:** `03_fix/output/S_vwxxx_MapLinksRecordsToOracle_fixed.snowsql`
**Analysis:** `01_analyze/output/analysis_S_vwxxx_MapLinksRecordsToOracle.md`
**Teradata ground truth:** **Not supplied.** No `00_input/S_vwxxx_MapLinksRecordsToOracle.teradata.sql` exists. Semantic intent is inferred from `02_rules/` and the Snowflake input alone; every inference is flagged `TODO(SME)`.
**Mechanical fixes applied:** **0.** The script is parse-clean Snowflake. The entire remediation is `TODO(SME)` markers at semantic-risk locations plus `[KEEP]` lines in the FIX LOG for the SnowSQL client layer. No SQL logic line was changed.

---

## 1. Purpose

This is a **SnowSQL ETL script** that loads a flight-schedule links CSV from the
client filesystem into a transient Snowflake staging table, extracts the
header record back out to a CSV on the stage, downloads it to the client, and
finally reshapes the detail rows into the `STAGING.WRK_FLT_SCHED_LINKS` target
table via `INSERT OVERWRITE`.

In business terms: a links CSV (one header row tagged `'LINKS'`, many detail
rows, one trailer row tagged `'TRAILER'`) is split into two outputs —

1. a **header CSV** carrying `CURRENT_DATE`, `SCHEDULE_NAME`, `PERIOD_START`,
   `PERIOD_END` (the run's metadata), and
2. the **detail link rows** in `WRK_FLT_SCHED_LINKS`, one row per inbound→outbound
   flight connection (the grain: one link = one inbound flight leg paired with
   one outbound flight leg at a station).

The grain of one detail row is a single flight-schedule link: inbound carrier /
number / suffix / arrival GMT date+time, paired with outbound carrier / number /
suffix / departure GMT date+time, plus station, aircraft, and timing attributes.

---

## 2. Clause-by-clause walk-through

### 2.1 `CREATE OR REPLACE TRANSIENT TABLE STAGING.Sq_Src_LinksCSVFile` (lines 1–11)

Creates a 28-column all-`VARCHAR` transient staging table (`FIELD1` … `FIELD28`)
to receive the raw CSV. `TRANSIENT` means no fail-safe retention — appropriate
for a throwaway load buffer. Column widths mirror the expected CSV field sizes.
No semantic risk here; this is a pure landing buffer.

### 2.2 `PUT` (lines 13–14) — **SNZ-02 KEEP**

`PUT file://<% ctx.env.S_vwxxxx_MapLinksRecordsToOracle_InputFile_DIR %> @<% ctx.env.LANDING_STAGE %> OVERWRITE=TRUE AUTO_COMPRESS=FALSE`

Uploads the input CSV from the client filesystem to the SnowSQL stage. This is a
**SnowSQL client command**, not SQL — preserved verbatim per `SNZ-02`. The
`<% ctx.env.* %>` template tags are resolved by the orchestrator, not by us
(`SNZ-01`). `AUTO_COMPRESS=FALSE` keeps the file as plain CSV so the downstream
`COPY INTO` can parse it directly.

### 2.3 `COPY INTO STAGING.Sq_Src_LinksCSVFile FROM @stage/file` (lines 17–18)

Loads the staged CSV into the transient table. `ERROR_ON_COLUMN_COUNT_MISMATCH=FALSE`
tolerates rows whose field count differs from 28 (the header/trailer rows have
fewer fields) — this is intentional, since the script later filters on `FIELD1`.
CSV type with comma delimiter. No semantic risk.

### 2.4 `REMOVE @stage/file` (line 20) — **SNZ-04 KEEP**

Deletes the staged input file after the load. Stage-management command,
preserved verbatim. (Not `EXPLAIN`-able by the validator — environment gap, not
a defect; the control input fails identically.)

### 2.5 `COPY INTO @stage/output FROM (SELECT …)` — header extract (lines 24–32)

This is the **header-record extraction**. The inner `SELECT` pulls the single
row where `FIELD1 = 'LINKS'` and projects four columns:

- `FIELD2 AS CURRENT_DATE`
- `FIELD3 AS SCHEDULE_NAME`
- `FIELD5 AS PERIOD_START`
- `FIELD6 AS PERIOD_END`

The result is written back to the stage as a single CSV file
(`SINGLE=TRUE`, `OVERWRITE=TRUE`, `WINDOWS1252` encoding). This file is the
run-metadata header that downstream consumers (the Oracle target, per the
script name) expect alongside the detail load.

> **SEM-04 / FNX-14 note:** `CURRENT_DATE` is used as a **column alias** here,
> shadowing the Snowflake keyword/function of the same name. Snowflake permits
> it as an alias, but it is fragile. With no Teradata ground truth we cannot
> confirm whether the original intended the function `CURRENT_DATE` (today's
> date) or a literal header label named "CURRENT_DATE". The alias is
> positional for the CSV output, so the value is whatever `FIELD2` holds on
> the `'LINKS'` row — i.e. a label, not the function. Flagged `TODO(SME)`.

### 2.6 `GET @stage/output file://dir` (lines 37–38) — **SNZ-03 KEEP**

Downloads the header CSV from the stage back to the client filesystem. SnowSQL
client command, preserved verbatim per `SNZ-03`.

### 2.7 `REMOVE @stage/output` (line 40) — **SNZ-04 KEEP**

Cleans up the staged output file after the download. Preserved verbatim.

### 2.8 `INSERT OVERWRITE INTO STAGING.WRK_FLT_SCHED_LINKS (… 28 cols …) SELECT …` (lines 43–72)

This is the **detail-load** — the semantic heart of the script. `INSERT
OVERWRITE` truncates the target then inserts, so SET-vs-MULTISET dedup is **not**
in play for this statement (overwrite replaces; it does not dedup). The
`SELECT` reads the staging table and filters out the header and trailer:

`WHERE FIELD1 NOT IN ('LINKS','TRAILER')` — keeps only detail rows.

The 28 SELECT expressions map CSV fields to target columns. The mapping is
non-trivial (fields are not in target order); key transformations:

- **Station / carrier / flight number** are extracted with `SUBSTR`:
  `SUBSTR(FIELD2,1,3) → LINK_STN_CD`, `SUBSTR(FIELD3,1,3) → IN_ALN_CD`,
  `SUBSTR(FIELD4,1,4) → IN_FLT_NO`, `SUBSTR(FIELD1,1,3) → AIRCRAFT_OWNER_CD`.
- **Flight suffix codes** (`IN_FLT_SFX_CD`, `OUT_FLT_SFX_CD`) are guarded:
  `IFF(SUBSTR(FIELD5,1,1) IS NULL,' ',SUBSTR(FIELD5,1,1))` — substitutes a
  single space `' '` when the source cell is NULL. See SEM-08 below.
- **GMT date/time** for the inbound arrival and outbound departure are built
  by concatenating a date field and a time field and parsing with
  `TO_TIMESTAMP(FIELD6 || FIELD7,'DDMONYYHH24MI')` (inbound arrival) and
  `TO_TIMESTAMP(FIELD14 || FIELD15,'DDMONYYHH24MI')` (outbound departure). See
  SEM-04, SEM-06, OBS-01 below.
- The remaining columns are direct field-to-column mappings (`FIELD26 →
  IN_DEP_GMT_FLT_DT`, `FIELD9 → IN_PAX_TML_CD`, etc.).

**No `JOIN`, no `CASE`, no `QUALIFY`, no `ORDER BY`, no aggregate, no division**
appears anywhere in the script — so SEM-01, SEM-02, SEM-07, SEM-09, SEM-10 are
all **not present**.

---

## 3. Semantic checks table

| ID | Risk | Present? | Corrected how? | Equivalent to Teradata? |
|---|---|---|---|---|
| SEM-01 | Integer division | **No** | — | N/A (no division) |
| SEM-02 | `QUALIFY` / dedup ordering | **No** | — | N/A (no `QUALIFY`/`ROW_NUMBER`) |
| SEM-03 | `CHAR(n)` padding & comparison | **SME** | Not corrected — target `WRK_FLT_SCHED_LINKS` DDL not supplied; cannot confirm CHAR vs VARCHAR. Flagged `TODO(SME)`. | SME |
| SEM-04 | Timestamp / timezone | **SME** | Not corrected — `TO_TIMESTAMP(...,'DDMONYYHH24MI')` yields `TIMESTAMP_NTZ` by default; target cols are `*_GMT_FLT_TM`. Also `CURRENT_DATE` is used as an alias (FNX-14). Flagged `TODO(SME)`. | SME |
| SEM-05 | SET-table dedup | **No (not in play)** | `INSERT OVERWRITE` truncates-then-inserts; dedup is not in play. Target DDL still unknown → flagged for awareness only. | Yes (overwrite semantics) |
| SEM-06 | Implicit cast / NULL in comparison | **SME** | Not corrected — `FIELD6 \|\| FIELD7` (and `FIELD14 \|\| FIELD15`) have no NULL guard; Snowflake `\|\|` returns NULL if any operand is NULL, unlike the guarded suffix fields. Also implicit string→timestamp cast in `TO_TIMESTAMP` with no `TRY_` guard. Flagged `TODO(SME)`. | SME |
| SEM-07 | `NULL` ordering | **No** | — | N/A (no `ORDER BY`) |
| SEM-08 | Empty string vs NULL | **SME** | Not corrected — `IFF(... IS NULL,' ',...)` substitutes a single space `' '` for NULL, not `''` or `NULL`. Confirm `' '` vs `''` vs `NULL` intent for `IN/OUT_FLT_SFX_CD`. Flagged `TODO(SME)`. | SME |
| SEM-09 | Aggregate of empty set | **No** | — | N/A (no aggregates) |
| SEM-10 | Join direction | **No** | — | N/A (no joins) |
| OBS-01 | Locale-dependent date mask (proposed) | **SME** | Not corrected — `'DDMONYYHH24MI'` mask is locale-dependent (`MON` case-sensitive). Confirm CSV date format and session locale. Flagged `TODO(SME)`. | SME |

**Summary:** 0 risks corrected (none forced by a rule); 6 distinct risks flagged
`SME` (SEM-03, SEM-04, SEM-06, SEM-08, OBS-01, plus SEM-05 awareness-only). All
others not present.

---

## 4. Divergences from the original

**There are no intentional divergences.** This is a 0-mechanical-fix run: the
fixed SQL is byte-for-byte identical to the input SQL except for the added
`FIX LOG` header and inline `-- TODO(SME)` comments. No SQL logic line was
changed.

The only "divergences" are **additions**, not changes:

- A `FIX LOG` header block documenting the 0-fix verdict and the SNZ KEEP items.
- Inline `-- TODO(SME)` comments at the 6 semantic-risk locations, each citing
  the relevant rule ID and source line.

Because no Teradata ground truth was supplied, **no semantic equivalence can be
proven** — only flagged. Every inference is a `TODO(SME)` for a human to
confirm against the (missing) Teradata original or the target DDL.

---

## 5. Open SME questions

Each is phrased as a decision for a human reviewer. With no Teradata ground
truth, none can be auto-resolved.

1. **SEM-04 / FNX-14 — `CURRENT_DATE` alias.** Is `CURRENT_DATE` in the header
   extract (line 27) intended as a literal header label (the value of `FIELD2`
   on the `'LINKS'` row), or was the Teradata original calling the
   `CURRENT_DATE` function? If the function was intended, the alias must be
   renamed and the expression replaced with `CURRENT_DATE()`.
2. **SEM-04 — Timestamp timezone.** `TO_TIMESTAMP(...,'DDMONYYHH24MI')` returns
   `TIMESTAMP_NTZ`. The target columns are named `IN_ARR_GMT_FLT_TM` and
   `OUT_DEP_GMT_FLT_TM` (GMT-named). Should these be `TIMESTAMP_NTZ` (no
   timezone, treat as GMT literal) or `TIMESTAMP_TZ`/`TIMESTAMP_LTZ`? Confirm
   the target column type and the session `TIMEZONE`.
3. **SEM-06 — NULL guard on timestamp concatenation.** `FIELD6 || FIELD7` and
   `FIELD14 || FIELD15` have no NULL guard, unlike the suffix fields which use
   `IFF(... IS NULL,' ',...)`. If `FIELD7` or `FIELD15` can be NULL, the whole
   timestamp becomes NULL (or `TO_TIMESTAMP` errors). Should a
   `COALESCE`/`IFF` guard be added, or does the source data contract guarantee
   non-NULL date+time fields?
4. **SEM-06 / DTX-10 — Implicit cast robustness.** `TO_TIMESTAMP` (not
   `TRY_TO_TIMESTAMP`) will error the whole row on a malformed CSV cell. Is
   `TRY_TO_TIMESTAMP` with a NULL-on-error fallback desired, or does the CSV
   contract guarantee well-formed date+time strings?
5. **SEM-08 — Suffix NULL handling.** `IFF(SUBSTR(FIELDx,1,1) IS NULL,' ',...)`
   substitutes a single space `' '` for NULL. Did the Teradata original use
   `''` (empty string), `' '` (space), or `NULL`? And is the target column
   `CHAR(1)` (blank-padded) or `VARCHAR`? This affects downstream
   equality/anti-join semantics.
6. **SEM-03 / DTX-03 — Target DDL / CHAR padding.** The `CREATE TABLE` DDL for
   `STAGING.WRK_FLT_SCHED_LINKS` is not supplied. Are the `*_CD`, `*_TYP`,
   `*_TXT` columns `CHAR(n)` (Teradata blank-pads, ignores trailing spaces in
   `=`) or `VARCHAR` (Snowflake does not pad)? This affects downstream
   joins/anti-joins against this target.
7. **SEM-05 — Target table type (awareness only).** `INSERT OVERWRITE` makes
   SET-vs-MULTISET dedup irrelevant for this statement, but is
   `WRK_FLT_SCHED_LINKS` a SET or MULTISET table? (For awareness of other
   writers into the same target, not a blocking gate for this script.)
8. **OBS-01 — Locale-dependent date mask.** The `'DDMONYYHH24MI'` mask uses
   `MON` (case-sensitive, locale-dependent month abbreviation). What is the
   CSV's actual date format and what is the session locale? If the CSV uses
   uppercase month abbreviations (`01JAN26`) the mask is correct; if lowercase
   or mixed, it will fail.
9. **SNZ-01 — Template tag values.** The 14 `<% ctx.env.* %>` placeholders (7
   distinct env vars) are resolved by the orchestrator. Confirm the
   orchestrator supplies all 7: `S_vwxxxx_MapLinksRecordsToOracle_InputFile_DIR`,
   `LANDING_STAGE`, `S_vwxxxx_MapLinksRecordsToOracle_InputFileName`,
   `S_vwxxxx_MapLinksRecordsToOracle_OutputFileName`,
   `S_vwxxxx_MapLinksRecordsToOracle_OutputFileName_DIR`. (Not a SQL question,
   but a deployment-completeness check.)

---

## 6. Inline anchors

```anchors
PUT file://<% ctx.env.S_vwxxxx_MapLinksRecordsToOracle_InputFile_DIR %> :: SNZ-02 KEEP — SnowSQL PUT command, preserved verbatim. Uploads input CSV to stage; AUTO_COMPRESS=FALSE keeps it parseable.
COPY INTO STAGING.Sq_Src_LinksCSVFile :: Loads staged CSV into the 28-col VARCHAR transient buffer; ERROR_ON_COLUMN_COUNT_MISMATCH=FALSE tolerates short header/trailer rows.
REMOVE @<% ctx.env.LANDING_STAGE %>/<% ctx.env.S_vwxxxx_MapLinksRecordsToOracle_InputFileName %> :: SNZ-04 KEEP — stage cleanup of input file after load.
FIELD2 AS CURRENT_DATE :: SEM-04/FNX-14 — CURRENT_DATE used as an alias, shadowing the Snowflake keyword. Confirm label vs function intent (TODO SME).
COPY INTO @<% ctx.env.LANDING_STAGE %>/<% ctx.env.S_vwxxxx_MapLinksRecordsToOracle_OutputFileName %> :: Header-record extract: the 'LINKS' row projected to a single CSV (SINGLE=TRUE) on the stage.
GET @<% ctx.env.LANDING_STAGE %>/<% ctx.env.S_vwxxxx_MapLinksRecordsToOracle_OutputFileName %> :: SNZ-03 KEEP — SnowSQL GET, downloads header CSV to client filesystem.
INSERT OVERWRITE INTO STAGING.WRK_FLT_SCHED_LINKS :: SEM-05 — Overwrite truncates-then-inserts; SET/MULTISET dedup not in play. Target DDL not supplied (TODO SME).
IFF(SUBSTR(FIELD5,1,1) IS NULL,' ',SUBSTR(FIELD5,1,1)) :: SEM-08 — substitutes a single space ' ' for NULL, not '' or NULL. Confirm suffix NULL intent (TODO SME).
TO_TIMESTAMP(FIELD6 || FIELD7,'DDMONYYHH24MI') :: SEM-04/SEM-06/OBS-01 — yields TIMESTAMP_NTZ (GMT-named target); no NULL guard on ||; locale-dependent MON mask. All TODO SME.
IFF(SUBSTR(FIELD13,1,1) IS NULL,' ',SUBSTR(FIELD13,1,1)) :: SEM-08 — same single-space-for-NULL guard on OUT_FLT_SFX_CD. Confirm intent (TODO SME).
TO_TIMESTAMP(FIELD14 || FIELD15,'DDMONYYHH24MI') :: SEM-04/SEM-06/OBS-01 — second timestamp, same three risks as the inbound arrival timestamp. All TODO SME.
WHERE FIELD1 NOT IN ('LINKS','TRAILER') :: Detail-row filter: drops the header ('LINKS') and trailer ('TRAILER') rows, keeping only link detail rows.
```