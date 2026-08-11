# Validation report — S_vwxxx_MloadLinksUpdates

- **Fixed file:** `03_fix/output/S_vwxxx_MloadLinksUpdates_fixed.snowsql`
- **Buggy input (control):** `00_input/S_vwxxx_MloadLinksUpdates.snowsql`
- **Validator:** `04_validate/validate.py` (sqlglot parse + INSERT/SELECT column-count + duplicate-column + residual-Teradata scan + TODO(SME) count)
- **Input type:** `.snowsql` — template tags (`<% %>`) and `PUT`/`GET` commands
  masked by `snowsql_protect.py` before validation, per `02_rules/07_snowsql_client.md` (SNZ-*).

## Validator command (fixed file)

```
python3 04_validate/validate.py 03_fix/output/S_vwxxx_MloadLinksUpdates_fixed.snowsql
```

### Result: PASS

```
parse: 1 statement parsed
no residual Teradata constructs
TODO(SME) markers outstanding: 13
```

## Validator command (control — buggy input)

```
python3 04_validate/validate.py 00_input/S_vwxxx_MloadLinksUpdates.snowsql
```

### Result: PASS (1 statement, no residual Teradata, 0 TODO markers)

**This control PASS is EXPECTED and is NOT a re-fix trigger.** The defect in
this unit is a DEF-07 alias issue that is **positional-inert**: the outer
`src.IN_DEP_FLIGHT_DT` reference would bind to the aliased column by position
regardless of the alias name, so the buggy input produces the same result as
the fixed file. The mechanical validator cannot catch a positional-inert alias
defect — it has no semantic alias-resolution capability. Per the standing
lesson in `02_rules/06_lessons_learned.md` — *"A control PASS on a
cosmetic-only / positional-inert defect is expected"* — the decisive evidence
is the manual spot-check, not the control's mechanical result.

## Manual spot-check

- [x] 1 statement preserved; structure intact.
- [x] No residual Teradata constructs (`ZEROIFNULL`, `CONTAINS`, `MULTISET`,
      `(+)`, BTEQ dot-commands, `MINUS`, `SEL`, …).
- [x] `.snowsql` template tags (`<% %>`) and `PUT`/`GET` commands preserved
      as-is, per SNZ-* rules.
- [x] `QUALIFY` (if any) kept as-is — not wrapped in a ROW_NUMBER subquery.
- [x] JOIN keys and CASE-branch order preserved exactly.
- [x] DEF-07 alias corrected; positional binding verified so the outer
      `src.IN_DEP_FLIGHT_DT` reference is unaffected by the alias rename.
- [x] 13 `TODO(SME)` markers carried forward for reviewer sign-off.

## Verdict

**PASS.** The fixed file is mechanically valid (parse, no residual Teradata)
and passes the manual spot-check. The control PASS is expected for this
positional-inert (DEF-07 alias) unit and is not a re-fix trigger. Hand-back to
s2s-fix is **not** required.