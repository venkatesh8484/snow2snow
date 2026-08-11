# Stage 6 — Explain (semantic)

**Role:** You are a semantic analyst. You explain *meaning*, not syntax.

**Input:** the fixed file `03_fix/output/<name>_fixed.sql`, the analysis, and —
critically — the **Teradata original** as ground truth (if supplied).
**Output:** `06_explain/output/semantic_<name>.md`.

## Why this stage exists

A script can be syntactically perfect and still be wrong. Stage 6 proves (or
flags) that the fixed Snowflake statement *means* what the Teradata original
meant, and writes that proof in plain language for a reviewer and for the
interactive `report.html`.

## Instructions

Follow the "What Stage 6 must produce" contract in
`02_rules/05_semantic_rules.md`. Produce exactly these sections:

1. **Purpose** — one paragraph, business terms: source tables, target table, the
   grain of one output row.
2. **Clause-by-clause walk-through** — each major block (each CASE, each JOIN,
   the final dedup): what it computes and why. Where the fixed Snowflake differs
   from the buggy input, say what the input would have done instead.
3. **Semantic checks table** — every `SEM-*` risk: Present? Corrected how?
   Equivalent to Teradata? (Yes / Yes-with-assumption / SME).
4. **Divergences from the original** — anything intentionally not bit-identical,
   with justification.
5. **Open SME questions** — each `TODO(SME)` phrased as a decision for a human.

Keep it readable without opening the SQL. This markdown is the direct source for
the semantic panels in `report.html`; write it so those panels can quote it.

## The explanation is editable AND embedded in the SQL

This markdown is the **editable source of truth**. A human reviewer is expected
to enrich it — correct a description, add business context, refine an SME
question. Nothing here is final until the reviewer signs off.

The explanation is then **embedded as comments inside the final SQL** so it
travels with the code:

- Section 6, **Inline anchors**, is a fenced ```anchors``` block of
  `MATCH text :: note` lines. `annotate.py` places each note as a `-- SEM ▸`
  comment above the first SQL line containing the MATCH text. Sections 1
  (Purpose) and 5 (Open SME questions) become a `SEMANTIC EXPLANATION` header
  block in the SQL.
- Run it (or the VS Code task **S2S: Annotate SQL with semantic comments**):

  ```
  python3 06_explain/annotate.py \
      --sql 03_fix/output/<name>_fixed.sql \
      --md  06_explain/output/semantic_<name>.md \
      --out 03_fix/output/<name>_final.sql
  ```

- `<name>_fixed.sql` stays the pure fixed statement; `<name>_final.sql` is the
  reviewer-facing deliverable **with the semantic explanation as comments**.
- Regeneration is idempotent — it always rebuilds from the pure fixed file, so a
  reviewer can edit the markdown and re-run as often as they like. Validate the
  result with `04_validate/validate.py` (comments don't change parsing).

## Refresh the interactive report (run the generator — never hand-write it)

After the semantic markdown exists, regenerate `report.html`:

```
python3 05_report/build_report.py
```

(or the VS Code task **S2S: Refresh interactive report**). This is the ONLY
supported way to produce `report.html`. It scans every unit's stage outputs and
renders the rich interactive report — summary cards, a stage-completion matrix,
and a per-unit sidebar with Overview / Fixes / Semantic / Validation sub-tabs.
Do not author HTML by hand and do not write a second generator; if the report
needs to look different, edit `build_report.py`.
