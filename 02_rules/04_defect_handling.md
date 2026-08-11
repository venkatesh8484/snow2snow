# Defect handling policy

The buggy input contains not just dialect leftovers but genuine bugs (bad
find/replace, hand edits, truncated copies). The fixer must neither silently
propagate nor silently swallow them.

## Policy

| ID | Defect class | Action |
|---|---|---|
| DEF-01 | Duplicate column in INSERT list (same name twice) | Remove the duplicate on **both** sides (INSERT list and matching SELECT position) so positions stay aligned. Log. |
| DEF-02 | Missing whitespace / typo breaking a keyword (`ASalias`, `SELECTa`) | Repair to the obvious intent. Log. |
| DEF-03 | Unbalanced parentheses | Rebuild the expression to the intent shown by sibling expressions; if intent is unclear → SME. Log. |
| DEF-04 | Malformed function call (e.g. `CAST((col, 0, 999) AS BIGINT)`) | Infer intent from the argument pattern (here: `COALESCE(col, 0)` guarded cast). Repair, mark `TODO(SME)`. Log. |
| DEF-05 | INSERT column count ≠ SELECT expression count | Align by name to find the missing/extra position. Missing expression → synthesize the most plausible one from sibling column patterns, mark `TODO(SME)`. Extra → SME. Log. |
| DEF-06 | Alias ≠ target column name | Not a defect (INSERT…SELECT is positional). Normalize alias to the target name for readability. |
| DEF-07 | Wrong column referenced (copy-paste from sibling) | Only fix if the Teradata original disproves the reference; otherwise flag → SME. Never guess a column swap. |

## Fix log format

Every repair appears in a comment block at the top of the fixed file:

```sql
-- FIX LOG (issues repaired during remediation)
-- [SFX-01] line 443: PERIOD CONTAINS -> BETWEEN on split columns
-- [FNX-01] line 30 : ZEROIFNULL(x) -> COALESCE(x, 0)
-- [DEF-01] line 72-73: duplicate column `sac_cd` removed from INSERT and SELECT
-- ...
```

Rule of thumb: **the fixed file must be honest** — anyone diffing input vs
output can trace every change to a rule ID or a fix-log entry.
