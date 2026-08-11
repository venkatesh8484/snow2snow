# Stage 5 — Fix Report: `S_vwxxx_MloadLinksUpdates.snowsql`

**Unit:** `S_vwxxx_MloadLinksUpdates`
**Input:** `00_input/S_vwxxx_MloadLinksUpdates.snowsql`
**Fixed file:** `03_fix/output/S_vwxxx_MloadLinksUpdates_fixed.snowsql`
**Analysis:** `01_analyze/output/analysis_S_vwxxx_MloadLinksUpdates.md`
**Validation:** `04_validate/output/validation_S_vwxxx_MloadLinksUpdates.md`
**Teradata ground truth:** Not supplied (no `S_vwxxx_MloadLinksUpdates.teradata.sql` in `00_input/`).
**File type:** `.snowsql` — SnowSQL client layer rules (`SNZ-*`) apply.
**Date:** 2026-07-24

---

## 1. Summary

`S_vwxxx_MloadLinksUpdates.snowsql` is a single `UPDATE … FROM (subquery) src
WHERE …` statement with a `NOT EXISTS` anti-join guard against
`BASE.FLIGHT_FOLDERLINKS`. It closes out the old row in
`BASE.FLT_FOLDERLINKS` by setting `LINK_EXPIRY_DT` and `CURRENT_REC_IND` from a
staging subquery filtered to `ACTION_CODE IN ('U','B')`.

The unit contained **one blocking defect (DEF-07)**: the converter renamed the
subquery alias `OLD_IN_DEP_FLIGHT_DT` to `IN_DEP_GMTFLIGHT_FLIGHT_DT` (a
find/replace drift) but did not update the outer `WHERE` reference
`src.IN_DEP_FLIGHT_DT` (line 29) or the `NOT EXISTS` guard
`x.IN_DEP_FLIGHT_DT = tgt.IN_DEP_FLIGHT_DT` (line 39). At runtime Snowflake
would raise `invalid identifier 'SRC.IN_DEP_FLIGHT_DT'` because no column of
that name exists in the `src` subquery.

The fix restores the alias to `IN_DEP_FLIGHT_DT` (minimal diff: align the
alias to the target join key rather than rewriting the outer `WHERE` and
`NOT EXISTS`). One `<% %>` template tag (SNZ-01) is preserved verbatim. Six
`TODO(SME)` markers remain for deferred semantic confirmations.

**Mechanical verdict: PASS** (1 statement parsed, no residual Teradata).
**Control PASS — expected and not a re-fix trigger** (DEF-07 is a runtime
resolution error, not a parse error; see §5).

---

## 2. Rules applied

### 2.1 Syntax / function / type fixes

| Rule | Line | Change | Notes |
|------|------|--------|-------|
| — | — | None | No `SFX-*`, `FNX-*`, or `DTX-*` mechanical fixes were required. The script is syntactically valid Snowflake once the DEF-07 alias is corrected. `IFF`, `DATEADD(DAY,-1,…)`, `TO_CHAR(...,'YYYYMMDD')` are all valid Snowflake forms. |

### 2.2 Defect repairs

| Rule | Line(s) | Defect | Repair |
|------|---------|--------|--------|
| **DEF-07** | 13 (alias), 29 (outer WHERE), 39 (NOT EXISTS) | Subquery alias `OLD_IN_DEP_FLIGHT_DT AS IN_DEP_GMTFLIGHT_FLIGHT_DT` did not match the outer join key `src.IN_DEP_FLIGHT_DT` (line 29) or the `NOT EXISTS` guard `x.IN_DEP_FLIGHT_DT = tgt.IN_DEP_FLIGHT_DT` (line 39). At runtime: `invalid identifier 'SRC.IN_DEP_FLIGHT_DT'`. | Restored the alias to `IN_DEP_FLIGHT_DT`. Minimal diff — only the alias name changed; the outer `WHERE` and `NOT EXISTS` references were left intact. All three sites now use the same identifier. Inline `TODO(SME)` confirms the intended column name for human review. |

### 2.3 Semantic handling

