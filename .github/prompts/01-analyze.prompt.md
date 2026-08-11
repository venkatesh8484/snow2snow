---
mode: agent
description: "Stage 1 — audit a buggy Snowflake script (no fixing)"
---

# /01-analyze

Analyze the buggy Snowflake file I name (default: the newest file in
`00_input/`). **Do not fix anything.**

**Archive first.** Before analyzing, run `python3 05_report/archive_outputs.py <name>`
so this unit's prior outputs move to `_archive/<timestamp>/` and a re-run starts
clean (other units untouched; no-op if already archived). Use
`python3 05_report/archive_outputs.py` with no args to reset **all** units before
a full pipeline re-run.

Read `01_analyze/PROMPT.md` and **all** of `02_rules/` first. Then produce
`01_analyze/output/analysis_<name>.md` exactly per the Stage-1 contract:

1. Column-count check first — INSERT target columns vs SELECT expressions, with
   duplicates noted and the net after removing them.
2. Syntax errors / residual-Teradata constructs, with line numbers and *why*
   each is invalid on Snowflake (cite `SFX-*` / `FNX-*` / `DTX-*`).
3. Defects (`DEF-*`), with line numbers.
4. Semantic risks present (`SEM-*`).
5. Classify every finding AUTO / FIX / SME.
6. Table dependency inventory.
7. A one-line verdict.

Use the original script in `00_input/` as ground truth for the semantic risks.
Stop and propose a new rule for any construct not covered by `02_rules/`.

**Never silently assume SET-table semantics (SEM-05).** SET vs MULTISET is
declared only in the target's `CREATE TABLE` DDL, not in an INSERT-only script.
If the file has multiple `INSERT`s into one target — or a `UNION`/`UNION ALL`
whose branches all write to one target — and no `CREATE TABLE` DDL for that
target is supplied, do not decide: raise an explicit **SME question** ("Is
`<target>` a SET table?") and classify it `SME`. Detect `SET`/`MULTISET`
directly only when the DDL is provided.
