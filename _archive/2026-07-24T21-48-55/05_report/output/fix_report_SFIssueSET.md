# Fix Report — `SFIssueSET.sql`

**Unit:** SFIssueSET
**Date:** 2026-07-24 (re-run)
**Pipeline:** Snowflake → Snowflake ICM remediation
**Target dialect:** Snowflake
**Teradata ground truth:** none (`00_input/SFIssueSET.teradata.sql` not present)
**Stage-6 semantic doc:** `06_explain/output/semantic_SFIssueSET.md` (see archived copy at `_archive/2026-07-24T19-12-17/06_explain/output/semantic_SFIssueSET.md`)

---

## 1. Summary

`SFIssueSET.sql` is a single `INSERT INTO staging.wrk_target` whose SELECT is
three branches joined by `UNION`. Each branch joins `synthetic_flgt_source`
(`src`) to a different flight-leg table — marketing (`synthetic_mkg_flgt_leg`),
operational (`synthetic_operational_flgt_leg`), and codeshare
(`synthetic_codeshare_flgt_leg`) — filters on `dep_stn_cd <> arr_stn_cd` and
`flgt_dt > (UPDATE_CUTOFF param)`, groups by `(airline_cd, flgt_no, flgt_dt)`,
and uses the latest-value trick `SUBSTR(MAX(effective_dt || val), 11, …)` to
pick each attribute from the row with the maximum `effective_dt` per group.

