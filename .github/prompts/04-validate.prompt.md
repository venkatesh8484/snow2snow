---
mode: agent
description: "Stage 4 — mechanical validation with sqlglot (script first)"
---

# /04-validate

Validate the fixed file `03_fix/output/<name>_fixed.sql`.

Read `04_validate/PROMPT.md` first. Then:

0. Ensure deps once: `python3 bootstrap.py` (idempotent — prints `deps OK` and
   returns instantly if already installed). Never `pip install sqlglot` directly.
1. Run the validator (VS Code task **S2S: Validate fixed SQL**, or in a terminal
   `python3 04_validate/validate.py 03_fix/output/<name>_fixed.sql`).
2. Run it on the buggy input `00_input/<name>.sql` as a **control** — it must
   fail. Include that output as evidence the issues were real.
3. Add a manual spot-check: JOIN keys intact, CASE branches in order, no dropped
   columns, no residual Teradata function/operator.
4. Write `04_validate/output/validation_<name>.md` with PASS/FAIL per check.

If the fixed file fails, return to `/03-fix`. **Never** edit the validator to
make it pass.
