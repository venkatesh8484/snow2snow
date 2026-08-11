# Stage 6 — Semantic explanation: `S_vwxxx_MloadLinksInserts.snowsql`

**Fixed SQL:** `03_fix/output/S_vwxxx_MloadLinksInserts_fixed.snowsql`
**Analysis:** `01_analyze/output/analysis_S_vwxxx_MloadLinksInserts.md`
**Validation:** `04_validate/output/validation_S_vwxxx_MloadLinksUpdates.md` (control PASS expected — semantic-only unit)
**Teradata ground truth:** **none supplied** (no
`00_input/S_vwxxx_MloadLinksInserts.teradata.sql`). Every semantic inference
below is flagged `TODO(SME)`; intent is inferred from `02_rules/` and the
Snowflake input alone. No reviewer guidance file exists.
**Input type:** `.snowsql` — SNZ-* rules apply; the SNZ inventory is **empty**
(no `<% %>` tags, no `PUT`/`GET`, no stage DML), but the `.snowsql` extension is
retained on the fixed output so the validator's masking path applies
consistently.

---

## 1. Purpose

`S_vwxxx_MloadLinksInserts.snowsql` is a **full-row anti-dup INSERT** into
`BASE.FLT_FOLDER_LINKS` (a 33-column flight-folder-links table). It reads
pre-cast "new" link rows from the staging view `STAGING.ExpFinalyseInserts`
(alias `S`), filters out rows with NULL leg-sequence numbers, and inserts a
staging row **only if no identical row already exists** in the base target.
The dedup is implemented as a `NOT EXISTS` subquery that equates **all 33
columns** of the staging row against the base target (`T.col = S.NEW_col` for
every column). This is the Snowflake-native equivalent of Teradata
`SET TABLE` "drop rows already present on INSERT" semantics: the `NOT EXISTS`
anti-join suppresses any staging row that would duplicate an existing base
row. The grain of one output row is one complete 33-column link record.

---

## 2. Statement-by-statement walk-through

### 2.1 INSERT target list (33 columns, lines 2–34)

The 33-column target list covers the full `BASE.FLT_FOLDER_LINKS` row:
`LINK_STATION_CD`, inbound leg fields (`IN_*`), outbound leg fields
(`OUT_*`), aircraft/owner fields, duration fields, and the SCD-2 bookends
(`LINK_EFFECTIVE_DT`, `LINK_EXPIRY_DT`, `CURRENT_REC_IND`).

### 2.2 SELECT projection (33 expressions, lines 37–69)

Each SELECT expression is a `NEW_*` column from `STAGING.ExpFinalyseInserts`
— the staging view has already pre-cast the raw values. Twelve of the 33
aliases carry a `_SMALLINT` or `_DATE` suffix
(e.g. `NEW_IN_FLT_NO_SMALLINT`, `NEW_IN_DEP_FLTDT_DATE`,
`NEW_IN_ARR_FLTTM_DATE`, `NEW_MIDNIGHT_QTY_SMALLINT`). The suffix describes
the **staging cast**, not the target column type — a type mismatch between
the staging value and the base column is the SEM-06/DTX-10 risk.

### 2.3 WHERE — NULL guard (lines 71–72)

```
WHERE S.IN_FLT_LEG_SEQ_NO IS NOT NULL
  AND S.OUT_FLT_LEG_SEQ_NO IS NOT NULL
```

Filters out staging rows with NULL leg-sequence numbers before the anti-join.
NULLs would never match in the `=` predicates anyway, so this primarily
prevents inserting rows with NULL keys. The remaining 31 columns are **not**
NULL-guarded — standard anti-join NULL semantics apply (a NULL staging value
makes its predicate NULL → row treated as non-matching → inserted). Flagged
for SME confirmation that no other key column should be NULL-guarded.

### 2.4 NOT EXISTS full-row anti-join (lines 73–108)

```
AND NOT EXISTS (
    SELECT 1
    FROM BASE.FLT_FOLDER_LINKS T
    WHERE T.LINK_STATION_CD = S.NEW_LINK_STATION_CD
      AND T.IN_ORIGN_STATION_CD = S.NEW_IN_ORIGN_STATION_CD
      ... (all 33 columns equated) ...
      AND T.CURRENT_REC_IND = S.NEW_CURRENT_REC_IND
)
```

This is the core dedup mechanism. It equates every one of the 33 columns
between the staging row `S` and the base target `T`. A staging row is
inserted only if **no** base row matches on all 33 columns. This emulates
Teradata SET-table "drop rows already present" semantics in Snowflake-native
form. Whether `BASE.FLT_FOLDER_LINKS` is itself a SET table (in which case
the `NOT EXISTS` is belt-and-suspenders) or a MULTISET table (in which case
the `NOT EXISTS` is the **only** dedup and is load-bearing) is an open SME
question (SEM-05).

