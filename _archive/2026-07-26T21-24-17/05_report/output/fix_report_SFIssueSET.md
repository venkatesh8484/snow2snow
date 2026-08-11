# Fix report — SFIssueSET

**Unit:** SFIssueSET
**Input:** `00_input/SFIssueSET.sql`
**Fixed SQL:** `03_fix/output/SFIssueSET_fixed.sql`
**Analysis:** `01_analyze/output/analysis_SFIssueSET.md`
**Validation:** `04_validate/output/validation_SFIssueSET.md`
**Semantic doc:** `06_explain/output/semantic_SFIssueSET.md` (archived copy:
`_archive/2026-07-25T18-43-25/06_explain/output/semantic_SFIssueSET.md`)
**Teradata ground truth:** none (no `00_input/SFIssueSET.teradata.sql`).
**Reviewer guidance:** `07_review/output/review_SFIssueSET.md` — *"This is a SET
table in teradata. So, there should not be any duplicates. You need to handle the
dedup logic in the query."* (authoritative; closes the SEM-05 SET-table question).
**Date:** 2026-07-25.
**Run type:** re-run confirming the SEM-05 SET-table dedup fix.

---

## 1. Summary

`SFIssueSET` refreshes `staging.wrk_target` — a **SET table** (reviewer-confirmed)
— with the latest effective flight attributes from three leg sources (marketing,
operational, codeshare). The buggy input collapsed three independent Teradata
`INSERT`s into a single `INSERT … UNION … UNION`, which is wrong for a SET table
on two counts: `UNION` deduplicates *across* branches (collapsing rows two
branches emit in common), and a single `INSERT` re-inserts rows already present
in the target (Snowflake has no SET-table silent-drop).

The fix applies **SEM-05 (SET-table dedup, reviewer-confirmed)**: split the
3-branch `INSERT … UNION … UNION` into **3 independent**
`INSERT INTO staging.wrk_target (col list) (SELECT … EXCEPT SELECT * FROM
staging.wrk_target)` statements — one per branch — and remove the `UNION`
operators entirely. An explicit 8-column INSERT target list was added so the
`EXCEPT SELECT *` positional match is unambiguous.

The file is parse-clean Snowflake; **0 mechanical syntax/function/defect fixes**
were required. All remaining risks are SME-classified semantic concerns carried
forward as inline `TODO(SME)` markers pending source DDL / Teradata ground truth.

- **Statements in fixed file:** 3 (one `INSERT … EXCEPT` per branch).
- **INSERT vs SELECT column count:** 8 = 8 per statement (no DEF-05 mismatch).
- **TODO(SME) markers outstanding:** 6.
- **Validation:** PASS (mechanical + manual). Control PASS (expected —
  semantic-only defect).

---

## 2. Rules applied

### 2.1 Syntax (SFX-* / FNX-* / DTX-*)

None. The input is parse-clean Snowflake. No residual-Teradata constructs
(`ZEROIFNULL`, `CONTAINS`, `MULTISET`, `(+)`, BTEQ dot-commands, `MINUS`, `SEL`,
`PRIMARY INDEX`, `COLLECT STATS`, `LOCKING … FOR ACCESS`, `CAST(… FORMAT …)`,
`INDEX`/`OREPLACE`/`OTRANSLATE`/`STRTOK`, `**`, `MOD` infix, `LIKE ANY`,
`HASHROW`/`HASHBUCKET`/`HASHAMP`, `TITLE`/`FORMAT` phrases, `BYTEINT`,
`CHARACTER SET LATIN`) were present. No SNZ-* rules apply (input is `.sql`, not
`.snowsql`; no `<% %>` template tags, no `PUT`/`GET` commands).

### 2.2 Defects (DEF-*)

None. DEF-01 through DEF-07 were scanned and did not fire. In particular:
- DEF-05 (INSERT col count ≠ SELECT expr count): n/a — 8 = 8 per branch.
- DEF-06 (alias ≠ target column name): n/a — aliases are cosmetic; `INSERT …
  SELECT` binds by ordinal position.
- DEF-07 (wrong column referenced / copy-paste): n/a — no sibling-pattern
  evidence.

### 2.3 Semantic (SEM-*)

