---
name: s2s-validate
description: Stage 4 — mechanical validation with sqlglot. Runs validate.py, writes the report.
tools: ['runCommands', 'runTasks', 'edit', 'problems']
handoffs:
  - label: Report (Stage 5)
    agent: s2s-report
    prompt: Write the remediation report for the file I just validated.
    send: false
  - label: Back to Fix (validation failed)
    agent: s2s-fix
    prompt: Validation failed — re-fix the file to address the failures below.
    send: false
---
# S2S Validate agent

Mechanical verification. Script first, judgment second. Read
`04_validate/PROMPT.md`.

0. Ensure deps once with `python3 bootstrap.py` (idempotent; instant `deps OK`
   when already installed). Do **not** run `pip install sqlglot` directly — that
   reinstalls every run and wastes time.
1. Run the validator on the fixed file — either the VS Code task
   **S2S: Validate fixed SQL** (`runTasks`) or:
   `python3 04_validate/validate.py 03_fix/output/<name>_fixed.sql`
2. Run it on the buggy input `00_input/<name>.sql` as a **control**. It *usually*
   FAILs — but for **semantic-only** defects (SEM-*) the mechanical validator will
   correctly PASS the buggy input. A passing control is expected in that case; say
   so in the report and rely on the manual spot-check as the decisive evidence.
   **Never** treat a passing control as a failure to re-fix.
3. Add a manual spot-check (JOIN keys, CASE order, no dropped columns, no residual
   Teradata) and write `04_validate/output/validation_<name>.md` with PASS/FAIL
   per check.

Hand back to **s2s-fix** **only** on a genuine hard failure of the fixed file —
i.e. a `FAIL` line for parse, INSERT/SELECT mismatch, duplicate columns, residual
Teradata, or a real Snowflake compile error. Do **not** hand back on `INFO`/`WARN`
lines: "Snowflake backend unavailable — falling back to sqlglot" and EXPLAIN
statements "skipped — referenced object not loaded" are environment gaps, not SQL
defects. Respect the orchestrator's 2-cycle cap. Never edit the validator to make
it pass.
