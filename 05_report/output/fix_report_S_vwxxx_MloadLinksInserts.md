# Stage 5 — Fix Report: `S_vwxxx_MloadLinksInserts.snowsql`

**Unit:** `S_vwxxx_MloadLinksInserts.snowsql`
**Input:** `00_input/S_vwxxx_MloadLinksInserts.snowsql` (109 lines)
**Fixed file:** `03_fix/output/S_vwxxx_MloadLinksInserts_fixed.snowsql`
**Analysis:** `01_analyze/output/analysis_S_vwxxx_MloadLinksInserts.md`
**Validation:** `04_validate/output/validation_S_vwxxx_MloadLinksInserts.md`
**Input type:** `.snowsql` (SNZ-* rules apply; `snowsql_protect.py` masking).
**Teradata ground truth:** none supplied.
**Reviewer guidance:** none — no `07_review/output/review_S_vwxxx_MloadLinksInserts.md`.
**Date:** 2026-07-27.

---

## 1. Input summary

A single `INSERT INTO BASE.FLT_FOLDER_LINKS (33 cols) SELECT … FROM
STAGING.ExpFinalyseInserts S WHERE S.IN_FLT_LEG_SEQ_NO IS NOT NULL AND
S.OUT_FLT_LEG_SEQ_NO IS NOT NULL AND NOT EXISTS (SELECT 1 FROM
BASE.FLT_FOLDER_LINKS T WHERE <all 33 columns equated>)`. It is a full-row
anti-dup INSERT: a staging row is inserted only if no identical row already
exists in the base target. The `NOT EXISTS` emulates Teradata SET-table "drop
rows already present" semantics in Snowflake-native form.

- **Statement shape:** 1 INSERT (unchanged).
- **Column-count check:** 33 = 33 — no DEF-05.
- **SNZ inventory:** empty (no `<% %>` tags, no `PUT`/`GET`, no stage DML). The
  `.snowsql` extension is retained on the fixed output so the validator's
  `is_snowsql()` masking path applies consistently.

---

## 2. Findings by class

| Class | Count | Findings |
|---|---|---|
| **AUTO** | 0 | — |
| **FIX** | 0 | — |
| **SME** | 4 | SEM-03 (CHAR padding in full-row anti-join); SEM-06/DTX-10 (type-suffixed aliases vs unknown BASE types); SEM-04 (TZ on `_TTM` time columns); SEM-05 (SET vs MULTISET on `BASE.FLT_FOLDER_LINKS`) |
| **KEEP** | 0 | SNZ inventory empty (`.snowsql` extension retained) |

**No mechanical (AUTO/FIX) fixes were required.** The file parses cleanly on
Snowflake with no residual Teradata constructs and no defects. All findings
are semantic and require DDL for `BASE.FLT_FOLDER_LINKS` and
`STAGING.ExpFinalyseInserts` (and/or SME confirmation) to resolve.

---

## 3. Fixes applied (rule IDs + line numbers)

None. No SQL logic lines changed. The entire remediation was a FIX LOG header
block + inline `TODO(SME)` markers at semantic-risk locations. A 0-fix run is a
valid outcome for a parse-clean, semantic-only unit — do not invent fixes to
justify the stage.

---

## 4. Defects repaired

None. No DEF-* defect fired (no duplicate columns, no count mismatch — 33=33,
no malformed calls, no alias defects, no wrong-column references).

---

## 5. Open `TODO(SME)` items

27 `TODO(SME)` markers carried forward (all blocked on missing DDL for
`BASE.FLT_FOLDER_LINKS` and `STAGING.ExpFinalyseInserts`):

1. **SEM-05** — SET vs MULTISET on `BASE.FLT_FOLDER_LINKS` cannot be decided
   from the SQL alone (no `CREATE TABLE` DDL). The `NOT EXISTS` full-row
   anti-join emulates Teradata SET-table dedup. If the target is SET, the
   `NOT EXISTS` is harmless belt-and-suspenders; if MULTISET, it is the only
   dedup mechanism (load-bearing). SME question: "Is `BASE.FLT_FOLDER_LINKS`
   a SET table?"
2. **SEM-03** — `CHAR(n)` padding drift in the full-row `NOT EXISTS` anti-join
   (all 33 `T.col = S.NEW_col` predicates). Teradata blank-pads `CHAR(n)` and
   ignores trailing spaces in `=`; Snowflake does not. Requires DDL to
   identify `CHAR(n)` columns; if any, wrap both sides in `RTRIM`/`TRIM`.