---

## 3. Semantic checks table

| SEM ID | Risk | Present? | Corrected how? | Equivalent to Teradata? |
|---|---|---|---|---|
| **SEM-03** | `CHAR(n)` padding in the full-row anti-join | **Yes** | **Not rewritten.** All 33 `T.col = S.NEW_col` predicates equate columns; several are plausibly `CHAR(n)` by naming convention (`*_CD`, `*_TYP`, `*_TXT`, `*_IND`). Teradata blank-pads `CHAR(n)` and ignores trailing spaces in `=`; Snowflake does **not** pad, so padding differences silently change which rows the anti-join suppresses — inserting duplicates or suppressing valid rows. Requires DDL for both `BASE.FLT_FOLDER_LINKS` and `STAGING.ExpFinalyseInserts` to identify `CHAR(n)` columns; if any, wrap both sides of each such predicate in `RTRIM`/`TRIM`. Flagged `TODO(SME)`. | **SME** — padding drift can silently change anti-join suppression. |
| **SEM-06 / DTX-10** | Type-suffixed staging aliases vs unknown BASE types | **Yes** | **Not rewritten.** 12 SELECT aliases carry `_SMALLINT`/`_DATE` suffixes (e.g. `NEW_IN_FLT_NO_SMALLINT`, `NEW_*_FLTDT_DATE`, `NEW_*_FLTTM_DATE`, `NEW_*_SMALLINT`). The suffix describes the staging cast, **not** the target column type. The `NOT EXISTS` predicates compare these against `BASE.FLT_FOLDER_LINKS` columns whose types are unknown (no DDL). A mismatch (e.g. `DATE` vs `TIMESTAMP`, `VARCHAR` vs `NUMBER`, `TIME` vs `TIMESTAMP`) could silently change suppression or raise a strict-cast error. Note `IN_ARR_FLTTM`/`OUT_DEP_FLTTM` are time slots whose staging alias is `_DATE` — a `TIME`/`TIMESTAMP` vs `DATE` mismatch is plausible. Flagged `TODO(SME)`. | **SME** — requires DDL for both sides; do not assume the suffix is authoritative. |
| **SEM-04** | Timezone on `_TTM` time columns | **Possible** | **Not rewritten.** `IN_ARR_FLTTM` and `OUT_DEP_FLTTM` (time slots) are loaded from `_DATE`-suffixed staging values. If the staging cast produced a `TIMESTAMP`/`TIMESTAMP_TZ` and the target is `TIME` or `TIMESTAMP_NTZ`, a session-`TIMEZONE` shift could move values. No explicit `TIMESTAMP_LTZ`/`TIMESTAMP_TZ` function is used, so the risk is indirect and depends on the staging view's cast. Flagged `TODO(SME)`. | **SME** — confirm staging cast + target type for the `_TTM` columns; pin session `TIMEZONE` or use `TIMESTAMP_NTZ` explicitly if needed. |
| **SEM-05** | SET vs MULTISET on `BASE.FLT_FOLDER_LINKS` | **Considered** | **Not rewritten.** This is a single `INSERT` (not multiple INSERTs / `UNION` into one target), so the strict SEM-05 trigger does not fire. However, the `NOT EXISTS` equates all 33 columns — it is an explicit full-row dedup that emulates Teradata SET-table "drop rows already present" semantics. The open question is whether `BASE.FLT_FOLDER_LINKS` is itself a SET table: if SET, the `NOT EXISTS` is belt-and-suspenders (harmless); if MULTISET, the `NOT EXISTS` is the **only** dedup mechanism (load-bearing). No `CREATE TABLE` DDL supplied → cannot decide. Flagged `TODO(SME)`. | **SME** — "Is `BASE.FLT_FOLDER_LINKS` a SET table?" Either way the SQL is self-consistent; do not rewrite. |
| SEM-01 | Integer division | No | n/a | n/a |
| SEM-02 | `QUALIFY`/dedup ties | No | n/a | n/a |
| SEM-07 | `NULL` ordering | No | n/a | n/a |
| SEM-08 | Empty string vs NULL | No | n/a (no `NULLIF(x,'')`) | n/a |
| SEM-09 | Aggregate of empty set | No | n/a | n/a |
| SEM-10 | Lookup join direction | No | The `NOT EXISTS` is an anti-join, not a directional lookup join. | n/a |

---

## 4. Divergences from the original

