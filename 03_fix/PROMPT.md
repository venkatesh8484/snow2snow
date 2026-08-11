# Stage 3 — Fix

**Role:** You are a Snowflake→Snowflake remediation engine.

**Input:** the buggy file from `00_input/` + its analysis from
`01_analyze/output/` + **every** markdown file in `02_rules/` (read all of them,
every run — rules change between runs; that is how you learn).

**Output:** `03_fix/output/<name>_fixed.sql`.

> **Re-remediation:** if `06_explain/output/semantic_<name>.md` already exists
> (a reviewer enriched it and asked to re-remediate), read it **first** and treat
> it as authoritative guidance. Its clarifications and answered SME questions
> override your own assumptions: resolve the matching `-- TODO(SME)` items using
> the reviewer's answers, adjust any fix the reviewer's semantics contradict, and
> note in the FIX LOG that the change came from reviewer semantics. Do not
> re-introduce an assumption the reviewer has already settled.

## Instructions

1. Apply the rules in `02_rules/` to every finding in the analysis, in this
   order: **(a)** syntax/function/datatype fixes so the file parses (`SFX-*`,
   `FNX-*`, `DTX-*`), **(b)** defect repairs (`DEF-*`), **(c)** semantic
   corrections (`SEM-*`). Do not invent fixes not covered by a rule; if you meet
   an unlisted construct, stop and add a proposed rule to the analysis for human
   review.
2. Record **every** change in a `FIX LOG` comment block at the top of the output
   file, each line citing a rule ID and the source line(s). One line = one real
   issue fixed — the report counts these for the "Issues fixed" metric. If the
   input was already clean and nothing substantive changed, use `[AUTO]` marker
   lines (these are **not** counted as issues). Use plain rule IDs (`FNX-01`,
   `SFX-01`, `DEF-02`, `SEM-05`, …) for genuine repairs; phrase deliberate
   no-ops as "kept as-is" / "verified" so they aren't miscounted as fixes.
3. Mark every assumption with an inline `-- TODO(SME): ...` comment.
4. Preserve semantics, column order, and the author's formatting/comments
   wherever the rules don't force a change. **Minimal diff is a feature** — the
   reviewer must be able to trace every difference to a rule ID or fix-log line.
   - **SnowSQL client layer (`.snowsql` inputs).** Never modify `<% ctx.env.X %>`
     template tags or `PUT`/`GET` commands (`SNZ-01/02/03` in
     `02_rules/07_snowsql_client.md`) — leave them verbatim and in place. Fix
     only the real SQL, including the SQL body of `COPY INTO @stage (…)`. Add one
     `[KEEP] SNZ-0x` FIX-LOG line per preserved construct (not counted as a fix).
5. The output must be a single executable Snowflake statement (or batch), ready
   for Stage 4 validation. Do not leave any residual Teradata construct.
