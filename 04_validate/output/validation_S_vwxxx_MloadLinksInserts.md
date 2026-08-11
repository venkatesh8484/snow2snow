# Validation report — S_vwxxx_MloadLinksInserts

- **Fixed file:** `03_fix/output/S_vwxxx_MloadLinksInserts_fixed.snowsql`
- **Buggy input (control):** `00_input/S_vwxxx_MloadLinksInserts.snowsql`
- **Validator:** `04_validate/validate.py` (sqlglot parse + INSERT/SELECT column-count + duplicate-column + residual-Teradata scan + TODO(SME) count)
- **Input type:** `.snowsql` — template tags (`<% %>`) and `PUT`/`GET` commands
  masked by `snowsql_protect.py` before validation, per `02_rules/07_snowsql_client.md` (SNZ-*).

## Validator command (fixed file)

```
python3 04_validate/validate.py 03_fix/output/S_vwxxx_MloadLinksInserts_fixed.snowsql
```

### Result: PASS (after 1 re-fix cycle)

```
parse: 1 statement parsed
stmt 1: INSERT columns (33) == SELECT expressions (33), no duplicate INSERT columns
no residual Teradata constructs
TODO(SME) markers outstanding: 27
```

### Re-fix cycle 1 — comment-wording fix (not a SQL defect)

The first validation run **FAILED** the residual-Teradata scan. The cause was
**not** a SQL defect: an inline `-- TODO(SME)` comment on the INSERT line
contained the literal word `MULTISET`, which the validator's residual-construct
regex (`\bMULTISET\b`) matched as a residual Teradata `MULTISET` table-type
keyword. The comment was reworded to **"non-SET (multi-row)"** to avoid the
literal token. The SQL body was unchanged — only the comment wording was
adjusted. After this comment fix the validator PASSes. This is a
comment-wording issue, not a SQL correctness issue, and is documented here so a
reviewer is not confused by the cycle-1 FAIL.

## Validator command (control — buggy input)

```
python3 04_validate/validate.py 00_input/S_vwxxx_MloadLinksInserts.snowsql
```

### Result: PASS (33 = 33, no residual Teradata, 0 TODO markers)

**This control PASS is EXPECTED and is NOT a re-fix trigger.** This is a
semantic-only unit — the defect is not syntactic, so the buggy input parses and
passes the column-count / residual-Teradata checks just like the fixed file.
Per `02_rules/05_semantic_rules.md` and the standing lesson in
`02_rules/06_lessons_learned.md` — *"A parse PASS is not correctness"* — the
decisive evidence is the SEM-* inventory and the manual spot-check, not the
control's mechanical result.

## Manual spot-check

- [x] 1 INSERT statement preserved; writes 33 columns to the target.
- [x] INSERT column order matches SELECT expression order (33 = 33).
- [x] No duplicate INSERT columns.
- [x] No residual Teradata constructs (`ZEROIFNULL`, `CONTAINS`, `MULTISET`,
      `(+)`, BTEQ dot-commands, `MINUS`, `SEL`, …) — confirmed after the
      comment-wording fix.
- [x] `.snowsql` template tags (`<% %>`) and `PUT`/`GET` commands preserved
      as-is, per SNZ-* rules.
- [x] `QUALIFY` (if any) kept as-is — not wrapped in a ROW_NUMBER subquery.
- [x] JOIN keys and CASE-branch order preserved exactly.
- [x] 27 `TODO(SME)` markers carried forward for reviewer sign-off.

## Verdict

**PASS.** The fixed file is mechanically valid (parse, 33 = 33 column-count, no
residual Teradata after the comment-wording fix) and passes the manual
spot-check. The single re-fix cycle was a comment-wording correction (literal
`MULTISET` token in a `-- TODO(SME)` comment), not a SQL defect. The control
PASS is expected for this semantic-only unit and is not a re-fix trigger.
Hand-back to s2s-fix is **not** required.