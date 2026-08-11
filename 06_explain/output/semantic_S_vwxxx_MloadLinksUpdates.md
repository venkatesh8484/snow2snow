# Stage 6 — Semantic explanation: `S_vwxxx_MloadLinksUpdates.snowsql`

**Fixed SQL:** `03_fix/output/S_vwxxx_MloadLinksUpdates_fixed.snowsql`
**Analysis:** `01_analyze/output/analysis_S_vwxxx_MloadLinksUpdates.md`
**Validation:** `04_validate/output/validation_S_vwxxx_MloadLinksUpdates.md` (PASS — 1 stmt, no residual Teradata, 13 TODO(SME))
**Teradata ground truth:** **none supplied** (no
`00_input/S_vwxxx_MloadLinksUpdates.teradata.sql`). Every semantic inference
below is flagged `TODO(SME)`; intent is inferred from `02_rules/` and the
Snowflake input alone. No reviewer guidance file exists.
**Input type:** `.snowsql` — SNZ-* rules apply; **1** SNZ-01 template tag is
preserved verbatim.

---

## 1. Purpose

`S_vwxxx_MloadLinksUpdates.snowsql` is a single `UPDATE … FROM (subquery)`
statement that **expires** link rows in `BASE.FLT_FOLDERLINKS` (the UPDATE
target, alias `tgt`). It reads "old" link records from the staging table
`STAGING.Rtr_DirectFlowOfLinksRecords` (subquery alias `src`), filtered to
rows whose `ACTION_CODE` is `'U'` (update) or `'B'` (both). For each such
record it sets `LINK_EXPIRY_DT` and `CURRENT_REC_IND` on the matching base
row. The `LINK_EXPIRY_DT` is computed with an `IFF`: if the old expiry is not
the sentinel `'20501231'`, keep it; otherwise replace it with the day before
an orchestrator-supplied current date (a `<% ctx.env.* %>` template tag). The
`CURRENT_REC_IND` is set to `'Y'` when `ACTION_CODE = 'U'`, else `'N'`. A
`NOT EXISTS` anti-join guard prevents the update from firing if a row with
the same key + new expiry/indicator already exists in
`BASE.FLIGHT_FOLDERLINKS` (a table whose name differs from the UPDATE
target — an open DEF-07 SME question). The grain of one updated row is one
link identity (7 keys).

---

## 2. Statement-by-statement walk-through

### 2.1 UPDATE target + SET list (lines 2–5)

```
UPDATE BASE.FLT_FOLDERLINKS tgt
SET
    LINK_EXPIRY_DT  = src.LINK_EXPIRY_DT,
    CURRENT_REC_IND = src.CURRENT_REC_IND
```

Only two columns are mutated: the expiry date and the current-record
indicator. Both come from the subquery `src`.

### 2.2 Subquery `src` projection (lines 8–20)

The subquery selects 9 columns from
`STAGING.Rtr_DirectFlowOfLinksRecords`, aliasing `OLD_*` staging columns to
the names the outer scope references:

- `OLD_LINK_STATION_CD AS LINK_STATION_CD`, …, `OLD_IN_FLIGHT_NO AS
  IN_FLIGHT_NO`, `OLD_IN_FLIGHT_SFX_CD AS IN_FLIGHT_SFX_CD`,
  `OLD_IN_DEP_FLIGHT_DT AS IN_DEP_FLIGHT_DT` (alias **renamed** by the
  DEF-07 fix from the drifted `IN_DEP_GMTFLIGHT_FLIGHT_DT`),
  `OLD_LINK_EFFECTIVE_DT AS LINK_EFFECTIVE_DT`.
- `IFF(TO_CHAR(OLD_LINK_EXPIRY_DT,'YYYYMMDD') <> '20501231',
   OLD_LINK_EXPIRY_DT,
   DATEADD(DAY,-1,TO_DATE('<% ctx.env.S_vw6122_…_Current_date %>','DDMONYY')))
   AS LINK_EXPIRY_DT` — the expiry logic. The `IFF` NULL path (SEM-08) and the
  `'DDMONYY'` locale-dependent mask (SEM-06) are flagged.
- `IFF(ACTION_CODE = 'U','Y','N') AS CURRENT_REC_IND` — the indicator logic.
  The NULL `ACTION_CODE` path (SEM-08) is flagged.

### 2.3 Subquery WHERE (line 21)

`WHERE ACTION_CODE IN ('U','B')` — keeps only update/both records.

### 2.4 Outer WHERE — join + NOT EXISTS guard (lines 26–41)

```
WHERE tgt.LINK_STATION_CD       = src.LINK_STATION_CD
  AND tgt.IN_ORIGN_STATION_CD   = src.IN_ORIGN_STATION_CD
  AND tgt.IN_ALN_CD             = src.IN_ALN_CD
  AND tgt.IN_FLIGHT_NO          = src.IN_FLIGHT_NO
  AND tgt.IN_FLIGHT_SFX_CD      = src.IN_FLIGHT_SFX_CD
  AND tgt.IN_DEP_FLIGHT_DT      = src.IN_DEP_FLIGHT_DT
  AND tgt.LINK_EFFECTIVE_DT     = src.LINK_EFFECTIVE_DT
  AND NOT EXISTS (
        SELECT 1
        FROM BASE.FLIGHT_FOLDERLINKS x
        WHERE x.<7 keys> = tgt.<7 keys>
          AND x.LINK_EXPIRY_DT  = src.LINK_EXPIRY_DT
          AND x.CURRENT_REC_IND = src.CURRENT_REC_IND
  )
```

