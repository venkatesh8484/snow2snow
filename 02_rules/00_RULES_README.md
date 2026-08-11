# Remediation rules — knowledge base

These files are the **entire** brain of the Snowflake→Snowflake pipeline. The
Stage-3 (fix) and Stage-6 (explain) agents read all of them, every run. To
change behavior, edit these files — nothing else.

Conventions:

- **IN** = the buggy input Snowflake form. **OUT** = the corrected Snowflake form.
- **TD** = the original Teradata form (semantic ground truth), when supplied.
- Rule IDs (`SFX-01`, `FNX-03`, `SEM-02`, `DEF-01`, …) are cited in fix logs,
  reports, and the HTML. Keep IDs stable; append new rules, do not renumber.
- Two distinct failure modes are handled separately:
  - **Syntactic** (`SFX-*`, `FNX-*`, `DTX-*`, `DEF-*`) — the script does not
    parse / run, or is an outright bug. Stage 3 fixes these.
  - **Semantic** (`SEM-*`) — the script parses but its *meaning* has drifted
    from the Teradata original. Stage 3 corrects; Stage 6 **explains**.
  - **SnowSQL client layer** (`SNZ-*`, `07_snowsql_client.md`) — `.snowsql`
    inputs only. `<% %>` template tags and `PUT`/`GET` commands are **preserved
    as-is** (never rewritten), masked only so the validator can parse the real
    SQL. See that file for the analyze/fix/report contract.
- If a fix requires an assumption about the migrated data model, the rule states
  the assumption and the fixer emits a `-- TODO(SME)` marker at the point of use.
- The output must be **honest**: every difference between input and output must
  trace to a rule ID or a fix-log entry.
