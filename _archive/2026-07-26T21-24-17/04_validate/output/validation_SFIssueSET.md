# Validation report — SFIssueSET

**Unit:** SFIssueSET
**Fixed file:** `03_fix/output/SFIssueSET_fixed.sql`
**Control file:** `00_input/SFIssueSET.sql`
**Mechanical verdict:** PASS

---

## Final SQL

### Mechanical validation (validator output)

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

All three INSERT statements parse as Snowflake via sqlglot. Each INSERT's
column list (8 columns) matches its SELECT expression count (8), with no
duplicate INSERT columns. No residual Teradata constructs (`ZEROIFNULL`,
`CONTAINS`, `MULTISET`, `(+)`, BTEQ dot-commands, `MINUS`, `SEL`, …) remain.

The 6 outstanding `TODO(SME)` markers are `INFO`-level assumptions flagged for
human review, not SQL defects — they do not affect the mechanical verdict.

### Manual spot-check

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
| SET-table dedup semantics (SEM-05) | PASS (manual) — fixed SQL enforces dedup per SEM-05 (see fix log); mechanical validator cannot verify without DDL, so this relies on the manual spot-check as decisive evidence |

**Manual verdict:** PASS

---

## Buggy input control

### Mechanical validation (control output)

```
PASS  parse: 1 statement(s) parsed as snowflake using sqlglot
PASS  no residual Teradata constructs
RESULT: PASS
```

The control **PASSES** the mechanical validator. This is **expected and not a
re-fix trigger**: the defect in `SFIssueSET` is purely semantic — a SEM-05
SET-table dedup violation. The mechanical validator has no DDL and cannot detect
SET-table duplicate-row violations, so a semantic-only defect correctly passes
the control. Per the s2s-validate policy, a passing control on a semantic-only
defect is the expected outcome; the manual spot-check above (not the control
run) is the decisive evidence for the fix.

---

## Summary

| Item | Verdict |
|---|---|
| Fixed file — mechanical | PASS |
| Fixed file — manual spot-check | PASS |
| Control (buggy input) | PASS (expected for SEM-* semantic-only defect) |
| **Overall** | **PASS** |

No hand-back to s2s-fix. The fixed file is mechanically valid Snowflake,
semantically faithful to the SEM-05 dedup intent, and free of residual Teradata
constructs. The 6 `TODO(SME)` markers are review items, not defects.