| # | Divergence | Justification |
|---|---|---|
| — | (none) | The file is parse-clean Snowflake with no residual Teradata constructs and no defects (33 = 33 columns, no DEF-*). No mechanical (AUTO/FIX) changes were applied. All four findings are semantic and were **not** rewritten — they carry forward as `TODO(SME)` markers pending DDL for `BASE.FLT_FOLDER_LINKS` and `STAGING.ExpFinalyseInserts`. |

Column order, the 33-column INSERT/SELECT alignment, the NULL guard, and the
full-row `NOT EXISTS` anti-join are all preserved exactly. The `.snowsql`
extension is retained (SNZ inventory empty, but the extension keeps the
validator's masking path consistent).

---

## 5. Open SME questions

1. **SEM-05 — SET vs MULTISET.** Is `BASE.FLT_FOLDER_LINKS` a SET table? If
   SET, the `NOT EXISTS` is belt-and-suspenders (harmless); if MULTISET, it is
   the only dedup mechanism (load-bearing). Supply the target `CREATE TABLE`
   DDL to confirm.
2. **SEM-03 — `CHAR(n)` padding.** Which of the 33 columns are `CHAR(n)` (by
   naming convention: `*_CD`, `*_TYP`, `*_TXT`, `*_IND`)? If any, wrap both
   sides of each such `NOT EXISTS` predicate in `RTRIM`/`TRIM` to preserve
   Teradata blank-padding semantics. Requires DDL for both
   `BASE.FLT_FOLDER_LINKS` and `STAGING.ExpFinalyseInserts`.
3. **SEM-06/DTX-10 — type compatibility.** What are the BASE column types for
   the 12 `_SMALLINT`/`_DATE`-suffixed staging aliases? In particular, confirm
   the `IN_ARR_FLTTM`/`OUT_DEP_FLTTM` time slots are type-compatible with their
   `_DATE`-suffixed staging values. Do not assume the suffix is authoritative —
   it describes the staging cast, not the target column.
4. **SEM-04 — timezone on `_TTM` columns.** What cast does the staging view
   `STAGING.ExpFinalyseInserts` apply to `IN_ARR_FLTTM`/`OUT_DEP_FLTTM`? If it
   produces a `TIMESTAMP_TZ`, pin the session `TIMEZONE` or use
   `TIMESTAMP_NTZ` explicitly.
5. **NULL-guard scope.** Only `IN_FLT_LEG_SEQ_NO` and `OUT_FLT_LEG_SEQ_NO`
   are NULL-guarded upstream. Should any other key column be NULL-guarded to
   prevent inserting rows with NULL keys (which standard anti-join NULL
   semantics would treat as non-matching and insert)?

---

## 6. Inline anchors

```anchors
INSERT INTO BASE.FLT_FOLDER_LINKS :: SEM-05: SET vs MULTISET on this target unknown (no DDL); the NOT EXISTS below is the dedup mechanism — confirm whether SET-table dedup also applies
NEW_IN_FLT_NO_SMALLINT :: SEM-06/DTX-10: _SMALLINT suffix = staging cast, not target type; confirm IN_FLT_NO type compatibility vs BASE column
NEW_IN_DEP_FLTDT_DATE :: SEM-06/DTX-10: _DATE suffix = staging cast; confirm IN_DEP_FLTDT type compatibility
NEW_IN_ARR_FLTTM_DATE :: SEM-06/DTX-10 + SEM-04: _DATE suffix on a _TTM (time) slot; confirm staging cast + target type (TIME vs TIMESTAMP vs DATE) and timezone handling
NEW_OUT_FLT_NO_SMALLINT :: SEM-06/DTX-10: _SMALLINT suffix = staging cast; confirm OUT_FLT_NO type compatibility
NEW_OUT_DEP_FLTTM_DATE :: SEM-06/DTX-10 + SEM-04: _DATE suffix on a _TTM (time) slot; confirm staging cast + target type and timezone handling
NEW_MIDNIGHT_QTY_SMALLINT :: SEM-06/DTX-10: _SMALLINT suffix = staging cast; confirm MIDNIGHT_QTY type compatibility
WHERE S.IN_FLT_LEG_SEQ_NO IS NOT NULL :: NULL guard: only leg-sequence columns are NULL-guarded; confirm no other key column needs guarding
AND NOT EXISTS ( :: SEM-03: full-row anti-join equates all 33 columns; CHAR(n) padding drift (Teradata pads, Snowflake does not) can silently change suppression
T.LINK_STATION_CD = S.NEW_LINK_STATION_CD :: SEM-03: first of 33 full-row anti-join predicates; CHAR(n) padding drift risk across all 33
```