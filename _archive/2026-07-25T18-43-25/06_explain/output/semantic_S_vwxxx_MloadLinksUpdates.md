# Stage 6 — Semantic explanation: `S_vwxxx_MloadLinksUpdates`

**Fixed SQL:** `03_fix/output/S_vwxxx_MloadLinksUpdates_fixed.snowsql`
**Teradata ground truth:** Not supplied (no `S_vwxxx_MloadLinksUpdates.teradata.sql` in `00_input/`). Intent is inferred from the buggy Snowflake input and `02_rules/`; every inference is flagged `TODO(SME)`.
**Statement type:** Single `UPDATE … FROM (subquery) src WHERE … AND NOT EXISTS (…)`.

---

## 1. Purpose

This statement performs the **"close-out the old link row"** half of a
multi-load (MLOAD) link-records update. It reads staged link records from
`STAGING.Rtr_DirectFlowOfLinksRecords` whose `ACTION_CODE` is `'U'` (update) or
`'B'` (both), computes a new `LINK_EXPIRY_DT` and `CURRENT_REC_IND` for each,
and applies those two columns to matching rows in the target table
`BASE.FLT_FOLDERLINKS`. The new expiry is the old expiry **unless** the old
expiry was the sentinel `2050-12-31` (an "open-ended" link), in which case the
new expiry becomes **run-date − 1** — i.e. the old open-ended row is closed out
the day before the current run. The `CURRENT_REC_IND` is set to `'Y'` for
`'U'` actions and `'N'` otherwise (the `'B'` branch). A `NOT EXISTS` guard
against `BASE.FLIGHT_FOLDERLINKS` prevents the update from touching a target
row whose new expiry/indicator pair already exists in that sibling table,
avoiding a duplicate future-state row. The grain of one updated row is one
folder-link identified by the seven join keys (station, origin station, airline
code, flight number, suffix, departure date, effective date).

---

## 2. Clause-by-clause walk-through

### 2.1 `UPDATE BASE.FLT_FOLDERLINKS tgt SET …`

The target is `BASE.FLT_FOLDERLINKS` (note the `FLT_` prefix). Only **two**
columns are overwritten: `LINK_EXPIRY_DT` and `CURRENT_REC_IND`. All other
columns on the matched target row are left untouched — this is a partial
update, not a full-row replace.

### 2.2 `FROM ( SELECT … FROM STAGING.Rtr_DirectFlowOfLinksRecords WHERE ACTION_CODE IN ('U','B') ) src`

The driving subquery (`src`) reads the staging table and keeps only rows marked
for update (`'U'`) or both-insert-and-update (`'B'`). It projects the seven
join keys (renaming the `OLD_*` staging columns to the target column names) and
two computed columns:

- **`LINK_EXPIRY_DT`** — `IFF(TO_CHAR(OLD_LINK_EXPIRY_DT,'YYYYMMDD') <> '20501231', OLD_LINK_EXPIRY_DT, DATEADD(DAY,-1,TO_DATE('<% ctx.env.…Current_date %>','DDMONYY')))`.
  If the old expiry is **not** the `20501231` sentinel, it is carried forward
  unchanged. If it **is** the sentinel, the new expiry is **run-date − 1 day**,
  closing out the open-ended row. The run date is injected by the orchestrator
  via the `<% ctx.env.…Current_date %>` template tag (SNZ-01, preserved
  verbatim) and parsed with the `'DDMONYY'` mask.
- **`CURRENT_REC_IND`** — `IFF(ACTION_CODE = 'U','Y','N')`. Update actions mark
  the row as the current record (`'Y'`); the `'B'` branch marks it
  non-current (`'N'`).

### 2.3 `WHERE tgt.<key> = src.<key> …` (seven-key equi-join)

The outer `WHERE` joins the target to the source on all seven link-identity
keys: `LINK_STATION_CD`, `IN_ORIGN_STATION_CD`, `IN_ALN_CD`, `IN_FLIGHT_NO`,
`IN_FLIGHT_SFX_CD`, `IN_DEP_FLIGHT_DT`, `LINK_EFFECTIVE_DT`. Only a target row
that matches a staged row on **all seven** keys is eligible for update.

> **What the buggy input would have done:** the subquery aliased
> `OLD_IN_DEP_FLIGHT_DT` as `IN_DEP_GMTFLIGHT_FLIGHT_DT`, but the outer `WHERE`
> referenced `src.IN_DEP_FLIGHT_DT`. Snowflake would have raised
> `invalid identifier 'SRC.IN_DEP_FLIGHT_DT'` and the statement would **not
> have run at all**. The fix (DEF-07) restored the alias to
> `IN_DEP_FLIGHT_DT` so the join key resolves.

### 2.4 `AND NOT EXISTS ( SELECT 1 FROM BASE.FLIGHT_FOLDERLINKS x WHERE … )`

