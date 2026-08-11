---
name: s2s-explain
description: Stage 6 — write the editable semantic explanation and embed it into the final SQL as comments.
tools: ['search', 'codebase', 'edit', 'runCommands', 'runTasks']
handoffs:
  - label: Open interactive report
    agent: agent
    prompt: Open report.html and summarize the semantic findings for this file.
    send: false
---
# S2S Explain agent

You explain *meaning*, not syntax. Read `06_explain/PROMPT.md` and
`02_rules/05_semantic_rules.md`. If an **optional** Teradata original is present
in `00_input/` (`<name>.teradata.sql`), use it as ground truth; if it is absent,
proceed without it and **never** search outside the workspace for it.

1. Write `06_explain/output/semantic_<name>.md` with these sections: Purpose ·
   Clause-by-clause walk-through · Semantic checks table (every `SEM-*`: present?
   corrected how? equivalent to Teradata?) · Divergences · Open SME questions ·
   **Inline anchors** (a fenced ```anchors``` block of `MATCH text :: note` lines,
   each using a short literal that appears verbatim in the fixed SQL).
2. This markdown is **editable** — the reviewer will enrich it. Then embed it as
   comments into the final SQL, using the VS Code task **S2S: Annotate SQL with
   semantic comments** (`runTasks`) or:
   ```
   python3 06_explain/annotate.py \
       --sql 03_fix/output/<name>_fixed.sql \
       --md  06_explain/output/semantic_<name>.md \
       --out 03_fix/output/<name>_final.sql
   ```
   Purpose + Open SME questions become a `SEMANTIC EXPLANATION` header block; each
   anchor note becomes a `-- SEM ▸` comment above its clause. `<name>_fixed.sql`
   stays pure; `<name>_final.sql` is the reviewer-facing deliverable.
3. Validate `<name>_final.sql` (comments don't affect parsing).
4. **Refresh the report by running the generator** — `python3
   05_report/build_report.py` (or the task **S2S: Refresh interactive report**).
   Never hand-write `report.html`; the generator produces the rich interactive
   report from the stage outputs.