| Rule | Line(s) | Risk | Action |
|------|---------|------|--------|
| **SEM-06 / DTX-09** | 18 | `TO_DATE('<% ctx.env.…Current_date %>','DDMONYY')` — the format mask `'DDMONYY'` must match the injected string. If the orchestrator emits a different format (e.g. `YYYY-MM-DD`), `TO_DATE` returns NULL silently, producing wrong `LINK_EXPIRY_DT` values. | Kept as-is; `TODO(SME)` to confirm the orchestrator emits `Current_date` in `DDMONYY` form (e.g. `24JUL26`). |
| **SEM-03** | 24–30, 34–40 | Join keys (`LINK_STATION_CD`, `IN_ORIGN_STATION_CD`, `IN_ALN_CD`, `IN_FLIGHT_NO`, `IN_FLIGHT_SFX_CD`, `IN_DEP_FLIGHT_DT`, `LINK_EFFECTIVE_DT`) may be `CHAR(n)`. Teradata blank-pads and ignores trailing spaces in `=`; Snowflake does not pad, so padding differences silently change which rows the UPDATE matches and which the `NOT EXISTS` suppresses. | Kept as-is; `TODO(SME)` to verify column types and wrap joins in `RTRIM` if any key column is `CHAR(n)`. |

No `SEM-01/02/04/05/07/08/09/10` risks were present (no division, no
`QUALIFY`, no timestamps/TZ, not an INSERT, no `ORDER BY`, no `''`
comparisons, no aggregates, NOT EXISTS direction unambiguous).

### 2.4 SnowSQL client layer (SNZ-*)

| Rule | Line | Construct | Action |
|------|------|-----------|--------|
| **SNZ-01** | 18 | `<% ctx.env.S_vw6122_CompareLinksRecordsWithTeradata_Current_date %>` template tag | **Preserved verbatim.** Resolved by the orchestrator at run time. Masked to `__TPL_n__` during validation, restored in the file. |

No `PUT` (SNZ-02), `GET` (SNZ-03), `REMOVE`/`LIST` (SNZ-04) commands present.

---

## 3. Defects repaired

| # | Rule | Line(s) | Defect | Repair | Verified by |
|---|------|---------|--------|--------|-------------|
| 1 | DEF-07 | 13, 29, 39 | Subquery alias `IN_DEP_GMTFLIGHT_FLIGHT_DT` ≠ outer reference `src.IN_DEP_FLIGHT_DT` → runtime `invalid identifier` | Alias restored to `IN_DEP_FLIGHT_DT` | Manual spot-check (validation §1) |

**Total defects repaired: 1.** No other DEF-* defects (no duplicate columns,
no typo keywords, no unbalanced parens, no malformed functions, no
INSERT/SELECT count mismatch — N/A, this is an UPDATE).

---

## 4. Open `TODO(SME)` items

| # | Rule | Line | Question |
|---|------|------|----------|
| 1 | DEF-07 | 13 | Confirm the intended column name is `IN_DEP_FLIGHT_DT` (not `IN_DEP_GMTFLIGHT_FLIGHT_DT`). The fix aligns the alias to the target join key; the converter's `IN_DEP_GMTFLIGHT_FLIGHT_DT` appears to be a find/replace drift. |
| 2 | SEM-06 / DTX-09 | 18 | Confirm the orchestrator emits `Current_date` in `DDMONYY` form (e.g. `24JUL26`). If it emits a different format, `TO_DATE` returns NULL silently. |
| 3 | SEM-03 | 24–30 | Verify the 7 UPDATE join-key column types in `BASE.FLT_FOLDERLINKS` and `STAGING.Rtr_DirectFlowOfLinksRecords`. If any are `CHAR(n)`, wrap joins in `RTRIM`. |
| 4 | SEM-03 | 34–40 | Verify the 7 `NOT EXISTS` anti-join key column types in `BASE.FLIGHT_FOLDERLINKS`. Same `RTRIM` guidance. |
| 5 | (analysis §7) | 2, 33 | Confirm `BASE.FLT_FOLDERLINKS` (UPDATE target) and `BASE.FLIGHT_FOLDERLINKS` (NOT EXISTS table) are intentionally two different tables (`FLT_` vs `FLIGHT_` prefix). |
| 6 | (general) | — | No Teradata ground truth was supplied. Every semantic inference above is flagged `TODO(SME)`. If a `.teradata.sql` is later provided, re-run Stage 1 and diff against it. |

**Total open `TODO(SME)`: 6.**

---

## 5. Validation result

**Source:** `04_validate/output/validation_S_vwxxx_MloadLinksUpdates.md`

### 5.1 Fixed file

```
INFO  .snowsql input — masked template tags / PUT-GET commands for validation (preserved as-is in the file).
PASS  snowflake connection: probe returned 1
PASS  parse: 1 statement(s) parsed as snowflake using snowflake
INFO  snowflake EXPLAIN stmt 1: skipped — referenced object not loaded.
INFO  1 statement(s) skipped for lack of loaded objects — not counted as failures.
PASS  no residual Teradata constructs
INFO  TODO(SME) markers outstanding: 6
------------------------------------------------------------
RESULT: PASS
```