3. **SEM-06/DTX-10** — 12 SELECT aliases carry `_SMALLINT`/`_DATE` suffixes
   (e.g. `NEW_IN_FLT_NO_SMALLINT`, `NEW_*_FLTDT_DATE`, `NEW_*_FLTTM_DATE`,
   `NEW_*_SMALLINT`). The suffix describes the staging cast, **not** the target
   column type. The `NOT EXISTS` predicates compare these against unknown BASE
   column types — a mismatch could silently change anti-join suppression or
   raise a strict-cast error. Requires DDL for both sides.
4. **SEM-04** — timezone risk on `_TTM` time columns (`IN_ARR_FLTTM`,
   `OUT_DEP_FLTTM`) loaded from `_DATE`-suffixed staging values. If the staging
   cast produced a `TIMESTAMP(_TZ)` and the target is `TIME`/`TIMESTAMP_NTZ`,
   a session-`TIMEZONE` shift could move values. Confirm staging cast + target
   type; pin session `TIMEZONE` or use `TIMESTAMP_NTZ` explicitly if needed.

---

## 6. Validation result

- **Fixed file:** `python3 04_validate/validate.py 03_fix/output/S_vwxxx_MloadLinksInserts_fixed.snowsql`
  → **PASS (after 1 re-fix cycle)**. 1 statement parsed; 33 = 33 columns; no
  duplicate INSERT columns; no residual Teradata constructs; 27 `TODO(SME)`
  markers outstanding.
  - **Re-fix cycle 1 — comment-wording fix (not a SQL defect):** The first
    validation run **FAILED** the residual-Teradata scan. The cause was **not**
    a SQL defect: an inline `-- TODO(SME)` comment on the INSERT line contained
    the literal word `MULTISET`, which the validator's residual-construct regex
    (`\bMULTISET\b`) matched as a residual Teradata `MULTISET` table-type
    keyword. The comment was reworded to **"non-SET (multi-row)"** to avoid the
    literal token. The SQL body was unchanged — only the comment wording was
    adjusted. After this comment fix the validator PASSes.
- **Control (buggy input):** `python3 04_validate/validate.py 00_input/S_vwxxx_MloadLinksInserts.snowsql`
  → **PASS** (33 = 33, no residual Teradata, 0 TODO markers). **This control
  PASS is EXPECTED** — this is a semantic-only unit; the defect is not
  syntactic, so the buggy input parses and passes the column-count /
  residual-Teradata checks just like the fixed file. Per the standing lesson
  (*"A parse PASS is not correctness"*), the decisive evidence is the SEM-*
  inventory and the manual spot-check, not the control's mechanical result.
  **Not a re-fix trigger.**

---

## 7. Residual-construct count

**0.** No residual Teradata constructs in the fixed file (confirmed after the
comment-wording fix that removed the literal `MULTISET` token from an inline
`-- TODO(SME)` comment).

---

## 8. Open `TODO(SME)` count

**27.**

---

## 9. Sign-off checklist

- [x] 1 INSERT statement preserved; writes 33 columns to the target.
- [x] INSERT column order matches SELECT expression order (33 = 33).
- [x] No duplicate INSERT columns.
- [x] No residual Teradata constructs — confirmed after the comment-wording
      fix (literal `MULTISET` token in an inline `-- TODO(SME)` comment
      reworded to "non-SET (multi-row)").
- [x] `.snowsql` extension retained; SNZ inventory empty (no template tags /
      PUT / GET to preserve).
- [x] `QUALIFY` (none present) — n/a.
- [x] JOIN keys and CASE-branch order preserved exactly.
- [x] 27 `TODO(SME)` markers carried forward for reviewer sign-off.
- [x] Validation PASS (after 1 re-fix cycle — comment-wording only); control
      PASS expected (semantic-only).

**Verdict: PASS — ready for reviewer sign-off.** No SQL logic changed; the
single re-fix cycle was a comment-wording correction (literal `MULTISET` token
in a `-- TODO(SME)` comment), not a SQL defect. The 4 open SME items are all
blocked on missing DDL for the base target and staging source and must not be
rewritten without reviewer confirmation. See the Stage-6 semantic doc
`06_explain/output/semantic_S_vwxxx_MloadLinksInserts.md` for the
clause-by-clause walk-through.