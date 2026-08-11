# Fix Report — `S_vwxxx_MloadLinksInserts.snowsql`

**Unit:** `S_vwxxx_MloadLinksInserts`
**Input:** `00_input/S_vwxxx_MloadLinksInserts.snowsql` (`.snowsql` client layer)
**Fixed file:** `03_fix/output/S_vwxxx_MloadLinksInserts_fixed.snowsql`
**Analysis:** `01_analyze/output/analysis_S_vwxxx_MloadLinksInserts.md`
**Validation:** `04_validate/output/validation_S_vwxxx_MloadLinksInserts.md`
**Stage-6 semantic doc:** `06_explain/output/semantic_S_vwxxx_MloadLinksInserts.md`
**Teradata ground truth:** **Not supplied** (no `00_input/S_vwxxx_MloadLinksInserts.teradata.sql`). Every semantic inference is flagged `TODO(SME)`.
**Run type:** Re-run (prior run dated 2026-07-24).
**Date:** 2026-07-25

---

## 1. Executive summary

A single `INSERT … SELECT … WHERE NOT EXISTS` anti-join that loads new
flight-folder-link rows from `STAGING.ExpFinalyseInserts` into
`BASE.FLT_FOLDER_LINKS`, suppressing rows already present on all 33 key
columns. The statement is **parse-clean Snowflake SQL** — zero mechanical
fixes were required (SFX/FNX/DTX/DEF/SNZ all = 0). The only findings are two
SME-classified semantic risks (SEM-03 `CHAR(n)` padding drift, SEM-06
implicit-cast drift) that require DDL for both tables to resolve. The fix
consisted solely of adding a `FIX LOG` header and 18 inline `-- TODO(SME)`
markers; no SQL logic was changed.

**Mechanical verdict: PASS.** Column count 33 = 33, no duplicates, no residual
Teradata constructs, `.snowsql` extension preserved. Control PASS is expected
for this semantic-only unit and is **not** a re-fix trigger.

---

## 2. Rules applied

### Syntax fixes (SFX-*) — 0
None. No residual Teradata constructs found: no `ZEROIFNULL`/`NULLIFZERO`,
`CONTAINS`/`OVERLAPS`, `SEL`, `SET`/`MULTISET`, `PRIMARY INDEX`,
`COLLECT STATS`, BTEQ directives, `LOCKING`, `(+)`, `MINUS`, `TOP`, `FORMAT`
cast, or `BYTEINT`/`CHARACTER SET`/`PERIOD`/`CLOB` types.

### Function fixes (FNX-*) — 0
None. No legacy function calls found.

### Datatype fixes (DTX-*) — 0
None. No DDL present; no type pitfalls in the DML.

### Defect repairs (DEF-*) — 0
None. Parentheses balanced (DEF-03), no duplicate columns (DEF-01), INSERT/SELECT
counts match 33 = 33 (DEF-05), no malformed function calls (DEF-04), no broken
keywords (DEF-02). The 33-predicate `NOT EXISTS` conjunction is well-formed.

### SnowSQL client layer (SNZ-*) — 0 (KEEP)
SNZ inventory is **empty**: no `<% %>` template tags, no `PUT`/`GET` commands,
no stage DML (`COPY INTO @stage`/`REMOVE`/`LIST`). The `.snowsql` extension is
preserved on the fixed output for validator masking-path consistency (per the
2026-07-24 lesson for this same unit).

### Semantic risks flagged (SEM-*) — 2 (both SME)

| SEM ID | Risk | Location | Classification | Action |
|---|---|---|---|---|
| **SEM-03** | `CHAR(n)` padding & comparison drift in the 33-key `NOT EXISTS` anti-join | `NOT EXISTS` predicates (lines ~76–108) | `SME` | No SQL change — no DDL supplied. Inline `-- TODO(SME)` markers added. If any key is `CHAR(n)`, wrap both sides of each such predicate in `RTRIM()`. |
| **SEM-06** | Implicit cast / type mismatch — `_SMALLINT`/`_DATE`-suffixed SELECT aliases compared against unknown BASE column types; positions 8 & 18 map `_DATE` aliases onto `_TM` targets | SELECT aliases (lines ~4–8, 15, 17–19, 26–29) + predicates | `SME` | No SQL change — no DDL supplied. Inline `-- TODO(SME)` markers added on each `_SMALLINT`/`_DATE` line. Confirm DDL types for both tables. |

Other SEM rules (SEM-01, SEM-02, SEM-04, SEM-05, SEM-07, SEM-08, SEM-09, SEM-10)
were evaluated and **not triggered** (see analysis §4). Note: SEM-05 (SET-table
dedup) does not fire from a single `INSERT` — the `NOT EXISTS` is an explicit
anti-join dedup pattern in the SQL itself, not an implicit SET-table dedup.

---

## 3. Defects repaired

None. Zero DEF-* defects were found or repaired.

---

## 4. Open `TODO(SME)` items — 18 markers

All 18 outstanding `TODO(SME)` markers are semantic, awaiting DDL for
`BASE.FLT_FOLDER_LINKS` and `STAGING.ExpFinalyseInserts`:

