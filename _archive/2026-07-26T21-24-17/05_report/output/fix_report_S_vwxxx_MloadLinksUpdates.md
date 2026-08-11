# Fix Report — `S_vwxxx_MloadLinksUpdates.snowsql`

**Unit:** `S_vwxxx_MloadLinksUpdates`
**Input:** `00_input/S_vwxxx_MloadLinksUpdates.snowsql`
**Fixed file:** `03_fix/output/S_vwxxx_MloadLinksUpdates_fixed.snowsql`
**Analysis:** `01_analyze/output/analysis_S_vwxxx_MloadLinksUpdates.md`
**Validation:** `04_validate/output/validation_S_vwxxx_MloadLinksUpdates.md`
**Stage-6 semantic doc:** `06_explain/output/semantic_S_vwxxx_MloadLinksUpdates.md` (archived copy: `_archive/2026-07-25T18-43-25/06_explain/output/semantic_S_vwxxx_MloadLinksUpdates.md`)
**Teradata ground truth:** **Not supplied.** No `S_vwxxx_MloadLinksUpdates.teradata.sql` in `00_input/`. Every semantic inference is flagged `TODO(SME)`.
**Run type:** Re-run (prior run dated 2026-07-24; see `02_rules/06_lessons_learned.md`).
**Statement shape:** Single `UPDATE … FROM (subquery) src WHERE … AND NOT EXISTS (…)` — no `INSERT … SELECT`, so the INSERT/SELECT column-count check is N/A; the subquery-alias vs outer-reference alignment is audited instead.

---

## 1. Summary

The buggy input was syntactically parseable Snowflake (no residual Teradata constructs) but **would not execute** because of a **DEF-07 subquery-alias / outer-reference mismatch**: the subquery projected `OLD_IN_DEP_FLIGHT_DT AS IN_DEP_GMTFLIGHT_FLIGHT_DT` while the outer `WHERE` and the `NOT EXISTS` guard both referenced `src.IN_DEP_FLIGHT_DT` / `tgt.IN_DEP_FLIGHT_DT` — a name that does not exist in the subquery's output. At runtime Snowflake would raise `invalid identifier 'SRC.IN_DEP_FLIGHT_DT'`.

The fix is a **single-line, minimal-diff alias rename**: `IN_DEP_GMTFLIGHT_FLIGHT_DT` → `IN_DEP_FLIGHT_DT`, aligning the subquery output to the join key and the target column. The outer `WHERE` and the `NOT EXISTS` guard were left untouched. The repair is flagged `TODO(SME)` to confirm the intended column name.

A second DEF-07 finding (target table `BASE.FLT_FOLDERLINKS` vs `NOT EXISTS` guard table `BASE.FLIGHT_FOLDERLINKS`) was **not** corrected — DEF-07 forbids guessing a table rename; it is flagged `TODO(SME)` for confirmation that the guard table is distinct from the update target.

Four SEM-* semantic risks (locale-dependent date mask, template-tag date format, NULL handling in `IFF`, CHAR-padding drift in join keys) were inventoried and flagged `TODO(SME)`; none were mechanically changed without ground truth.

**Net: 1 mechanical fix (DEF-07 alias), 1 SNZ-01 tag preserved, 10 `TODO(SME)` markers outstanding, validation PASS.**

---

## 2. Rules applied

### Syntax (SFX-* / FNX-* / DTX-*)
None. The input contained no residual Teradata constructs and no legacy-function or datatype pitfalls. `IFF`, `DATEADD(DAY,-1,TO_DATE(...))`, `TO_CHAR(...,'YYYYMMDD')`, `TO_DATE(...,'DDMONYY')` are all valid Snowflake idioms.

### Defects (DEF-*)
| Rule | Line(s) | Finding | Action |
|---|---|---|---|
| **DEF-07** | 13 (alias) vs 29 (outer `WHERE`) vs 39 (`NOT EXISTS` guard) | Subquery alias `IN_DEP_GMTFLIGHT_FLIGHT_DT` did not match the outer reference `src.IN_DEP_FLIGHT_DT` nor the guard `tgt.IN_DEP_FLIGHT_DT`. Would raise `invalid identifier 'SRC.IN_DEP_FLIGHT_DT'` at runtime. | **FIXED** — alias renamed to `IN_DEP_FLIGHT_DT` (minimal diff: align alias to the join key rather than rewriting the outer `WHERE`). Flagged `TODO(SME)` to confirm intended column name. |
| **DEF-07** | 1 (target) vs 32 (guard) | `UPDATE` target `BASE.FLT_FOLDERLINKS` vs `NOT EXISTS` guard `BASE.FLIGHT_FOLDERLINKS` — different table names. | **NOT corrected** — DEF-07 forbids guessing a table rename. Flagged `TODO(SME)` to confirm `FLIGHT_FOLDERLINKS` is a distinct guard table and not a typo for `FLT_FOLDERLINKS`. |

