# Validation report — SFissuetime

- **Fixed file:** `03_fix/output/SFissuetime_fixed.sql`
- **Buggy input (control):** `00_input/SFissuetime.sql`
- **Validator:** `04_validate/validate.py` (sqlglot parse + INSERT/SELECT column-count + duplicate-column + residual-Teradata scan + TODO(SME) count)

## Validator command (fixed file)

```
python3 04_validate/validate.py 03_fix/output/SFissuetime_fixed.sql
```

### Result: PASS

```
parse: 1 statement parsed
stmt 1: INSERT columns (60) == SELECT expressions (60), no duplicate INSERT columns
no residual Teradata constructs
TODO(SME) markers outstanding: 10
```

## Validator command (control — buggy input)

```
python3 04_validate/validate.py 00_input/SFissuetime.sql
```

### Result: PASS (60 = 60, no residual Teradata, 0 TODO markers)

**This control PASS is EXPECTED and is NOT a re-fix trigger.** The only defect in
this unit is a cosmetic DEF-06 alias issue, which is positional-inert — an
INSERT…SELECT alias name does not change which source column lands in which
target column; binding is by position regardless of the alias label. The
mechanical validator (parse / column-count / residual-Teradata) therefore PASSes
both the buggy input and the fixed file. Per the standing lesson in
`02_rules/06_lessons_learned.md` — *"A control PASS on a cosmetic-only defect is
expected"* — the decisive evidence is the manual spot-check, not the control's
mechanical result.

## Manual spot-check

- [x] 1 INSERT statement preserved; writes 60 columns to the target.
- [x] INSERT column order matches SELECT expression order (60 = 60).
- [x] No duplicate INSERT columns.
- [x] No residual Teradata constructs (`ZEROIFNULL`, `CONTAINS`, `MULTISET`,
      `(+)`, BTEQ dot-commands, `MINUS`, `SEL`, …).
- [x] `QUALIFY` (if any) kept as-is — not wrapped in a ROW_NUMBER subquery.
- [x] JOIN keys and CASE-branch order preserved exactly.
- [x] DEF-06 alias corrected; positional binding verified so no semantic drift.
- [x] 10 `TODO(SME)` markers carried forward for reviewer sign-off.

## Verdict

**PASS.** The fixed file is mechanically valid (parse, 60 = 60 column-count, no
residual Teradata) and passes the manual spot-check. The control PASS is
expected for this cosmetic-only (DEF-06) unit and is not a re-fix trigger.
Hand-back to s2s-fix is **not** required.