The outer `WHERE` joins `tgt` to `src` on 7 keys. The `NOT EXISTS` guard
anti-joins `BASE.FLIGHT_FOLDERLINKS x` against `tgt` on the same 7 keys plus
the two new values being set — i.e. it suppresses the update if a row with
the same key + new expiry/indicator already exists (preventing a duplicate
insert elsewhere from being overwritten). The guard table name
`BASE.FLIGHT_FOLDERLINKS` differs from the UPDATE target
`BASE.FLT_FOLDERLINKS` — an open DEF-07 SME question.

---

## 3. Semantic checks table

| SEM ID | Risk | Present? | Corrected how? | Equivalent to Teradata? |
|---|---|---|---|---|
| **DEF-07** (alias) | Subquery alias mismatch | **Yes** | Alias renamed `IN_DEP_GMTFLIGHT_FLIGHT_DT` → `IN_DEP_FLIGHT_DT` (line 13). The outer `WHERE` (line 31) and `NOT EXISTS` guard (line 38) already use `IN_DEP_FLIGHT_DT` consistently, so the alias was the outlier (find/replace drift: doubled `FLIGHT`, `GMT` infix). Minimal diff = 1 token. | **Yes** — the outer scope already used `IN_DEP_FLIGHT_DT`; the alias was the outlier, so the rename is unambiguous and does not require ground truth. `TODO(SME)` notes the rename for grain confirmation. |
| **DEF-07** (table name) | `BASE.FLT_FOLDERLINKS` vs `BASE.FLIGHT_FOLDERLINKS` | **Yes** | **Not renamed.** Per DEF-07 no-guess policy, do not rename either table without ground truth. Flagged `TODO(SME)`: are these the same table? | **SME** — if they are different tables, the guard protects a *different* table than the UPDATE target. |
| **SEM-03** | `CHAR(n)` padding on join + anti-join keys | **Yes (suspected)** | **Not rewritten.** The outer `WHERE` (7 keys) and `NOT EXISTS` (9 keys) equate columns; several are plausibly `CHAR(n)` (`LINK_STATION_CD`, `IN_ORIGN_STATION_CD`, `IN_ALN_CD`, `IN_FLIGHT_SFX_CD`, `CURRENT_REC_IND`). Teradata blank-pads, Snowflake does not → padding differences silently change which rows match. No DDL supplied. Flagged `TODO(SME)`. | **SME** — if any of the 9 keys are `CHAR(n)`, wrap both sides in `RTRIM()`. |
| **SEM-06** | `'DDMONYY'` locale-dependent mask | **Yes** | **Not rewritten.** `TO_DATE('<% … %>','DDMONYY')` — the `MON` token is locale-dependent. With no Teradata ground truth, the orchestrator-supplied date format and session locale cannot be verified. Flagged `TODO(SME)`. | **SME** — confirm the orchestrator date matches `'DDMONYY'` and the session locale matches the source. |
| **SEM-08** | `IFF` NULL/empty-string handling | **Yes (suspected)** | **Not rewritten.** (1) `IFF(TO_CHAR(OLD_LINK_EXPIRY_DT,'YYYYMMDD') <> '20501231', …)`: if `OLD_LINK_EXPIRY_DT` is NULL, `TO_CHAR(NULL)` is NULL, `NULL <> '20501231'` is NULL (not TRUE), so the `IFF` falls to the false-branch (`DATEADD(...)`). (2) `IFF(ACTION_CODE = 'U','Y','N')`: if `ACTION_CODE` is NULL, `= 'U'` is NULL → false-branch `'N'`. Flagged `TODO(SME)` on both `IFF` NULL paths. | **SME** — confirm both NULL paths match Teradata intent. |
| **SEM-10** | Join-key grain/direction | **Yes (suspected)** | **Not rewritten.** The outer `WHERE` joins `tgt`↔`src` on 7 keys. Without DDL/ground truth, cannot prove the `OLD_*` staging columns are the same grain as the `tgt` BASE columns. The `OLD_IN_DEP_FLIGHT_DT` alias drift (DEF-07) is itself a grain-direction signal. Flagged `TODO(SME)`. | **SME** — confirm the 7 `OLD_*` staging columns map 1:1 to the `tgt` BASE columns by grain. |
| SEM-01 | Integer division | No | n/a | n/a |
| SEM-02 | `QUALIFY`/dedup ties | No | n/a | n/a |
| SEM-04 | Timestamp / timezone | No | `TO_DATE(...)` returns `DATE`; no `TIMESTAMP`/`TIMESTAMP_LTZ`/`CURRENT_TIMESTAMP`. | n/a |
| SEM-05 | SET-table dedup | No | Single `UPDATE`, not an `INSERT`/`UNION` into one target. The `NOT EXISTS` is an explicit anti-join guard, not implicit SET-table dedup. | n/a |
| SEM-07 | `NULL` ordering | No | n/a | n/a |
| SEM-09 | Aggregate of empty set | No | n/a | n/a |