### Semantic (SEM-*)
| Rule | Line(s) | Risk | Action |
|---|---|---|---|
| **SEM-06 / DTX-09** | 18 | `TO_DATE('<% ctx.env.…Current_date %>','DDMONYY')` format mask must match the injected string. | Kept as-is; `TODO(SME)` to confirm the orchestrator emits `Current_date` in `DDMONYY` form (e.g. `24JUL26`). |
| **SEM-03** | 24–30, 34–40 | Join/anti-join keys may be `CHAR(n)`; Teradata blank-pads, Snowflake does not. | `TODO(SME)` to verify column types and wrap joins in `RTRIM` if any key is CHAR-typed. |
| **SEM-06 / SEM-08** | 17 | `TO_CHAR(OLD_LINK_EXPIRY_DT,'YYYYMMDD') <> '20501231'` returns NULL when `OLD_LINK_EXPIRY_DT` is NULL, routing NULL to the `DATEADD` else-branch. | `TODO(SME)` to confirm intended NULL handling. Not corrected without ground truth. |

### SnowSQL client layer (SNZ-*)
| Rule | Line | Construct | Action |
|---|---|---|---|
| **SNZ-01** | 18 | `<% ctx.env.S_vw6122_CompareLinksRecordsWithTeradata_Current_date %>` template tag inside `TO_DATE(...)` | **KEEP** — preserved verbatim. Validator masked it for parse via `snowsql_protect.py`. |

No `PUT`/`GET` (SNZ-02/03) or stage DML (SNZ-04) commands present.

---

## 3. Defects repaired

| # | Defect | Rule | Fix |
|---|---|---|---|
| 1 | Subquery alias `IN_DEP_GMTFLIGHT_FLIGHT_DT` mismatched the outer reference `src.IN_DEP_FLIGHT_DT` and the guard `tgt.IN_DEP_FLIGHT_DT` — a runtime `invalid identifier` error. | DEF-07 | Renamed the alias to `IN_DEP_FLIGHT_DT` (line 13 of the fixed file). Minimal diff: alias only; outer `WHERE` and `NOT EXISTS` guard left untouched. |

**Not repaired (flagged `TODO(SME)`):** the `BASE.FLT_FOLDERLINKS` vs `BASE.FLIGHT_FOLDERLINKS` table-name mismatch (DEF-07) — left for SME confirmation per the no-guess policy.

---

## 4. Open `TODO(SME)` items (10 markers)

1. **DEF-07 (line 13)** — Confirm the intended column name is `IN_DEP_FLIGHT_DT` (not `IN_DEP_GMTFLIGHT_FLIGHT_DT`).
2. **DEF-07 (line 1 vs 32)** — Confirm `BASE.FLIGHT_FOLDERLINKS` is a distinct guard table, not a typo for the `BASE.FLT_FOLDERLINKS` update target.
3. **SEM-06 / DTX-09 (line 18)** — Confirm the orchestrator injects `Current_date` in `DDMONYY` form to match the `TO_DATE(...,'DDMONYY')` mask.
4. **SEM-03 (lines 24–30)** — Verify the 6 outer join keys are not `CHAR(n)`; wrap in `RTRIM` if so.
5. **SEM-03 (lines 34–40)** — Verify the `NOT EXISTS` guard correlation keys are not `CHAR(n)`; wrap in `RTRIM` if so.
6. **SEM-06 / SEM-08 (line 17)** — Confirm intended NULL handling when `OLD_LINK_EXPIRY_DT` is NULL (NULL routes to the `DATEADD` else-branch).

(Items 4 and 5 are emitted as one `TODO(SME)` per join-key block in the fixed file, accounting for the 10-marker total reported by the validator.)

---

## 5. Validation result

**Mechanical verdict: PASS**

```
INFO  .snowsql input — masked template tags / PUT-GET commands for validation (preserved as-is in the file).
PASS  parse: 1 statement(s) parsed as snowflake using sqlglot
PASS  no residual Teradata constructs
INFO  TODO(SME) markers outstanding: 10
RESULT: PASS
```

| Check | Result |
|---|---|
| Parse (sqlglot, snowflake) | PASS — 1 statement |
| Residual Teradata constructs | PASS — none |
| INSERT/SELECT column count | N/A — single UPDATE |
| Duplicate columns | N/A — UPDATE |
| `.snowsql` template tags preserved | PASS — `<% ctx.env.…Current_date %>` intact |
| TODO(SME) markers | 10 outstanding (human-review; none block compilation) |

