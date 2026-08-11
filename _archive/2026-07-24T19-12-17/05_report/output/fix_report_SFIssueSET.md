# Fix report — `SFIssueSET`

## Outcome
The earlier automated run changed **0 SQL lines** (it only added a comment
header) and reported PASS — a false pass, because the real defect is semantic and
a parser cannot see it. This is the corrected remediation.

## Real issues repaired

| Rule | Issue | Repair |
|---|---|---|
| SEM-05 | SET-table dedup lost: 3 independent Teradata INSERTs (drop rows already in target) were collapsed into ONE `INSERT … UNION …`, which re-inserts existing rows and de-duplicates across branches | Restored 3 separate `INSERT INTO staging.wrk_target ( … EXCEPT SELECT * FROM staging.wrk_target )` |
| FN-LATEST | `SUBSTR(MAX(effective_dt \|\| operating_flgt_no), 11, …)` used a width-unstable key, so `MAX` could pick the wrong "latest" row | Wrapped as `TO_CHAR(effective_dt,'YYYY-MM-DD') \|\| LPAD(operating_flgt_no::VARCHAR,5,' ')` |

## Why the first pass missed it
`validate.py`/sqlglot only proves the file *parses*; `UNION` parses perfectly.
The catch requires comparing against `SFIssueSET.teradata.sql` — which the run
did not do. See the lesson added to `02_rules/06_lessons_learned.md`.

## Validation
`validate.py`: parse **PASS** (3 statements), no residual Teradata. Behavioural
equivalence still needs a data test against a staged copy (the `EXCEPT` guard and
row multiplicity).