---

## 4. Divergences from the original

| # | Divergence | Justification |
|---|---|---|
| 1 | Subquery alias `IN_DEP_GMTFLIGHT_FLIGHT_DT` → `IN_DEP_FLIGHT_DT` (line 13). | DEF-07. The outer `WHERE` (line 31) and `NOT EXISTS` guard (line 38) already use `IN_DEP_FLIGHT_DT` consistently; the alias was the outlier (find/replace drift). The rename is unambiguous and does not require ground truth. `TODO(SME)` notes the rename for grain confirmation. |

No other SQL logic was changed. The SNZ-01 template tag is preserved
verbatim; the `IFF`/`DATEADD`/`TO_DATE`/`TO_CHAR` expressions, the 7-key join,
and the `NOT EXISTS` guard are all preserved exactly. The five SME-classified
risks (DEF-07 table name, SEM-03, SEM-06, SEM-08, SEM-10) were **not**
mechanically rewritten — they carry forward as `TODO(SME)` markers pending
DDL / Teradata ground truth.

---

## 5. Open SME questions

1. **DEF-07 (table name).** Is `BASE.FLIGHT_FOLDERLINKS` (line 33, the `NOT
   EXISTS` guard table) the same table as the UPDATE target
   `BASE.FLT_FOLDERLINKS` (line 2)? If not, is the guard intended to protect
   a *different* table? Do not rename either without ground truth.
2. **DEF-07 (alias rename confirmation).** Confirm the renamed alias
   `IN_DEP_FLIGHT_DT` matches the staging column `OLD_IN_DEP_FLIGHT_DT` by
   grain (the rename aligns the alias with the outer scope; the grain itself
   is still unprovable without DDL).
3. **SEM-03 — `CHAR(n)` padding.** Are any of the 9 join/anti-join keys
   `CHAR(n)` (`LINK_STATION_CD`, `IN_ORIGN_STATION_CD`, `IN_ALN_CD`,
   `IN_FLIGHT_SFX_CD`, `CURRENT_REC_IND`, …)? If so, wrap both sides of each
   predicate in `RTRIM()`.
4. **SEM-06 — `'DDMONYY'` locale mask.** Does the orchestrator-supplied
   `<% ctx.env.S_vw6122_…_Current_date %>` value match the `'DDMONYY'` format,
   and does the session locale match the source? `MON` is locale-dependent.
5. **SEM-08 — `IFF` NULL paths.** (a) If `OLD_LINK_EXPIRY_DT` is NULL, the
   first `IFF` falls to the `DATEADD(...)` false-branch — is that the intended
   behaviour? (b) If `ACTION_CODE` is NULL, the second `IFF` returns `'N'` —
   is that the intended behaviour?
6. **SEM-10 — join-key grain.** Do the 7 `OLD_*` staging columns map 1:1 to
   the `tgt` BASE columns by grain? Confirm against Teradata ground truth.

---

## 6. Inline anchors

```anchors
UPDATE BASE.FLT_FOLDERLINKS tgt :: DEF-07 (table name): UPDATE target is FLT_FOLDERLINKS; the NOT EXISTS guard uses FLIGHT_FOLDERLINKS — confirm same table
OLD_IN_DEP_FLIGHT_DT AS IN_DEP_FLIGHT_DT :: DEF-07 (alias): renamed from IN_DEP_GMTFLIGHT_FLIGHT_DT to align with outer WHERE (line 31) and NOT EXISTS guard (line 38)
IFF( :: SEM-08: IFF NULL path — TO_CHAR(NULL) or NULL ACTION_CODE falls to the false-branch; confirm intent
TO_CHAR(OLD_LINK_EXPIRY_DT,'YYYYMMDD') <> '20501231' :: SEM-08: if OLD_LINK_EXPIRY_DT is NULL, NULL <> '20501231' is NULL -> IFF false-branch (DATEADD)
DATEADD(DAY,-1,TO_DATE('<% ctx.env.S_vw6122_CompareLinksRecordsWithTeradata_Current_date %>','DDMONYY')) :: SNZ-01 template tag preserved verbatim; SEM-06: 'DDMONYY' locale-dependent MON mask
IFF(ACTION_CODE = 'U','Y','N') AS CURRENT_REC_IND :: SEM-08: NULL ACTION_CODE -> '= U' is NULL -> IFF false-branch 'N'; confirm intent
WHERE ACTION_CODE IN ('U','B') :: subquery filter keeps update/both records only
tgt.LINK_STATION_CD       = src.LINK_STATION_CD :: SEM-03/SEM-10: first of 7 join keys; CHAR(n) padding + grain confirmation needed
FROM BASE.FLIGHT_FOLDERLINKS x :: DEF-07 (table name): guard table name differs from UPDATE target — confirm same table
```