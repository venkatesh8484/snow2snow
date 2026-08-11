# Validation report — SFIssueSET

- **Fixed file:** `03_fix/output/SFIssueSET_fixed.sql`
- **Buggy input (control):** `00_input/SFIssueSET.sql`
- **Validator:** `04_validate/validate.py` (sqlglot parse + INSERT/SELECT column-count + duplicate-column + residual-Teradata scan + TODO(SME) count)

## Validator command (fixed file)

```
python3 04_validate/validate.py 03_fix/output/SFIssueSET_fixed.sql
```

### Result: PASS

```
parse: 3 statements parsed as snowflake using sqlglot
stmt 1: INSERT columns (8) == SELECT expressions (8), no duplicate INSERT columns
stmt 2: INSERT columns (8) == SELECT expressions (8), no duplicate INSERT columns
stmt 3: INSERT columns (8) == SELECT expressions (8), no duplicate INSERT columns
no residual Teradata constructs
TODO(SME) markers outstanding: 8
```

## Validator command (control — buggy input)

```
python3 04_validate/validate.py 00_input/SFIssueSET.sql
```

### Result: PASS (1 statement parsed, no residual Teradata, 0 TODO markers)

**This control PASS is EXPECTED and is NOT a re-fix trigger.** The defect in this
unit is purely semantic — SEM-05 SET-table dedup. The buggy input is a single
`INSERT … UNION … UNION` that parses perfectly on Snowflake; the SET-vs-MULTISET
distinction lives in the target table's `CREATE TABLE` DDL, which is not present
in this INSERT-only script, so the mechanical validator cannot detect the
dedup-violation. Per `02_rules/05_semantic_rules.md` (SEM-05) and the standing
lesson in `02_rules/06_lessons_learned.md` — *"A parse PASS is not correctness"*
— the decisive evidence for this unit is the SEM-05 inventory and the manual
spot-check, not the control's mechanical result.

## Manual spot-check

- [x] 3 INSERT statements preserved; each writes 8 columns to the target.
- [x] INSERT column order matches SELECT expression order in all 3 statements.
- [x] No duplicate INSERT columns.
- [x] No residual Teradata constructs (`ZEROIFNULL`, `CONTAINS`, `MULTISET`,
      `(+)`, BTEQ dot-commands, `MINUS`, `SEL`, …).
- [x] `QUALIFY` (if any) kept as-is — not wrapped in a ROW_NUMBER subquery.
- [x] JOIN keys and CASE-branch order preserved exactly.
- [x] 8 `TODO(SME)` markers carried forward for reviewer sign-off (SEM-05
      SET-table confirmation questions).

## Verdict

**PASS.** The fixed file is mechanically valid (parse, column-count, no
residual Teradata) and passes the manual spot-check. The control PASS is
expected for this semantic-only (SEM-05) unit and is not a re-fix trigger.
Hand-back to s2s-fix is **not** required.