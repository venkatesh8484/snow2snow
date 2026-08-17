# Snowflake → Snowflake Remediation Pipeline

An [Interpretable Context Methodology](https://arxiv.org/abs/2603.16021) pipeline —
a sibling to `../teradata2snowflake/`. Same idea (numbered folders = stages,
markdown carries the prompts and rules, a local script does mechanical checks),
but a **different job**.

## What problem this solves

Another team already ran a Teradata → Snowflake conversion. The output is
*nominally* Snowflake SQL, but it has a lot of issues:

- **Syntactic errors** — constructs that don't parse or don't run on Snowflake
  (residual Teradata functions like `ZEROIFNULL`, PERIOD `CONTAINS`, malformed
  casts, unbalanced parentheses, duplicated columns, INSERT/SELECT count
  mismatches).
- **Semantic drift** — statements that *parse* but no longer mean what the
  original Teradata logic meant (silent truncation, NULL handling, timezone,
  dedup semantics).

This pipeline takes the buggy Snowflake script as **input** and produces a
**clean, executable, semantically-faithful Snowflake script** as output — plus,
for every script, a written **semantic explanation** and an **interactive HTML
report** so a reviewer can sign off with confidence.

> The original Teradata source (when available) is used as *ground truth* for
> the semantic check — not re-converted. See `02_rules/05_semantic_rules.md`.

## Folder structure

```
snowflake2snowflake/
├── 00_input/        Buggy Snowflake .sql files (already-converted, needs fixing)
├── 01_analyze/      Stage 1 — inventory syntax errors, defects & semantic risks
├── 02_rules/        Knowledge base — ALL fix + semantic rules (editable markdown)
├── 03_fix/          Stage 3 — produce corrected Snowflake SQL applying 02_rules
├── 04_validate/     Stage 4 — mechanical checks (validate.py, sqlglot)
├── 05_report/       Stage 5 — remediation report per file
├── 06_explain/      Stage 6 — editable SEMANTIC explanation + annotate.py
│                    (embeds the explanation as comments in the final SQL)
├── 07_review/       Stage 7 — reviewer comments on the fixed SQL, per unit
│                    (review_<name>.md; written from report.html's Review tab)
├── _archive/        Previous runs' stage outputs, moved here by
│                    05_report/archive_outputs.py before each re-run (timestamped)
├── report.html      Interactive report (GENERATED — do not hand-edit)
│                    built by 05_report/build_report.py from the stage outputs
├── COPILOT_SETUP.md How to run it in Copilot (agents + prompts) + troubleshooting
├── .github/         Copilot config:
│   ├── copilot-instructions.md   (auto-loaded rules)
│   ├── prompts/*.prompt.md       (/01-analyze … /06-explain slash commands)
│   └── agents/*.agent.md         (s2s-remediate + 5 stage agents)
└── .vscode/         VS Code tasks, settings, recommended extensions
```

## The generic framework solution runs in GitHub Copilot / VS Code

This repo is set up to be driven from **GitHub Copilot Chat in VS Code** — no
bespoke app, no redeploy. Two ways to run it, both defined under `.github/`:

- **Custom agents** (`.github/agents/*.agent.md`) — pick a persona from the chat
  agent dropdown. **`s2s-remediate`** orchestrates all stages via subagents; the
  five stage agents (`s2s-analyze` … `s2s-explain`) chain via handoff buttons.
  This is the agentic flow.
- **Prompt files** (`.github/prompts/*.prompt.md`) — `/01-analyze` … `/06-explain`
  slash commands for stepping through stages manually.

The rules are Copilot *context* (`.github/copilot-instructions.md` + `02_rules/`),
and the validator/annotator run as *VS Code tasks*.

> **Setup + troubleshooting (important):** prompt files and agents are discovered
> only at the **workspace-root `.github/`** folder — so open **this**
> `snowflake2snowflake` folder as the VS Code workspace (not the parent). Full
> steps, including "the `/` menu is empty" fixes, are in **`COPILOT_SETUP.md`**.

1. Open **this folder** in VS Code with the **GitHub Copilot** and **GitHub
   Copilot Chat** extensions installed (see `.vscode/extensions.json`). The
   Snowflake extension is *optional* — only for executing the fixed SQL against a
   live account; the pipeline's validation uses sqlglot offline.
2. Drop a buggy Snowflake `.sql` file into `00_input/`.
3. **Re-running? Archive the old outputs first** so the report reflects only the
   current `00_input/` files — stale artifacts from removed/renamed inputs
   otherwise linger and get re-included:

   ```
   python3 05_report/archive_outputs.py <file-base>   # just that unit
   python3 05_report/archive_outputs.py               # reset ALL units
   ```

   The orchestrator and the `s2s-analyze` stage do this automatically (step 0);
   run it by hand when stepping through stages manually. Nothing is deleted —
   files move to `_archive/<timestamp>/`, and `00_input/`, `02_rules/` and
   `07_review/` are never touched.
4. Pick the **s2s-remediate** agent and say *"remediate `00_input/<file>` — run
   all stages"*, **or** run the stage prompts in order (type `/` to pick them):

   ```
   /01-analyze   00_input/<file>.sql
   /03-fix       00_input/<file>.sql
   /04-validate  03_fix/output/<file>_fixed.sql
   /05-report    <file>
   /06-explain   <file>
   ```

   `.github/copilot-instructions.md` is loaded automatically on every Copilot
   request, so the agent always knows the ICM rules and reads `02_rules/`
   before fixing. Review the output after each stage.
5. Run **Terminal → Run Task → S2S: Validate fixed SQL** (or the task auto-runs
   from `/04-validate`) to get the mechanical PASS/FAIL.
6. **Enrich the semantic explanation** (`06_explain/output/semantic_<file>.md`)
   as a reviewer — it's plain markdown — then run **Terminal → Run Task → S2S:
   Annotate SQL with semantic comments**. This embeds the explanation as
   comments inside `03_fix/output/<file>_final.sql`. Re-run any time you edit the
   markdown; it's idempotent.
7. **Refresh the interactive report** after every remediation run by running
   **Terminal → Run Task → S2S: Refresh interactive report** (or
   `python3 05_report/build_report.py`). This is mandatory and keeps
   `report.html` aligned with the latest stage outputs. `report.html` is
   produced **only** by this generator — never hand-authored — so every run
   looks the same. To change how it looks, edit `build_report.py`.
8. Open `report.html` in a browser: summary cards, a stage-completion matrix
   across all units, and a per-unit sidebar with Overview / Comparison / Fixes /
   Semantic / Validation / Review-comments sub-tabs. To enrich the semantic
   content, edit `06_explain/output/semantic_<file>.md` and re-run the generator.
   The **Review comments** tab lets a reviewer type feedback on the fixed SQL and
   either **Save comments** (to `07_review/output/review_<file>.md`) or
   **Re-remediate** to trigger the `s2s-remediate` orchestrator with those
   comments as reviewer guidance — served via `05_report/serve_report.py`.

### Two SQL outputs

| File | What |
|---|---|
| `03_fix/output/<file>_fixed.sql` | The pure corrected statement + FIX LOG |
| `03_fix/output/<file>_final.sql` | The reviewer-facing deliverable — the fixed statement **with the semantic explanation embedded as comments** |

## How the agent learns

`02_rules/` is the single source of truth. To change behavior, **edit a
markdown file** — no code.

| File | Contains |
|---|---|
| `01_syntax_fixes.md` | Snowflake syntax-error fixes & residual-Teradata constructs |
| `02_datatype_rules.md` | Snowflake data-type pitfalls (padding, NUMBER, TZ) |
| `03_function_fixes.md` | Legacy/invalid function → Snowflake equivalent |
| `04_defect_handling.md` | Policy for defects found in the buggy source SQL |
| `05_semantic_rules.md` | **Semantic-equivalence policy + explanation format** |
| `06_lessons_learned.md` | Append-only log; the agent adds an entry every run |

Corrections you make to fixed output should be captured as new rules or lessons
so the next run gets it right automatically.