| Check | Result |
|-------|--------|
| Parse | PASS (1 statement) |
| Residual Teradata scan | PASS (none) |
| EXPLAIN | SKIPPED — `STAGING.RTR_DIRECTFLOWOFLINKSRECORDS` not loaded (environment gap, not a defect) |
| DEF-07 alias fix applied | PASS (manual spot-check) |
| JOIN keys intact (7 keys, original order) | PASS |
| NOT EXISTS anti-join intact (9 predicates) | PASS |
| SET / IFF branches intact | PASS |
| No dropped columns (UPDATE — N/A for count check) | PASS |
| Template tags preserved (SNZ-01) | PASS |

### 5.2 Buggy input control

```
RESULT: PASS
```

**Control PASS — expected and NOT a re-fix trigger.**

The control PASSES because the DEF-07 defect is a **runtime resolution error**,
not a parse error. sqlglot parses the buggy statement fine — the alias
`IN_DEP_GMTFLIGHT_FLIGHT_DT` is syntactically valid; it simply does not match
the name used in the outer `WHERE`. The EXPLAIN is skipped because the
referenced object is not loaded, so the backend cannot perform identifier
resolution. The mechanical validator cannot detect this defect without loaded
objects. Per the orchestrator rules: *"Do not re-fix a semantic-only unit just
because the control PASSes."* The manual spot-check (validation §1) is the
decisive evidence that the fix is correct.

---

## 6. Minimal-diff confirmation

| Aspect | Buggy input | Fixed file | Changed? |
|--------|-------------|------------|----------|
| Subquery alias (line 13) | `OLD_IN_DEP_FLIGHT_DT AS IN_DEP_GMTFLIGHT_FLIGHT_DT` | `OLD_IN_DEP_FLIGHT_DT AS IN_DEP_FLIGHT_DT` | **Yes** (DEF-07) |
| Outer WHERE (line 29) | `src.IN_DEP_FLIGHT_DT` | `src.IN_DEP_FLIGHT_DT` | No |
| NOT EXISTS guard (line 39) | `x.IN_DEP_FLIGHT_DT = tgt.IN_DEP_FLIGHT_DT` | `x.IN_DEP_FLIGHT_DT = tgt.IN_DEP_FLIGHT_DT` | No |
| SET clause | `LINK_EXPIRY_DT = src.LINK_EXPIRY_DT`, `CURRENT_REC_IND = src.CURRENT_REC_IND` | unchanged | No |
| IFF branches | `IFF(TO_CHAR(...) <> '20501231', …, DATEADD(DAY,-1,…))`, `IFF(ACTION_CODE='U','Y','N')` | unchanged | No |
| Join keys (7) | original order | original order | No |
| NOT EXISTS predicates (9) | original order | original order | No |
| Template tag (SNZ-01) | `<% ctx.env.…Current_date %>` | preserved verbatim | No |
| File extension | `.snowsql` | `.snowsql` | No |

**Lines changed: 1** (the alias on line 13). All other content is preserved.
Six `TODO(SME)` markers and a `FIX LOG` header block were added (comments only).

---

## 7. Sign-off checklist

A reviewer can sign off from this document alone. Confirm:

- [x] **DEF-07 repaired:** alias `IN_DEP_FLIGHT_DT` now matches outer WHERE and NOT EXISTS.
- [x] **No residual Teradata constructs** in the fixed file.
- [x] **Column order, JOIN keys, CASE/IFF branch order preserved** exactly.
- [x] **Template tag (SNZ-01) preserved verbatim.**
- [x] **`.snowsql` extension retained** on the fixed output.
- [x] **Validation PASS** (parse + residual-Teradata; EXPLAIN skipped — environment gap).
- [x] **Control PASS explained** (runtime resolution error, not parse error).
- [ ] **SME confirms** `IN_DEP_FLIGHT_DT` is the intended column name (TODO #1).
- [ ] **SME confirms** the injected `Current_date` format is `DDMONYY` (TODO #2).
- [ ] **SME confirms** join-key column types (CHAR vs VARCHAR) and whether `RTRIM` is needed (TODOs #3–4).
- [ ] **SME confirms** `FLT_FOLDERLINKS` vs `FLIGHT_FOLDERLINKS` are intentionally distinct tables (TODO #5).

**Mechanical sign-off: PASS.** Semantic sign-off pending SME confirmation of
the 6 open `TODO(SME)` items.

---

## 8. Stage-6 semantic reference

The clause-by-clause semantic account is Stage 6's job. When generated, see
`06_explain/output/semantic_S_vwxxx_MloadLinksUpdates.md`. This report
references it; it does not duplicate it.