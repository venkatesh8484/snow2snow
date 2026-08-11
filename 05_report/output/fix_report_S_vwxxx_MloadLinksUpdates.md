# Stage 5 — Fix Report: `S_vwxxx_MloadLinksUpdates.snowsql`

**Unit:** `S_vwxxx_MloadLinksUpdates.snowsql`
**Input:** `00_input/S_vwxxx_MloadLinksUpdates.snowsql` (43 lines)
**Fixed file:** `03_fix/output/S_vwxxx_MloadLinksUpdates_fixed.snowsql`
**Analysis:** `01_analyze/output/analysis_S_vwxxx_MloadLinksUpdates.md`
**Validation:** `04_validate/output/validation_S_vwxxx_MloadLinksUpdates.md`
**Input type:** `.snowsql` (SNZ-* rules apply; `snowsql_protect.py` masking).
**Teradata ground truth:** none supplied.
**Reviewer guidance:** none — no `07_review/output/review_S_vwxxx_MloadLinksUpdates.md`.
**Date:** 2026-07-27.

---

## 1. Input summary

A single `UPDATE BASE.FLT_FOLDERLINKS tgt SET LINK_EXPIRY_DT = src.LINK_EXPIRY_DT,
CURRENT_REC_IND = src.CURRENT_REC_IND FROM (SELECT … FROM
STAGING.Rtr_DirectFlowOfLinksRecords WHERE ACTION_CODE IN ('U','B')) src WHERE
<7-key join> AND NOT EXISTS (SELECT 1 FROM BASE.FLIGHT_FOLDERLINKS x WHERE
<7-key anti-join + LINK_EXPIRY_DT + CURRENT_REC_IND>)`. The subquery builds
`LINK_EXPIRY_DT` via an `IFF(TO_CHAR(OLD_LINK_EXPIRY_DT,'YYYYMMDD') <>
'20501231', OLD_LINK_EXPIRY_DT, DATEADD(DAY,-1,TO_DATE('<% … %>','DDMONYY')))`
fallback that embeds a SnowSQL template tag, and `CURRENT_REC_IND` via
`IFF(ACTION_CODE = 'U','Y','N')`.

- **Statement shape:** 1 UPDATE (unchanged structure).
- **SNZ inventory:** 1 SNZ-01 template tag (line 18) inside `TO_DATE(...,'DDMONYY')`.

---

## 2. Findings by class

| Class | Count | Findings |
|---|---|---|
| **AUTO** | 0 | — |
| **FIX** | 1 | DEF-07 alias rename `IN_DEP_GMTFLIGHT_FLIGHT_DT` → `IN_DEP_FLIGHT_DT` (line 13) |
| **SME** | 5 | DEF-07 table-name mismatch (line 2 vs 33); SEM-03 CHAR padding; SEM-06 locale mask; SEM-08 NULL/empty-string in `IFF`; SEM-10 join-key grain |
| **KEEP** | 1 | SNZ-01 template tag (line 18) preserved verbatim |

---

## 3. Fixes applied (rule IDs + line numbers)

| Rule | Source line(s) | Change |
|---|---|---|
| **DEF-07** | 13 | Subquery alias `OLD_IN_DEP_FLIGHT_DT AS IN_DEP_GMTFLIGHT_FLIGHT_DT` → `AS IN_DEP_FLIGHT_DT` (find/replace drift — doubled `FLIGHT` and `GMT` infix). The outer `WHERE` reference `src.IN_DEP_FLIGHT_DT` (line 31) and the `NOT EXISTS` guard `tgt.IN_DEP_FLIGHT_DT` (line 38) already use `IN_DEP_FLIGHT_DT`, so the alias was the outlier. Minimal diff = 1 token (alias only; outer `WHERE` and guard left untouched). At runtime the buggy alias raises `invalid identifier 'SRC.IN_DEP_FLIGHT_DT'`. |

No syntax (SFX/FNX/DTX) fixes were required — the SQL body is parse-clean
Snowflake. The only non-SQL token is the SNZ-01 template tag (line 18), which
is preserved verbatim (not a defect).

---

## 4. Defects repaired

1. **DEF-07 (line 13 vs 31)** — alias/reference mismatch (find/replace drift).
   Renamed the subquery alias to align with the outer `WHERE` reference and
   the `NOT EXISTS` guard. The repair is unambiguous because the outer scope
   already uses `IN_DEP_FLIGHT_DT` consistently at lines 31 and 38 — the alias
   was the outlier. Carries a `TODO(SME)` noting the rename.

