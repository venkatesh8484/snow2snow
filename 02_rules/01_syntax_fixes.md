# Syntax fixes (statement-level)

Residual Teradata constructs and structural errors that were left in the
"already-converted" Snowflake script. These break parsing or execution on
Snowflake and must be fixed in Stage 3.

| ID | IN (buggy Snowflake) | OUT (correct Snowflake) | Notes |
|---|---|---|---|
| SFX-01 | `<period_col> CONTAINS <date>` | `<date> BETWEEN <period_col>_start_dt AND <period_col>_end_dt` | `CONTAINS` is a Teradata PERIOD operator; **invalid in Snowflake** (parse error). **Assumption:** the DDL migration split each PERIOD column `x_pd` into `x_start_dt`/`x_end_dt`. Emit `TODO(SME)` to confirm names. |
| SFX-02 | `<period_col> OVERLAPS PERIOD(...)` | Explicit range predicates on split start/end columns | Same assumption as SFX-01. |
| SFX-03 | `QUALIFY ROW_NUMBER() OVER (...) = 1` | Keep as-is | Snowflake supports `QUALIFY` natively — do **not** rewrite as a wrapped ROW_NUMBER subquery. Minimal diff. |
| SFX-04 | `SEL ...` | `SELECT ...` | Teradata shorthand left in; invalid in Snowflake. |
| SFX-05 | `CREATE SET/MULTISET TABLE` | `CREATE TABLE` | `SET`/`MULTISET` keywords are Teradata-only. SET-table dedup semantics do NOT carry over — see SEM-05. |
| SFX-06 | `PRIMARY INDEX (...)`, `UNIQUE PRIMARY INDEX (...)` | Remove; consider `CLUSTER BY (...)` for very large tables | Snowflake has no PI; leaving it is a parse error. |
| SFX-07 | `COLLECT STATS` / `COLLECT STATISTICS` / `HELP STATS` | Remove | Snowflake auto-collects; statements are invalid. |
| SFX-08 | BTEQ directives (`.IF ERRORCODE`, `.LABEL`, `.QUIT`, `.LOGON`, `.RUN`) | Remove; move control flow to orchestration (Snowflake Scripting / tasks) | Not SQL — a `.sql` file containing these will not run. |
| SFX-09 | `LOCKING ROW FOR ACCESS`, `LOCKING TABLE ... FOR ACCESS` | Remove | No Snowflake equivalent needed. |
| SFX-10 | Old-style non-ANSI joins (comma joins, `WHERE a.x = b.x (+)`) | ANSI `JOIN ... ON` | `(+)` outer-join syntax is invalid in Snowflake. |
| SFX-11 | Unbalanced parentheses / truncated expression | Rebuild to the evident intent (see DEF-03) | Common when a hand-edit or bad find/replace clipped an expression. |
| SFX-12 | Trailing comma before `FROM`, or missing comma between two SELECT items | Fix the list punctuation | Parse error; align against the INSERT target list to find which. |
| SFX-13 | `TOP n` | `LIMIT n` or `QUALIFY ROW_NUMBER() ... <= n` | `SELECT TOP n` is not Snowflake syntax. |
| SFX-14 | `MINUS` set operator | `EXCEPT` | `MINUS` is not a Snowflake keyword. |
| SFX-15 | `CAST(x AS <type> FORMAT '...')` | `TO_DATE`/`TO_CHAR`/`TO_NUMBER(x, '...')` | Teradata `FORMAT` phrase is invalid in a Snowflake CAST. See FNX-08. |

**Order of operations:** fix SFX/FNX/DTX first so the file parses, then run the
column-count and defect checks (DEF-*), then the semantic pass (SEM-*).
