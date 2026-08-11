---
mode: agent
description: "Stage 3 — produce corrected Snowflake SQL from the analysis + rules"
---

# /03-fix

Fix the file I name using its analysis in `01_analyze/output/` and **every**
rule file in `02_rules/` (read them all — that is how you learn).

Read `03_fix/PROMPT.md` first. Then write
`03_fix/output/<name>_fixed.sql`:

- Apply fixes in order: syntax/function/type (`SFX-*`/`FNX-*`/`DTX-*`) so it
  parses → defects (`DEF-*`) → semantics (`SEM-*`).
- Top-of-file `FIX LOG` comment block: one line per change, each citing a rule
  ID and the source line(s).
- Inline `-- TODO(SME): …` for every assumption.
- **Minimal diff** — preserve column order, JOIN keys, CASE-branch order, and
  the author's formatting/comments wherever a rule doesn't force a change.
- Keep `QUALIFY` as-is. Leave **no** residual Teradata construct.

Output must be a single executable Snowflake statement/batch, ready for Stage 4.
Do not invent fixes without a rule ID; if you hit an unlisted construct, stop
and add a proposed rule to the analysis.