**Not repaired (SME):** DEF-07 table-name mismatch — `UPDATE` target
`BASE.FLT_FOLDERLINKS` (line 2) vs `NOT EXISTS` guard `BASE.FLIGHT_FOLDERLINKS`
(line 33). Per DEF-07 no-guess policy, the pipeline does **not** rename either
table without ground truth. Carries forward as `TODO(SME)`.

---

## 5. Open `TODO(SME)` items

13 `TODO(SME)` markers carried forward (all blocked on missing DDL / Teradata
ground truth):

1. **DEF-07 (table name)** — `BASE.FLIGHT_FOLDERLINKS` (line 33) vs
   `BASE.FLT_FOLDERLINKS` (line 2): are these the same table? If not, is the
   guard intended to protect a different table?
2. **DEF-07 (alias rename)** — confirm the `IN_DEP_FLIGHT_DT` alias rename
   matches the staging column grain.
3. **SEM-03** — `CHAR(n)` padding drift on the 9 join/anti-join keys; if any
   are `CHAR(n)`, wrap both sides in `RTRIM()`.
4. **SEM-06** — `TO_DATE('<% … %>','DDMONYY')` locale-dependent `MON` mask;
   confirm the orchestrator-supplied date matches `'DDMONYY'` and the session
   locale matches the source.
5. **SEM-08** — `IFF` NULL-handling: `TO_CHAR(NULL) <> '20501231'` → NULL
   (false-branch); `ACTION_CODE = 'U'` with NULL → `'N'`. Confirm NULL paths
   match Teradata intent.
6. **SEM-10** — join-key grain/direction; confirm the 7 `OLD_*` staging
   columns map 1:1 to the `tgt` BASE columns by grain.

---

## 6. Validation result

- **Fixed file:** `python3 04_validate/validate.py 03_fix/output/S_vwxxx_MloadLinksUpdates_fixed.snowsql`
  → **PASS**. 1 statement parsed; no residual Teradata constructs; 13
  `TODO(SME)` markers outstanding.
- **Control (buggy input):** `python3 04_validate/validate.py 00_input/S_vwxxx_MloadLinksUpdates.snowsql`
  → **PASS** (1 statement, no residual Teradata, 0 TODO markers). **This
  control PASS is EXPECTED** — the defect is a DEF-07 alias issue that is
  **positional-inert**: the outer `src.IN_DEP_FLIGHT_DT` reference would bind
  to the aliased column by position regardless of the alias name, so the buggy
  input produces the same mechanical result as the fixed file. The validator
  cannot catch a positional-inert alias defect — it has no semantic
  alias-resolution capability (sqlglot does not resolve identifiers against the
  subquery output schema; EXPLAIN is skipped because objects are not loaded).
  Per the standing lesson (*"A control PASS on a positional-inert defect is
  expected"*), the decisive evidence is the manual spot-check, not the
  control's mechanical result. **Not a re-fix trigger.**

---

## 7. Residual-construct count

**0.** No residual Teradata constructs in the fixed file.

---

## 8. Open `TODO(SME)` count

**13.**

---

## 9. Sign-off checklist

- [x] 1 statement preserved; structure intact.
- [x] No residual Teradata constructs.
- [x] `.snowsql` template tag (`<% ctx.env.S_vw6122_…_Current_date %>`, line 18)
      preserved as-is, per SNZ-01.
- [x] `QUALIFY` (none present) — n/a.
- [x] JOIN keys and CASE-branch order preserved exactly.
- [x] DEF-07 alias corrected; positional binding verified so the outer
      `src.IN_DEP_FLIGHT_DT` reference is unaffected by the alias rename.
- [x] 13 `TODO(SME)` markers carried forward for reviewer sign-off.
- [x] Validation PASS; control PASS expected (DEF-07 positional-inert).

**Verdict: PASS — ready for reviewer sign-off.** The single DEF-07 alias fix is
a 1-token change with no semantic drift (positional binding); the SNZ-01
template tag is preserved verbatim; the 5 open SME items are all blocked on
missing DDL / Teradata ground truth and must not be rewritten without reviewer
confirmation. See the Stage-6 semantic doc
`06_explain/output/semantic_S_vwxxx_MloadLinksUpdates.md` for the
clause-by-clause walk-through.