| Rule | Applied as FIX? | Detail |
|---|---|---|
| **SEM-05** (SET-table dedup) | **Yes — FIX** | Reviewer confirmed `staging.wrk_target` is a SET table. Split the single 3-branch `INSERT … UNION … UNION` into 3 independent `INSERT INTO staging.wrk_target (col list) (SELECT … EXCEPT SELECT * FROM staging.wrk_target)` statements. Removed `UNION` operators entirely. Added explicit 8-column INSERT target list so the `EXCEPT SELECT *` positional match is unambiguous. |
| SEM-02 / FN-LATEST | No — SME | `SUBSTR(MAX(src.effective_dt \|\| <val>), 11, N)` latest-value trick in all 3 branches. Correctness depends on `effective_dt` being a fixed-width, lexicographically sortable string. If `DATE`/`TIMESTAMP`, Snowflake's implicit cast may not be zero-padded, so `MAX` can pick the wrong row. No SQL change pending DDL / data-type confirmation. Suggested: `TO_CHAR(effective_dt,'YYYY-MM-DD') \|\| LPAD(<val>::VARCHAR, n, ' ')`. |
| SEM-06 / DTX-10 | No — SME | Implicit `param_value` string→date cast in `WHERE` (`src.flgt_dt > (SELECT param_value …)`) and implicit `effective_dt \|\| <val>` date→string cast. Suggested: `TO_DATE(param_value, '<fmt>')`, `TO_CHAR(effective_dt, 'YYYY-MM-DD')`. Requires DDL / format confirmation. |
| SEM-03 | No — SME | `CHAR(n)` padding drift — join/`EXCEPT` keys (`airline_cd`, `flgt_no`, `company_cd`, `*_stn_cd`, etc.) may be `CHAR(n)`. Teradata blank-pads and ignores trailing spaces in `=`; Snowflake does not, so join/`EXCEPT` matching can drift. Suggested: `TRIM`/`RTRIM`. Cannot confirm without DDL. |
| SEM-04 | No — SME | `TIMESTAMP` vs `TIMESTAMP_TZ` on `gmt_flgt_dt` / `effective_dt` — NTZ/TZ mismatch shifts values. Cannot confirm without DDL. |
| SEM-10 | No — SME | Join-key direction (marketing/operational/codeshare) plausible from table names but unverifiable without Teradata ground truth. |
| SEM-05 (sub) | No — SME | Target physical column order unknown (no DDL supplied). The explicit column list assumes the order `airline_cd, flgt_no, flgt_dt, company_cd, direction_ind, operating_airline_cd, operating_flgt_no, operating_sfx_cd` — matching the SELECT projection order of the buggy input. Confirm against target DDL. |

**Counts:** 1 FIX (SEM-05), 6 SME, 0 AUTO. 0 mechanical syntax/function/defect fixes.

---

## 3. Defects repaired

None of the DEF-* mechanical defects were present. The single repair is the
semantic SEM-05 SET-table dedup split (see §2.3 and §4).

---

## 4. SEM-05 fix detail (the critical repair)

- **Signal:** one `INSERT INTO staging.wrk_target` + 3 `UNION` branches, all
  writing to the same target.
- **DDL supplied?** No — but the reviewer confirmed the target is a SET table,
  which is the missing DDL fact SEM-05 requires. Reviewer confirmation closes the
  SME question and moves SEM-05 to **FIX**.
- **Why the input was wrong:**
  1. `UNION` (not `UNION ALL`) de-duplicates **across** the 3 branches. In
     Teradata the 3 INSERTs were independent — each was deduped **against the
     target's existing rows** (SET semantics), not against each other. `UNION`
     is the wrong dedup axis.
  2. Even with `UNION ALL`, a plain `INSERT` would re-insert rows already
     present in the target, violating SET-table "drop rows already present"
     semantics.
- **Fix applied:** 3 independent
  `INSERT INTO staging.wrk_target (airline_cd, flgt_no, flgt_dt, company_cd,
  direction_ind, operating_airline_cd, operating_flgt_no, operating_sfx_cd)
  (SELECT … EXCEPT SELECT * FROM staging.wrk_target)` statements — one per
  branch (marketing, operational, codeshare). `UNION` operators removed
  entirely. Explicit column list added so the `EXCEPT SELECT *` positional match
  is unambiguous.
- **Minimal diff:** column projection order, JOIN keys, GROUP BY, and WHERE
  predicates within each branch are preserved exactly as authored. Only the
  statement structure (split + `EXCEPT`) and the added INSERT column list
  changed.

---

## 5. Open `TODO(SME)` items

Six `TODO(SME)` markers are embedded in the fix log at the top of
`SFIssueSET_fixed.sql` and remain outstanding for human review:

| # | Rule | Item |
|---|---|---|
| 1 | SEM-05 (sub) | Target physical column order unknown (no DDL). Explicit list assumes projection order of buggy input. Confirm against target DDL. |
| 2 | SEM-02 / FN-LATEST | `SUBSTR(MAX(effective_dt \|\| <val>), 11, N)` key width / sortability. Confirm `effective_dt` type; consider `TO_CHAR(effective_dt,'YYYY-MM-DD') \|\| LPAD(val::VARCHAR,n,' ')`. |
| 3 | SEM-06 / DTX-10 | Implicit `param_value` string→date cast in `WHERE`. Consider `TO_DATE(param_value, '<fmt>')`. Also `effective_dt \|\| <val>` implicit date→string cast. |
| 4 | SEM-03 | `CHAR(n)` padding drift on join/`EXCEPT` keys. Consider `TRIM`/`RTRIM`. Cannot confirm without DDL. |
| 5 | SEM-04 | `TIMESTAMP` vs `TIMESTAMP_TZ` on `gmt_flgt_dt` / `effective_dt`. Cannot confirm without DDL. |
| 6 | SEM-10 | Join-key direction (marketing/operational/codeshare) unverifiable without Teradata ground truth. |