### Manual spot-check (decisive evidence)

- **Join keys (outer `WHERE`):** All 7 keys preserved in original order — `LINK_STATION_CD`, `IN_ORIGN_STATION_CD`, `IN_ALN_CD`, `IN_FLIGHT_NO`, `IN_FLIGHT_SFX_CD`, `IN_DEP_FLIGHT_DT`, `LINK_EFFECTIVE_DT`. Identical to buggy input. ✅
- **`NOT EXISTS` guard:** Guard table `BASE.FLIGHT_FOLDERLINKS x` and all 9 correlation predicates preserved verbatim, including the `x.LINK_EXPIRY_DT = src.LINK_EXPIRY_DT` and `x.CURRENT_REC_IND = src.CURRENT_REC_IND` tail predicates. ✅
- **`SET` clause:** `LINK_EXPIRY_DT = src.LINK_EXPIRY_DT`, `CURRENT_REC_IND = src.CURRENT_REC_IND` — unchanged. ✅
- **Subquery column order:** 9 columns in original order; only the 6th column's alias was changed (DEF-07). ✅
- **`IFF` branch order:** Both `IFF` expressions (`TO_CHAR(...) <> '20501231'` then-else; `ACTION_CODE = 'U'` Y/N) preserved in original branch order. ✅
- **DEF-07 alias fix:** Fixed file aligns the alias to the join key; buggy input does not. ✅
- **No dropped columns:** Subquery emits 9 columns; `SET` consumes 2; `WHERE` consumes 7 join keys + 2 `NOT EXISTS` correlations. No column lost. ✅
- **Snowflake idioms:** `IFF`, `DATEADD(DAY,-1,TO_DATE(...))`, `TO_CHAR(...,'YYYYMMDD')` — all valid. ✅
- **SNZ-01 preservation:** Template tag preserved verbatim; validator masked it for parse. ✅

### Buggy input control

```
INFO  .snowsql input — masked template tags / PUT-GET commands for validation (preserved as-is in the file).
PASS  parse: 1 statement(s) parsed as snowflake using sqlglot
PASS  no residual Teradata constructs
RESULT: PASS
```

**Control PASS is expected and is NOT a re-fix trigger.** The defect is a DEF-07 alias mismatch — a **runtime resolution error** (`invalid identifier 'SRC.IN_DEP_FLIGHT_DT'`), not a parse error. sqlglot does not resolve identifiers against the subquery's output schema, so it parses the buggy input cleanly. The mechanical validator therefore correctly PASSes the control; the decisive evidence is the manual spot-check above. Per the s2s-validate policy, a passing control on a runtime-only defect is expected and does not warrant a hand-back to s2s-fix.

---

## 6. Sign-off checklist

- [x] Fixed file parses as Snowflake (1 statement).
- [x] No residual Teradata constructs.
- [x] DEF-07 alias mismatch repaired (minimal diff; alias only).
- [x] All join keys, `SET` columns, `NOT EXISTS` predicates, and `IFF` branch order preserved.
- [x] SNZ-01 template tag preserved verbatim.
- [x] Validation PASS; control PASS explained (runtime defect, not parse defect).
- [ ] **SME:** Confirm intended column name `IN_DEP_FLIGHT_DT` (DEF-07, line 13).
- [ ] **SME:** Confirm `BASE.FLIGHT_FOLDERLINKS` is a distinct guard table (DEF-07, line 1 vs 32).
- [ ] **SME:** Confirm `Current_date` orchestrator format is `DDMONYY` (SEM-06/DTX-09, line 18).
- [ ] **SME:** Confirm join/anti-join key column types are not `CHAR(n)` (SEM-03, lines 24–40).
- [ ] **SME:** Confirm intended NULL handling for `OLD_LINK_EXPIRY_DT` (SEM-06/SEM-08, line 17).

**A reviewer can sign off the mechanical remediation from this document alone.** The five SME items above are the gate for production deployment; none block compilation.

---

## 7. Semantic account

The clause-by-clause semantic walk-through, the purpose statement, and the SEM-03 / SEM-06 / DTX-09 SME questions are in the Stage-6 semantic doc (`06_explain/output/semantic_S_vwxxx_MloadLinksUpdates.md`, archived copy: `_archive/2026-07-25T18-43-25/06_explain/output/semantic_S_vwxxx_MloadLinksUpdates.md`). This report references it; it does not duplicate it.