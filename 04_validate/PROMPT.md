# Stage 4 — Validate

**Role:** mechanical verification. Script first, judgment second.

**Input:** `03_fix/output/<name>_fixed.sql` (and, for a control, the buggy
`00_input/<name>.sql`).
**Output:** `04_validate/output/validation_<name>.md`.

## Instructions

1. Run the local script (no AI needed — ICM principle):

   ```
   python3 04_validate/validate.py 03_fix/output/<name>_fixed.sql
   ```

   It parses the file with `sqlglot` (Snowflake dialect) and, for INSERT…SELECT,
   compares target column count vs SELECT expression count, checks for duplicate
   INSERT columns, and counts remaining `TODO(SME)` markers.

2. **Control run** — run it on the buggy input too. It should FAIL to parse (or
   mismatch counts); include that as evidence the issues were real:

   ```
   python3 04_validate/validate.py 00_input/<name>.sql
   ```

3. If the fixed file fails, return to Stage 3, fix, re-run. Do **not** hand-edit
   the validator to make it pass.
4. Add a manual spot-check (JOIN keys intact, CASE branches preserved in order,
   no dropped columns, no residual Teradata function/operator) and write the
   validation report: PASS/FAIL per check, with details.

   Use these exact section headings so the generated report stays consistent:
   `## Final SQL` for the fixed-file result and `## Buggy input control` for the
   control run.