None of these is a SQL defect; all are review items pending source DDL or
Teradata ground truth. They do not affect the mechanical validation verdict.

---

## 6. Validation result

Source: `04_validate/output/validation_SFIssueSET.md`.

### 6.1 Fixed file — mechanical (validator output)

```
PASS  parse: 3 statement(s) parsed as snowflake using sqlglot
PASS  stmt 1: INSERT columns (8) == SELECT expressions (8)
PASS  stmt 1: no duplicate INSERT columns
PASS  stmt 2: INSERT columns (8) == SELECT expressions (8)
PASS  stmt 2: no duplicate INSERT columns
PASS  stmt 3: INSERT columns (8) == SELECT expressions (8)
PASS  stmt 3: no duplicate INSERT columns
PASS  no residual Teradata constructs
INFO  TODO(SME) markers outstanding: 6
RESULT: PASS
```

### 6.2 Fixed file — manual spot-check

| Check | Result |
|---|---|
| Parse / compile under Snowflake dialect | PASS — 3 statements parse cleanly |
| INSERT column count == SELECT expression count (all 3 stmts) | PASS — 8 == 8 each |
| No duplicate INSERT columns | PASS |
| Column order preserved vs. intent | PASS — INSERT column order matches SELECT expression order in each statement |
| JOIN keys preserved | PASS — JOIN keys retained as authored; no key dropped or reordered |
| CASE-branch order preserved | PASS — CASE branches kept in original order; no reordering |
| No dropped columns | PASS — all 8 columns per statement present on both INSERT and SELECT sides |
| No residual Teradata constructs | PASS — no `ZEROIFNULL`, `CONTAINS`, `MULTISET`, `(+)`, `MINUS`, `SEL`, BTEQ dot-commands |
| `QUALIFY` handling | N/A — no `QUALIFY` clauses present |
| SET-table dedup semantics (SEM-05) | PASS (manual) — fixed SQL enforces dedup per SEM-05; mechanical validator cannot verify without DDL, so manual spot-check is decisive |

**Manual verdict:** PASS.

### 6.3 Buggy input control

```
PASS  parse: 1 statement(s) parsed as snowflake using sqlglot
PASS  no residual Teradata constructs
RESULT: PASS
```

The control **PASSES** the mechanical validator. This is **expected and not a
re-fix trigger**: the defect in `SFIssueSET` is purely semantic (SEM-05 SET-table
dedup). The mechanical validator has no DDL and cannot detect SET-table
duplicate-row violations, so a semantic-only defect correctly passes the
control. Per s2s-validate policy, the manual spot-check (§6.2) — not the
control run — is the decisive evidence for the fix.

### 6.4 Overall

| Item | Verdict |
|---|---|
| Fixed file — mechanical | PASS |
| Fixed file — manual spot-check | PASS |
| Control (buggy input) | PASS (expected for SEM-* semantic-only defect) |
| **Overall** | **PASS** |

No hand-back to s2s-fix. The fixed file is mechanically valid Snowflake,
semantically faithful to the SEM-05 dedup intent, and free of residual Teradata
constructs.

---

## 7. Sign-off

A reviewer can sign off from this document alone:

- ✅ Single critical fix (SEM-05 SET-table dedup split) applied with reviewer
  confirmation of the SET-table fact.
- ✅ 3 independent `INSERT … EXCEPT SELECT * FROM staging.wrk_target`
  statements; `UNION` removed; explicit 8-column INSERT list added.
- ✅ 8 = 8 INSERT/SELECT column count per statement; no duplicate INSERT columns.
- ✅ No residual Teradata constructs.
- ✅ Column order, JOIN keys, and CASE-branch order preserved (minimal diff).
- ✅ Validation PASS (mechanical + manual); control PASS (expected, semantic-only).
- ⚠ 6 `TODO(SME)` items open pending source DDL / Teradata ground truth (review
  items, not defects).

**Semantic account:** see `06_explain/output/semantic_SFIssueSET.md` (archived
copy: `_archive/2026-07-25T18-43-25/06_explain/output/semantic_SFIssueSET.md`)
for the clause-by-clause walk-through and the SEM-05 correction pattern. This
report does not duplicate it.