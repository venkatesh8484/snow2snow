# Analysis — `SFIssueSET.sql`

Three-branch staging load (marketing / operational / codeshare flight legs) into
`staging.wrk_target`. Parses cleanly, but has a **semantic** defect a parser
cannot see. Ground truth: `SFIssueSET.teradata.sql` (three independent INSERTs
into a **SET** table). Reference for the correct target form: `SFFixedSET.sql`.

## Findings

| Type | Where | Finding | Rule | Class |
|---|---|---|---|---|
| Semantic | `UNION` between the 3 branches | **SET-table dedup lost.** Teradata ran 3 *separate* INSERTs into a SET table (rows already present are dropped on insert). This file collapsed them into ONE INSERT with `UNION`, removing the "don't re-insert existing target rows" guarantee and adding cross-branch de-duplication that never existed. | SEM-05 | FIX |
| Semantic | `SUBSTR(MAX(effective_dt \|\| operating_flgt_no), 11, …)` | "Keep latest value" trick: `MAX()` over a concatenation must order by a fixed-width key. Bare `date \|\| number` is not width-stable, so `MAX` can pick the wrong row. | FN-LATEST | FIX |
| Syntax | whole file | Parses as Snowflake; no residual Teradata constructs. | — | (none) |

## Column / target note

Teradata selected 10 columns into `wrk_target_table` (incl. `dc_cpn_id`,
`bkkg_reference`); the Snowflake target `staging.wrk_target` is the redesigned
8-column table (confirmed by `SFFixedSET.sql`). The dropped columns are
**intentional** (target redesign), not a defect.

## Verdict

Not a parse problem — a **results** problem. The delivered file will re-insert
rows already staged and de-duplicate across branches. Fix: restore three
separate INSERTs, each `… EXCEPT SELECT * FROM staging.wrk_target`. This is
exactly the class of bug a `parse PASS` cannot catch — it needs the Teradata
comparison.
