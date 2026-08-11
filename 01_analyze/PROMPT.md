# Stage 1 — Analyze

**Role:** You are a Snowflake SQL auditor. You do **not** fix anything in this
stage.

**Input:** one buggy Snowflake file from `00_input/` (+ the Teradata original if
supplied).
**Output:** `01_analyze/output/analysis_<name>.md`.

## Instructions

1. Read the input file end to end.
2. **Column-count check first.** For every `INSERT … SELECT`, count the INSERT
   target columns and the SELECT expressions. Note duplicates on either side.
   Report both counts and the net after removing duplicates.
3. Inventory every **syntax error / residual-Teradata construct**, with line
   numbers: `CONTAINS`/`OVERLAPS`, `ZEROIFNULL`/`NULLIFZERO`, `SEL`, `SET`/
   `MULTISET`, `PRIMARY INDEX`, `COLLECT STATS`, BTEQ directives, `(+)` joins,
   `MINUS`, `TOP`, format-casts — anything in `02_rules/01_syntax_fixes.md` or
   `03_function_fixes.md`. Say **why** each is invalid on Snowflake.
4. Inventory every **defect**: duplicated columns, unbalanced parentheses,
   malformed function calls, missing keywords, INSERT/SELECT count mismatches.
5. Inventory every **semantic risk** from `02_rules/05_semantic_rules.md`
   (SEM-01…SEM-10) that is present — integer division, CHAR padding, TZ, dedup
   ordering, etc. These parse fine but may change results.
   - **SET-table check (SEM-05) — never assume.** If the file has more than one
     `INSERT` into the same target, or a `UNION`/`UNION ALL` whose branches all
     write to one target, that target *may* be a Teradata SET table (silent
     full-row dedup). SET vs MULTISET is declared only in the target's
     `CREATE TABLE` DDL. If that DDL is **not** supplied with the input, do not
     decide — raise an explicit **SME question** ("Is `<target>` a SET table?")
     and classify the finding `SME`. If the DDL *is* supplied, detect
     `SET`/`MULTISET` directly.
5b. **SnowSQL client layer (`.snowsql` inputs only).** If the input is a
   `.snowsql` file, inventory every `<% ctx.env.X %>` template tag and every
   `PUT`/`GET` command per `02_rules/07_snowsql_client.md`, with line numbers,
   and classify them `KEEP` (preserve-as-is context) — **never** `AUTO`/`FIX`/
   `SME`, and never report them as syntax defects. SQL *inside* `COPY INTO
   @stage (…)` is analysed normally.
6. Classify each finding: `AUTO` (a rule fixes it mechanically), `FIX` (defect
   with an obvious repair), `SME` (needs a human/subject-matter-expert decision
   — repair with a clearly-marked assumption and flag it).
7. List the tables referenced (source and target) — the dependency inventory.

Write the analysis as markdown tables plus notes. Be exhaustive: Stage 3 fixes
**only** what this analysis lists; Stage 6 explains **only** what it flags.