The anti-join guard. For each candidate (target row, source row) pair, it
checks that **no** row in `BASE.FLIGHT_FOLDERLINKS` (note the `FLIGHT_`
prefix — a **different table** from the `FLT_` update target) already carries
the **new** `LINK_EXPIRY_DT` and `CURRENT_REC_IND` values on the same
seven-key identity. If such a row exists, the update is skipped for that
candidate, preventing a duplicate future-state row. The guard compares
`x.LINK_EXPIRY_DT = src.LINK_EXPIRY_DT` and `x.CURRENT_REC_IND =
src.CURRENT_REC_IND` — i.e. it uses the **computed** (new) values, not the
old ones.

---

## 3. Semantic checks table

| SEM-* | Risk | Present? | Corrected how? | Equivalent to Teradata? |
|---|---|---|---|---|
| **SEM-01** | Integer division | No | N/A — no division in the script. | N/A |
| **SEM-02** | `QUALIFY` / dedup ordering | No | N/A — no `QUALIFY`/`ROW_NUMBER`. | N/A |
| **SEM-03** | `CHAR(n)` padding & comparison | **Possibly** — the seven join keys (`LINK_STATION_CD`, `IN_ORIGN_STATION_CD`, `IN_ALN_CD`, `IN_FLIGHT_NO`, `IN_FLIGHT_SFX_CD`, `IN_DEP_FLIGHT_DT`, `LINK_EFFECTIVE_DT`) may be `CHAR(n)` in either `BASE.FLT_FOLDERLINKS`, `STAGING.Rtr_DirectFlowOfLinksRecords`, or `BASE.FLIGHT_FOLDERLINKS`. | **Not corrected** — no DDL was supplied, so `RTRIM` was not added. Flagged `TODO(SME)`: if any key is `CHAR(n)`, wrap both sides of each join predicate in `RTRIM` to preserve Teradata's blank-padding semantics. | **SME** — depends on confirmed column types. |
| **SEM-04** | Timestamp / timezone | No | N/A — all date columns are `DATE`, not `TIMESTAMP`. | N/A |
| **SEM-05** | SET-table dedup | No | N/A — this is an `UPDATE`, not an `INSERT`; SET-table dedup only applies to INSERT targets. | N/A |
| **SEM-06** | Implicit cast / NULL in comparison | **Yes** — `TO_DATE('<% ctx.env.…Current_date %>','DDMONYY')` parses the injected run-date string. If the orchestrator emits a format other than `DDMONYY` (e.g. `YYYY-MM-DD`), `TO_DATE` silently returns `NULL`, and `DATEADD(DAY,-1,NULL)` = `NULL`, so every sentinel row would get a `NULL` expiry. | **Not corrected** — the mask is kept as-is because the injected value is orchestrator-controlled (SNZ-01). Flagged `TODO(SME)`: confirm the orchestrator emits `Current_date` in `DDMONYY` form (e.g. `24JUL26`). | **Yes-with-assumption** — equivalent *if* the injected format matches `'DDMONYY'`; otherwise silently wrong. |
| **SEM-07** | `NULL` ordering | No | N/A — no `ORDER BY` feeding `QUALIFY`/`TOP`. | N/A |
| **SEM-08** | Empty string vs NULL | No | N/A — no `''` comparisons. | N/A |
| **SEM-09** | Aggregate of empty set | No | N/A — no aggregates. | N/A |
| **SEM-10** | Join direction / alias honesty | **Yes (low)** — the `NOT EXISTS` guard references `BASE.FLIGHT_FOLDERLINKS` (a **different table** from the `BASE.FLT_FOLDERLINKS` update target). The alias `x` is honest; all predicates reference `tgt.*`/`src.*`/`x.*` correctly. | **Not corrected** — no direction ambiguity. Flagged for SME confirmation that the anti-join should target a *different* table from the update target. | **Yes-with-assumption** — equivalent *if* `FLIGHT_FOLDERLINKS` is genuinely the intended guard table (not a typo for `FLT_FOLDERLINKS`). |

---

## 4. Divergences from the original

| # | Divergence | Justification | Rule |
|---|---|---|---|
| 1 | Subquery alias `IN_DEP_GMTFLIGHT_FLIGHT_DT` → `IN_DEP_FLIGHT_DT` (line 13 of the fixed file). | The buggy alias did not match the outer join key `src.IN_DEP_FLIGHT_DT` (line 29) nor the `NOT EXISTS` guard `x.IN_DEP_FLIGHT_DT = tgt.IN_DEP_FLIGHT_DT` (line 39), causing a Snowflake `invalid identifier` error. The minimal-diff fix aligns the alias to the target join key rather than rewriting the outer `WHERE`. This is the **only** change to the statement body. | **DEF-07** |

