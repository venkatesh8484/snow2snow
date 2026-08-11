# Stage 5 — Fix Report: `S_vwxxx_MapLinksRecordsToOracle.snowsql`

**File:** `00_input/S_vwxxx_MapLinksRecordsToOracle.snowsql`
**File type:** `.snowsql` (SnowSQL client layer — `SNZ-*` rules apply)
**Teradata ground truth:** none supplied (no `00_input/<name>.teradata.sql`)
**Fixed file:** `03_fix/output/S_vwxxx_MapLinksRecordsToOracle_fixed.snowsql`
**Analysis:** `01_analyze/output/analysis_S_vwxxx_MapLinksRecordsToOracle.md`
**Validation:** `04_validate/output/validation_S_vwxxx_MapLinksRecordsToOracle.md`
**Stage-6 semantic doc:** `06_explain/output/semantic_S_vwxxx_MapLinksRecordsToOracle.md` (referenced, not duplicated)

---

## 1. Executive summary

This is a `.snowsql` ETL script (CREATE TABLE → PUT → COPY INTO → REMOVE →
COPY INTO @stage → GET → REMOVE → INSERT OVERWRITE). The file was
**parse-clean Snowflake SQL** — **0 mechanical fixes** were required. No
`SFX-*`, `FNX-*`, `DTX-*`, or `DEF-*` rules fired. The remediation consisted
entirely of:

- Preserving 16 SnowSQL client-layer constructs verbatim (14 template tags,
  1 `PUT`, 1 `GET`) per `SNZ-01/02/03`.
- Analysing 4 stage-DML statements (`COPY INTO`, `REMOVE`) normally per
  `SNZ-04` — all clean.
- Adding **10 inline `TODO(SME)` markers** at semantic-risk locations
  (SEM-04/05/06/08, OBS-01) and a top-of-file `FIX LOG` with `[KEEP]` lines
  for every SNZ construct.

**Validation: PASS.** Parse (6 statements), INSERT/SELECT column count
(28 = 28), no duplicate columns, no residual Teradata constructs. The 2
`REMOVE` EXPLAIN `FAIL` lines are an environment gap (the EXPLAIN backend
does not support stage-management commands), not a SQL defect — the control
fails identically.

**Sign-off gate:** the 10 open `TODO(SME)` items below. No mechanical defect
blocks sign-off.

---

## 2. Rules applied

### 2.1 Syntax fixes (SFX-* / FNX-* / DTX-*)

**None.** The SQL body uses only valid Snowflake functions (`SUBSTR`, `IFF`,
`TO_TIMESTAMP`, `IFF(... IS NULL, ...)`). No residual Teradata constructs
(`ZEROIFNULL`, `CONTAINS`, `MULTISET`, `MINUS`, `SEL`, `(+)`, BTEQ
dot-commands, `FORMAT`-casts, `PRIMARY INDEX`, `COLLECT STATS`) were found.

### 2.2 Defect repairs (DEF-*)

**None.** Parentheses balanced, function calls well-formed, no duplicate
columns, INSERT/SELECT counts match (28 = 28), no malformed `CAST`.

### 2.3 Semantic rules (SEM-*)

No semantic rule **forced** a change. Each risk was flagged inline as
`TODO(SME)` for human review (see §4):

| Rule | Line(s) | Risk | Action |
|---|---|---|---|
| SEM-04 | 80, 88 | `TO_TIMESTAMP(...,'DDMONYYHH24MI')` yields `TIMESTAMP_NTZ`; target cols are `*_GMT_FLT_TM` — confirm TZ intent | `TODO(SME)` ×2 |
| SEM-05 | 63 | Target `WRK_FLT_SCHED_LINKS` DDL not supplied; `INSERT OVERWRITE` makes SET/MULTISET dedup irrelevant — awareness only | `TODO(SME)` ×1 (low priority) |
| SEM-06 | 80, 88 | `FIELD6 \|\| FIELD7` (and `FIELD14 \|\| FIELD15`): Snowflake `\|\|` returns NULL if any operand is NULL; no NULL guard unlike suffix fields | `TODO(SME)` ×2 |
| SEM-08 | 78, 86 | `IFF(... IS NULL,' ',...)` substitutes a single space for NULL, not `''` or NULL — confirm intent for `IN/OUT_FLT_SFX_CD` | `TODO(SME)` ×2 |
| OBS-01 | 80, 88 | `'DDMONYYHH24MI'` mask is locale-dependent (`MON` case-sensitive) — confirm CSV date format and locale | `TODO(SME)` ×2 (proposed rule, pending review) |

### 2.4 SnowSQL client layer (SNZ-*)

| Rule | Construct | Count | Action |
|---|---|---|---|
| SNZ-01 | Template placeholders `<% ctx.env.X %>` | 14 (7 distinct env vars) | `[KEEP]` — preserved verbatim |
| SNZ-02 | `PUT file://… @… OVERWRITE=TRUE AUTO_COMPRESS=FALSE;` | 1 | `[KEEP]` — preserved verbatim, not converted to `COPY` |
| SNZ-03 | `GET @…/… file://… OVERWRITE=TRUE;` | 1 | `[KEEP]` — preserved verbatim |
| SNZ-04 | `COPY INTO` / `REMOVE` stage DML | 4 (2 `COPY INTO`, 2 `REMOVE`) | Analysed normally — SQL bodies clean; preserved as-is |

---

## 3. Defects repaired

