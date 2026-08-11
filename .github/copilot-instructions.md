# Copilot instructions — snowflake2snowflake ICM pipeline

You are the agent driving a **Snowflake → Snowflake remediation** pipeline built
on the Interpretable Context Methodology (ICM). VS Code loads this file
automatically on every Copilot Chat request, so these rules always apply.

## What this repo does

Input = Snowflake `.sql` that another team produced by converting Teradata, but
which is **buggy** (does not parse/run, or has drifted semantically). Output =
clean, executable, semantically-faithful Snowflake SQL, plus a written semantic
explanation and an interactive HTML report.

## Stage 0 — dependencies (install ONCE, never reinstall per run)

The validator needs `sqlglot`, which is slow to download. **Do not** run a bare
`pip install` at the start of every run — that is what caused the repeated
delay. Instead run the **idempotent** bootstrap, which checks whether the deps
already import and only installs when something is missing:

```
python3 bootstrap.py        # or the VS Code task "S2S: Setup — install deps (run once)"
```

When the packages are already present it prints `deps OK` and returns in
milliseconds, so it is safe to leave at the front of a run. **Never** call
`pip install sqlglot …` directly — always go through `bootstrap.py`, and if it
prints `deps OK`, do not install anything. Declared deps live in
`requirements.txt`.

## The rules live in markdown — read them, every run

Before fixing or explaining anything, **read every file in `02_rules/`**. It is
the single source of truth:

- `01_syntax_fixes.md` — `SFX-*` residual-Teradata / structural fixes
- `02_datatype_rules.md` — `DTX-*` type pitfalls
- `03_function_fixes.md` — `FNX-*` legacy-function fixes
- `04_defect_handling.md` — `DEF-*` defect policy
- `05_semantic_rules.md` — `SEM-*` semantic-equivalence policy + the Stage-6
  explanation contract
- `06_lessons_learned.md` — append-only lessons (read before, append after)
- `07_snowsql_client.md` — `SNZ-*` SnowSQL client layer (`.snowsql` inputs):
  `<% %>` template tags and `PUT`/`GET` commands are **preserved as-is**, never
  rewritten. Validation masks them via `snowsql_protect.py`.

Never invent a fix that isn't backed by a rule ID. If you meet an unlisted
construct, stop and propose a new rule in the analysis for human review.

## Stages (run in order; review between each)

Use the prompt files in `.github/prompts/` (`/01-analyze`, `/03-fix`,
`/04-validate`, `/05-report`, `/06-explain`).

1. **01-analyze** → `01_analyze/output/analysis_<name>.md`. No fixing. Count
   INSERT vs SELECT columns first. Inventory syntax errors, defects, and SEM-*
   risks with line numbers. Classify AUTO / FIX / SME.
2. **03-fix** → `03_fix/output/<name>_fixed.sql`. Apply rules in order:
   syntax/function/type → defects → semantics. Top-of-file `FIX LOG` citing a
   rule ID + source line for every change. Inline `-- TODO(SME)` for every
   assumption. **Minimal diff.**
3. **04-validate** → `04_validate/output/validation_<name>.md`. Run the VS Code
   task **S2S: Validate fixed SQL** (or `python3 04_validate/validate.py <file>`).
   Also run it on the buggy input as a control (it must fail). Never edit the
   validator to pass.
4. **05-report** → `05_report/output/fix_report_<name>.md` + append a lesson to
   `02_rules/06_lessons_learned.md`.
5. **06-explain** → `06_explain/output/semantic_<name>.md`. Plain-language
   semantic proof against the optional Teradata ground truth (if a local
   `00_input/<name>.teradata.sql` exists), per the Stage-6 contract.
   This markdown is **editable by the reviewer** and is the source of truth.
   Then run `06_explain/annotate.py` (or the task **S2S: Annotate SQL with
   semantic comments**) to embed it as comments in
   `03_fix/output/<name>_final.sql` — Purpose + SME questions as a header block,
   each `## 6. Inline anchors` note as a `-- SEM ▸` comment. Regeneration is
   idempotent (always rebuilds from the pure `_fixed.sql`).
6. **Always refresh the interactive report by RUNNING THE GENERATOR**: run
   `python3 05_report/build_report.py` (or the task **S2S: Refresh interactive
   report**) after any remediation run so `report.html` reflects the latest
   analysis, validation, and semantic outputs. This is a mandatory step, not an
   optional follow-up.

## Non-negotiables

- **NEVER hand-author or hand-edit `report.html`, and never write your own
  report generator.** `report.html` is produced ONLY by
  `05_report/build_report.py`, which renders the rich interactive report
  (summary cards, stage-completion matrix, per-unit sidebar with Overview /
  Fixes / Semantic / Validation sub-tabs) from the stage markdown. To update the
  report, run that script — do not emit HTML yourself. If the report needs to
  change, edit `build_report.py`, not the HTML.
- The fixed file must contain **no** residual Teradata construct (`ZEROIFNULL`,
  `CONTAINS`, `MULTISET`, `(+)`, BTEQ dot-commands, `MINUS`, `SEL`, …).
- Preserve column order, JOIN keys, and CASE-branch order exactly.
- Keep `QUALIFY` — Snowflake supports it. Do not wrap it in a ROW_NUMBER subquery.
- If a local `00_input/<name>.teradata.sql` exists, use it as ground truth
  instead of re-deriving intent from the buggy Snowflake; it is optional, and
  when absent you work from `02_rules/` and the Snowflake input alone — never
  reach outside the workspace for it. Flag every inference `TODO(SME)`.
- After a human corrects your output, capture the correction as a new rule or a
  lesson so the next run gets it right automatically.

## SQL conventions

- Target dialect is **Snowflake**. Prefer `COALESCE`, `DATEADD('day', n, d)`,
  `IFF`, `QUALIFY`, `TO_DATE(x,'fmt')`.
- Keep the original author's formatting and comments where a rule doesn't force
  a change.