**No mechanical fixes were required.** The file parses and compiles cleanly on
Snowflake as written — zero syntax errors, zero residual Teradata constructs,
zero structural defects. All six findings are **semantic** and classified
**SME**: they require a subject-matter-expert decision (SET vs MULTISET,
`UNION` vs `UNION ALL`, latest-value key width, `MAX` tie-break, implicit
string→date cast, `operating_airline_cd` width-3 truncation). Per the
minimal-diff policy and SEM-05 ("SET vs MULTISET lives in the target DDL, not
in an INSERT-only script — do not decide without the DDL"), the SQL structure
was preserved as-is and every risk was flagged with an inline `TODO(SME)`
marker rather than rewritten.

**Validation: PASS.** The fixed file parses and compiles against a live
Snowflake backend (EXPLAIN OK) with no residual Teradata constructs. The
control (buggy input) also PASSes — expected for a semantic-only unit, where
the mechanical validator cannot detect semantic drift. This matches the
2026-07-24 lesson: *"A parse PASS is not correctness."*

---

## 2. Rules applied

### 2.1 Syntax (SFX-* / FNX-*)

**None.** The file contains no residual Teradata constructs and no syntax
errors. No SFX-* or FNX-* rule was invoked.

### 2.2 Defects (DEF-*)

**None.** No structural defects were found. Column-count consistency across the
three `UNION` branches was verified (8 expressions per branch, positionally
identical). DEF-05 (INSERT vs SELECT count) cannot be confirmed without the
target DDL — this is an open dependency, not a defect in the SQL itself.

### 2.3 Semantic (SEM-*)

All six semantic findings were classified **SME** — no SQL was changed. Each
was flagged with an inline `TODO(SME)` marker in `03_fix/output/SFIssueSET_fixed.sql`.

| # | Lines | Risk | Rule | Class | Action taken |
|---|---|---|---|---|---|
| S1 | 1, 30, 60 | SET-table dedup signal — single `INSERT` with 3 `UNION` branches into `staging.wrk_target`, no target DDL supplied | **SEM-05** | SME | `TODO(SME)` at INSERT and both UNION operators; structure preserved. Do **not** split into separate INSERTs or add `EXCEPT` without DDL/SME confirmation. |
| S2 | 30, 60 | `UNION` vs `UNION ALL` set-semantics — 2 de-duplicating `UNION` operators | **SEM-05** (cross-ref lesson) | SME | `TODO(SME)` at both `UNION` operators. |
| S3 | 6–13, 33–40, 63–70 | Latest-value trick needs fixed-width key — `SUBSTR(MAX(effective_dt \|\| val), 11, …)` with raw date concat and variable-width value | **SEM-02 / FN-LATEST** | SME | `TODO(SME)` at each `SUBSTR(MAX(...))` expression (3 branches × value columns). |
| S4 | 6–13, 33–40, 63–70 | `MAX` over string concat tie-break non-determinism — if `effective_dt` is non-unique per group, `MAX` picks the lexicographically larger value, not the intended row | **SEM-02** | SME | Covered by the S3 `TODO(SME)` markers. |
| S5 | 17, 47, 77 | Scalar subquery `param_value` implicit string→date cast — `flgt_dt > (SELECT param_value …)` relies on implicit coercion | **SEM-06 / DTX-10** | SME | `TODO(SME)` at each scalar subquery (3 branches). |
| S6 | 8–9, 35–36, 65–66 | `operating_airline_cd` truncated to width 3 (`SUBSTR(...,11,3)`) while all other value columns use width 99 — likely intentional but unconfirmable without ground truth | **SEM** (consistency) | SME | No marker added (not a defect per DEF-06/DEF-07 without ground truth); noted in analysis and this report. |

**Critical finding: S1 (SEM-05).** A single `INSERT … UNION … UNION` into one
target is a SET-table dedup signal. With no `CREATE TABLE staging.wrk_target`
DDL supplied, SET vs MULTISET cannot be decided from the SQL alone. Per SEM-05,
the pipeline does **not** assume SET and does **not** rewrite the structure —
it raises the SME question and awaits confirmation.

---

## 3. Defects repaired

**None.** The file was parse-clean. No SFX-*, FNX-*, DEF-*, or DTX-* rule
required a mechanical edit. The FIX LOG at the top of
`03_fix/output/SFIssueSET_fixed.sql` records "No mechanical syntax/defect fixes
required — file parses clean on Snowflake."

---

## 4. Open TODO(SME) items

Ten `TODO(SME)` markers are outstanding in `03_fix/output/SFIssueSET_fixed.sql`,
covering the six semantic findings above:

1. **[SEM-05] SET-table dedup (INSERT, line 1):** Is `staging.wrk_target` a SET
   table? If yes, each `UNION` branch must become a separate
   `INSERT INTO staging.wrk_target (SELECT … EXCEPT SELECT * FROM staging.wrk_target)`.
   Do not assume SET.
2. **[SEM-05] UNION vs UNION ALL (line 30):** Should the first set operator be
   `UNION ALL` (preserve cross-branch duplicates) or a separate INSERT
   (SET-table dedup)? The current `UNION` both de-duplicates across branches
   and re-inserts rows already in the target.
3. **[SEM-05] UNION vs UNION ALL (line 60):** Same question for the second set
   operator.
4. **[SEM-02/FN-LATEST] Latest-value key width (branch 1, lines 6–13):** Is
   `src.effective_dt` a DATE (sortable as `YYYY-MM-DD`) or a TIMESTAMP (needs
   explicit `TO_CHAR` format)? What is the max display width of each
   concatenated value column for `LPAD`? Format as
   `TO_CHAR(effective_dt,'YYYY-MM-DD') || LPAD(val::VARCHAR,n,' ')` before `MAX`.
5. **[SEM-02/FN-LATEST] Latest-value key width (branch 2, lines 33–40):** Same
   as #4 for the operational-leg branch.
6. **[SEM-02/FN-LATEST] Latest-value key width (branch 3, lines 63–70):** Same
   as #4 for the codeshare-leg branch.
7. **[SEM-02] MAX tie-break (all branches):** Is `effective_dt` unique per
   `(airline_cd, flgt_no, flgt_dt)` group, or can ties occur? If ties are
   possible, `MAX` over the concatenated string picks the lexicographically
   larger value, not necessarily the intended row.
8. **[SEM-06/DTX-10] Implicit string→date cast (branch 1, line 17):** Is
   `synthetic_sys_param.param_value` a date-formatted string (e.g.
   `YYYY-MM-DD`)? Should the comparison be
   `src.flgt_dt > TO_DATE(param_value, 'YYYY-MM-DD')`?
9. **[SEM-06/DTX-10] Implicit string→date cast (branch 2, line 47):** Same as
   #8 for the operational-leg branch.
10. **[SEM-06/DTX-10] Implicit string→date cast (branch 3, line 77):** Same as
    #8 for the codeshare-leg branch.

**Plus one unmarked consistency note (S6):** Confirm the width-3 truncation on
`operating_airline_cd` (`SUBSTR(...,11,3)`) is intentional versus the width-99
used on all other value columns.

---

## 5. Validation result

**Verdict: PASS**

| Check | Fixed file | Control (buggy input) |
|---|---|---|
| Snowflake connection | PASS | PASS |
| Parse (sqlglot, snowflake dialect) | PASS — 1 statement | PASS — 1 statement |
| Snowflake EXPLAIN (compile) | PASS — compiled OK | PASS — compiled OK |
| Residual Teradata constructs | PASS — none | PASS — none |
| TODO(SME) markers | INFO — 10 outstanding | INFO — 0 |
| **Overall** | **PASS** | **PASS (expected)** |

**Control explanation.** The control (buggy input) also PASSes because the
defects in `SFIssueSET.sql` are purely semantic — SET-table dedup semantics
(SEM-05), latest-value trick drift (SEM-02), and implicit cast strictness
(SEM-06). A file with only semantic drift parses and compiles cleanly on
Snowflake; the mechanical validator (sqlglot parse + EXPLAIN) cannot detect
semantic incorrectness. A passing control is therefore the **expected** outcome
for a semantic-only unit and is **not** a reason to re-fix. The decisive
evidence for this unit is the manual spot-check and the SEM-* finding inventory
in the Stage-1 analysis, not the control's mechanical result.

**Manual spot-checks (from Stage 4):** all five PASS — JOIN keys intact across
3 branches, CASE/GROUP BY order preserved, 8 columns per branch UNION-consistent,
no residual Teradata functions/operators, 10 `TODO(SME)` markers placed at
semantic-risk locations.

---

## 6. Sign-off checklist

A reviewer can sign off from this document alone. Confirm each item:

- [ ] **SEM-05 / S1 — SET vs MULTISET (CRITICAL).** Obtain the
      `CREATE TABLE staging.wrk_target` DDL. If the target is SET, each `UNION`
      branch must be rewritten as a separate
      `INSERT INTO staging.wrk_target (SELECT … EXCEPT SELECT * FROM staging.wrk_target)`.
      If MULTISET, confirm whether `UNION` (de-dup) or `UNION ALL` is intended.
- [ ] **SEM-05 / S2 — UNION vs UNION ALL.** Confirm the intended set-semantics
      for both set operators (lines 30, 60). If the original Teradata used
      separate INSERTs or `UNION ALL`, the current `UNION` is wrong.
- [ ] **SEM-02 / S3 — Latest-value key width.** Confirm the data type of
      `src.effective_dt` (DATE vs TIMESTAMP) and the max display width of each
      concatenated value column. Apply
      `TO_CHAR(effective_dt,'YYYY-MM-DD') || LPAD(val::VARCHAR,n,' ')` before
      `MAX` if the key is not already fixed-width and lexicographically sortable.
- [ ] **SEM-02 / S4 — MAX tie-break.** Confirm whether `effective_dt` is unique
      per `(airline_cd, flgt_no, flgt_dt)` group. If ties are possible, add a
      deterministic tie-breaker.
- [ ] **SEM-06 / S5 — Implicit string→date cast.** Confirm the format of
      `synthetic_sys_param.param_value` for `param_id = 'UPDATE_CUTOFF'`. Wrap
      with `TO_DATE(param_value, 'YYYY-MM-DD')` if it is not already an ISO
      date string.
- [ ] **S6 — operating_airline_cd width-3.** Confirm the
      `SUBSTR(...,11,3)` truncation on `operating_airline_cd` is intentional
      (airline codes are 2–3 chars) and not a conversion artifact.
- [ ] **DEF-05 — INSERT column count.** Obtain the target DDL and verify the
      8 SELECT expressions match `staging.wrk_target`'s column count and order.
- [ ] **No Teradata ground truth.** No `00_input/SFIssueSET.teradata.sql` was
      supplied. Every semantic inference above is flagged `TODO(SME)`. If a
      Teradata source is later provided, re-run Stage 1 to diff statement count,
      set operators, and column list against it.
- [ ] **Validation PASS confirmed.** Fixed file parses + compiles on Snowflake;
      control PASS is expected for a semantic-only unit.

---

*Report generated by Stage 5 (S2S Report agent). Semantic detail lives in
`06_explain/output/semantic_SFIssueSET.md`; this report does not duplicate it.*