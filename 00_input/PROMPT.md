# Stage 0 — Input

**Role:** none (holding area, no AI work).

Place the **already-converted but buggy Snowflake** `.sql` files here. One file =
one remediation unit.

Do not edit files in this folder; all fixes happen downstream so the original
(buggy) input is always preserved for diffing against the fixed output.

Optionally, if the original **Teradata** source for a file is available, drop it
alongside here as `<name>.teradata.sql`. Stage 6 uses it as semantic ground truth
when present. It is **optional** — if absent, the pipeline proceeds without it and
never looks outside this workspace for it.