No other divergences. Column order, join-key order, `CASE`/`IFF` branch order,
and the `NOT EXISTS` guard structure are all preserved exactly. The single
`<% ctx.env.…Current_date %>` template tag (SNZ-01) is preserved verbatim.

---

## 5. Open SME questions

1. **DEF-07 — intended column name.** Is the intended join-key column name
   `IN_DEP_FLIGHT_DT` (the fix applied) or `IN_DEP_GMTFLIGHT_FLIGHT_DT` (the
   buggy alias)? The fix assumes the target table `BASE.FLT_FOLDERLINKS` has a
   column named `IN_DEP_FLIGHT_DT` and that the staging column
   `OLD_IN_DEP_FLIGHT_DT` maps to it. Confirm against the DDL.

2. **SEM-06 / DTX-09 — injected date format.** Does the orchestrator emit
   `ctx.env.S_vw6122_CompareLinksRecordsWithTeradata_Current_date` in `DDMONYY`
   form (e.g. `24JUL26`)? If it emits a different format (e.g. `YYYY-MM-DD`,
   `MM/DD/YYYY`), `TO_DATE(...,'DDMONYY')` silently returns `NULL` and every
   sentinel (`20501231`) row gets a `NULL` `LINK_EXPIRY_DT`. Confirm the
   injected format or adjust the mask.

3. **SEM-03 — CHAR(n) join keys.** Are any of the seven join-key columns
   (`LINK_STATION_CD`, `IN_ORIGN_STATION_CD`, `IN_ALN_CD`, `IN_FLIGHT_NO`,
   `IN_FLIGHT_SFX_CD`, `IN_DEP_FLIGHT_DT`, `LINK_EFFECTIVE_DT`) declared
   `CHAR(n)` (fixed-length) in `BASE.FLT_FOLDERLINKS`,
   `STAGING.Rtr_DirectFlowOfLinksRecords`, or `BASE.FLIGHT_FOLDERLINKS`? If so,
   wrap both sides of each join predicate in `RTRIM` to preserve Teradata's
   blank-padding comparison semantics.

4. **SEM-10 — guard table identity.** The `NOT EXISTS` guard references
   `BASE.FLIGHT_FOLDERLINKS` while the update target is `BASE.FLT_FOLDERLINKS`
   — two different tables (`FLIGHT_` vs `FLT_`). Is this intentional (a
   flight-level folder-links table used as the dedup guard), or is
   `FLIGHT_FOLDERLINKS` a typo for `FLT_FOLDERLINKS`? Confirm the intended
   guard table.

---

## 6. Inline anchors

```anchors
MATCH UPDATE BASE.FLT_FOLDERLINKS tgt :: Target is BASE.FLT_FOLDERLINKS (FLT_ prefix); only LINK_EXPIRY_DT and CURRENT_REC_IND are overwritten.
MATCH WHERE ACTION_CODE IN ('U','B') :: Source keeps update ('U') and both ('B') actions only; 'B' rows become non-current (CURRENT_REC_IND='N').
MATCH TO_CHAR(OLD_LINK_EXPIRY_DT,'YYYYMMDD') <> '20501231' :: Sentinel 2050-12-31 means "open-ended link"; non-sentinel expiries are carried forward unchanged.
MATCH DATEADD(DAY,-1,TO_DATE('<% ctx.env.S_vw6122_CompareLinksRecordsWithTeradata_Current_date %>','DDMONYY')) :: Open-ended rows are closed out at run-date − 1. SEM-06/DTX-09: injected Current_date must be in DDMONYY form or TO_DATE returns NULL silently. SNZ-01 template tag preserved verbatim.
MATCH IFF(ACTION_CODE = 'U','Y','N') AS CURRENT_REC_IND :: 'U' actions mark the row current ('Y'); 'B' actions mark it non-current ('N').
MATCH OLD_IN_DEP_FLIGHT_DT AS IN_DEP_FLIGHT_DT :: DEF-07 fix: alias restored from IN_DEP_GMTFLIGHT_FLIGHT_DT to IN_DEP_FLIGHT_DT so the outer join key and NOT EXISTS guard resolve. TODO(SME) to confirm intended column name.
MATCH WHERE tgt.LINK_STATION_CD       = src.LINK_STATION_CD :: Seven-key equi-join on link identity. SEM-03: if any key is CHAR(n), wrap in RTRIM to preserve Teradata blank-padding.
MATCH AND NOT EXISTS :: Anti-join guard against BASE.FLIGHT_FOLDERLINKS (FLIGHT_ prefix — a different table from the FLT_ update target). Skips the update when the new expiry/indicator pair already exists there. SEM-10: confirm FLIGHT_ vs FLT_ is intentional.
MATCH x.LINK_EXPIRY_DT    = src.LINK_EXPIRY_DT :: Guard compares the NEW (computed) expiry/indicator, not the old values — prevents a duplicate future-state row.
```