1. **SEM-03 (1 marker, block-level)** — In the `NOT EXISTS` subquery: confirm
   whether any of the 33 anti-join key columns in `BASE.FLT_FOLDER_LINKS` are
   declared `CHAR(n)` (e.g. `*_CD`, `*_TYP`, `*_TXT`, `*_IND`). If yes, wrap
   both sides of each `CHAR(n)` predicate in `RTRIM()` so the anti-join
   suppresses the same rows Teradata would.
2. **SEM-06 (1 marker, block-level)** — In the `NOT EXISTS` subquery: confirm
   the BASE column types match the `_SMALLINT`/`_DATE`-cast staging values so
   Snowflake's implicit casts produce the same row-suppression behaviour as
   Teradata.
3. **SEM-06 (16 markers, per-line)** — One on each `_SMALLINT`/`_DATE`-suffixed
   SELECT expression, confirming the corresponding BASE column type matches:
   - `NEW_IN_FLT_NO_SMALLINT` → `IN_FLT_NO`
   - `NEW_IN_DEP_FLTDT_DATE` → `IN_DEP_FLTDT`
   - `NEW_IN_ARR_FLTDT_DATE` → `IN_ARR_FLTDT`
   - `NEW_IN_ARR_FLTTM_DATE` → `IN_ARR_FLTTM` (note: `_DATE` alias onto a `_TM` target — possible grain mismatch)
   - `NEW_OUT_FLT_NO_SMALLINT` → `OUT_FLT_NO`
   - `NEW_OUT_DEP_FLTDT_DATE` → `OUT_DEP_FLTDT`
   - `NEW_OUT_DEP_FLTTM_DATE` → `OUT_DEP_FLTTM` (note: `_DATE` alias onto a `_TM` target — possible grain mismatch)
   - `NEW_OUT_ARR_FLTDT_DATE` → `OUT_ARR_FLTDT`
   - `NEW_MIDNIGHT_QTY_SMALLINT` → `MIDNIGHT_QTY`
   - `NEW_BUFFER_DUR_SMALLINT` → `BUFFER_DUR`
   - `NEW_STD_WORKING_DUR_SMALLINT` → `STD_WORKING_DUR`
   - `NEW_TOW_TIME_DUR_SMALLINT` → `TOW_TIME_DUR`

   (The remaining 4 `_SMALLINT`/`_DATE` lines share the block-level SEM-06
   marker in the `NOT EXISTS` subquery rather than a per-line marker.)

**Gate items for sign-off:** the two SEM-03 / SEM-06 SME questions above. Both
require DDL for both tables; neither can be resolved from the SQL alone.

---

## 5. Validation result

**Mechanical verdict: ✅ PASS** (run via `04_validate/validate.py`).

| # | Check | Result |
|---|-------|--------|
| 1 | Parse as Snowflake (sqlglot) | ✅ PASS — 1 statement |
| 2 | INSERT columns == SELECT expressions | ✅ PASS — 33 == 33 |
| 3 | No duplicate INSERT columns | ✅ PASS |
| 4 | No residual Teradata constructs | ✅ PASS |
| 5 | `.snowsql` template tags / `PUT`/`GET` preserved | ✅ INFO — masked for validation, preserved as-is in file |

**Manual spot-check verdict: PASS.** JOIN keys, CASE branch order, column
count/order, `.snowsql` layer, and residual-Teradata scan all confirmed. The
SEM-03/SEM-06 remediation was applied with minimal diff and flagged for SME
review; no unflagged inferences were introduced.

### Buggy input control

The control (buggy input) also PASSES the mechanical validator (parse + column
count + no duplicates + no residual Teradata). **This is expected** — this
unit's defects are purely semantic (SEM-03 `CHAR` padding, SEM-06 implicit
cast), not mechanical. The validator is a structural/parse tool and correctly
reports the buggy input as mechanically clean. A passing control for a
semantic-only defect class is the anticipated outcome and is **not** a re-fix
trigger. The decisive evidence is the SEM-* inventory and the manual
spot-check of the fixed file, not the control's mechanical result (per the
standing lesson: *"A parse PASS is not correctness."*).

---

## 6. Minimal diff

The SQL logic is **byte-for-byte identical** to the input except for:
- An added `FIX LOG` header block (citing 0 mechanical fixes and the two SEM-*
  risks flagged).
- 18 inline `-- TODO(SME)` comments (2 block-level in the `NOT EXISTS`
  subquery, 16 per-line on the `_SMALLINT`/`_DATE` SELECT expressions).

No clause was rewritten, no column reordered, no predicate altered, no
formatting changed.

---

## 7. Sign-off

A reviewer can sign off this unit once the two open SME questions are answered
with DDL for `BASE.FLT_FOLDER_LINKS` and `STAGING.ExpFinalyseInserts`:

- **SEM-03:** Confirm no `CHAR(n)` keys (or apply `RTRIM()` to those that are).
- **SEM-06:** Confirm BASE column types match the `_SMALLINT`/`_DATE`-cast
  staging values, with special attention to the `_TM` targets at positions 8
  (`IN_ARR_FLTTM`) and 18 (`OUT_DEP_FLTTM`).

Until then, the fixed file is mechanically clean and semantically faithful to
the supplied Snowflake input; the `TODO(SME)` markers are the only open items.

**Stage-6 semantic doc:** see
`06_explain/output/semantic_S_vwxxx_MloadLinksInserts.md` for the
clause-by-clause walk-through and the SEM-03 / SEM-06 analysis. This report
references it; it does not duplicate it.