**None.** No `DEF-*` defect was present in the input.

---

## 4. Open `TODO(SME)` items

10 outstanding markers — all semantic review items, none blocking:

| # | Marker | Line(s) | Question for SME |
|---|---|---|---|
| 1 | SEM-05 | 63 | Is `STAGING.WRK_FLT_SCHED_LINKS` SET or MULTISET? (Low priority — `INSERT OVERWRITE` truncates first, so dedup is not in play.) |
| 2 | SEM-08 | 78 | `IFF(SUBSTR(FIELD5,1,1) IS NULL,' ',…)` — should `IN_FLT_SFX_CD` receive `' '`, `''`, or NULL? |
| 3 | SEM-04 | 80 | `TO_TIMESTAMP(FIELD6 \|\| FIELD7,'DDMONYYHH24MI')` → `TIMESTAMP_NTZ`; target `IN_ARR_GMT_FLT_TM` is GMT-named — NTZ vs TZ/LTZ? |
| 4 | SEM-06 | 80 | `FIELD6 \|\| FIELD7` returns NULL if either is NULL — is a NULL guard needed (like the suffix fields)? |
| 5 | OBS-01 | 80 | `'DDMONYYHH24MI'` mask is locale-dependent — confirm CSV date format and locale. |
| 6 | SEM-08 | 86 | `IFF(SUBSTR(FIELD13,1,1) IS NULL,' ',…)` — should `OUT_FLT_SFX_CD` receive `' '`, `''`, or NULL? |
| 7 | SEM-04 | 88 | `TO_TIMESTAMP(FIELD14 \|\| FIELD15,'DDMONYYHH24MI')` → `TIMESTAMP_NTZ`; target `OUT_DEP_GMT_FLT_TM` is GMT-named — NTZ vs TZ/LTZ? |
| 8 | SEM-06 | 88 | `FIELD14 \|\| FIELD15` returns NULL if either is NULL — is a NULL guard needed? |
| 9 | OBS-01 | 88 | `'DDMONYYHH24MI'` mask locale — confirm (same as #5). |
| 10 | (header) | FIX LOG | Top-of-file `FIX LOG` documents all `[KEEP]` SNZ constructs and semantic risks; no SQL logic changed. |

---

## 5. Validation result

**Mechanical verdict: PASS**

| Check | Result | Evidence |
|---|---|---|
| Parse (sqlglot, snowflake dialect) | **PASS** | 6 statement(s) parsed as snowflake |
| INSERT/SELECT column count | **PASS** | stmt 6: 28 INSERT columns == 28 SELECT expressions |
| Duplicate INSERT columns | **PASS** | none |
| Residual Teradata constructs | **PASS** | none |
| `REMOVE` EXPLAIN (stmts 3, 5) | FAIL ×2 | **Environment gap** — EXPLAIN backend does not support stage-management commands (`REMOVE`/`PUT`/`GET`/`LIST`). Not a SQL defect. |
| Object-not-loaded INFO (stmts 2, 4, 6) | INFO ×3 | Staging table / named stage not materialised in the validation account. Not counted as failures. |

### Control (buggy input)

The control (`00_input/S_vwxxx_MapLinksRecordsToOracle.snowsql`) fails
**identically** on the same 2 `REMOVE` statements, confirming the EXPLAIN
failure is inherent to the input construct, not a regression introduced by
remediation. The control has `TODO(SME) markers outstanding: 0` vs `10` in
the fixed file — the 10 markers are semantic flags added by the fix stage,
not mechanical defects.

Per the orchestrator rules, `FAIL` lines that are environment gaps do not
trigger a re-fix cycle. **No hand-back to s2s-fix.**

---

## 6. What changed in the fixed file

- **0 SQL logic lines changed.** Minimal diff: the SQL body is byte-for-byte
  identical to the input (modulo the added comment lines).
- **Added:** top-of-file `FIX LOG` block citing rule IDs and source lines for
  every `[KEEP]` SNZ construct and every semantic risk.
- **Added:** 10 inline `-- TODO(SME)` markers at the semantic-risk locations
  listed in §4.
- **Preserved:** column order, JOIN keys (none — single-table SELECT), and
  CASE-branch order exactly. `QUALIFY` not present (N/A).

---

## 7. Sign-off checklist

A reviewer can sign off from this document alone:

- [x] No residual Teradata constructs
- [x] Column count 28 = 28 (INSERT vs SELECT)
- [x] No duplicate INSERT columns
- [x] Parse PASS (6 statements, snowflake dialect)
- [x] All SNZ constructs preserved verbatim (14 tags, 1 PUT, 1 GET, 4 stage DML)
- [x] `.snowsql` extension retained (so `snowsql_protect.py` masking applies)
- [x] `REMOVE` EXPLAIN failures confirmed as environment gap (control fails identically)
- [ ] **SME resolves 10 `TODO(SME)` items** (SEM-04/05/06/08, OBS-01) — gate item
- [ ] If a `.teradata.sql` ground truth is later supplied, re-run Stage 1 and diff

---

## 8. Reference

- **Stage-6 semantic doc:** `06_explain/output/semantic_S_vwxxx_MapLinksRecordsToOracle.md`
  — the clause-by-clause semantic account. This report is the
  syntactic/mechanical record; it references the semantic doc, it does not
  duplicate it.
- **Lesson learned:** appended to `02_rules/06_lessons_learned.md`
  (2026-07-24 entry).