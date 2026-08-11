---
mode: agent
description: "Stage 5 — remediation report + append a lesson"
---

# /05-report

Read `05_report/PROMPT.md`, then write
`05_report/output/fix_report_<name>.md` from the Stage 1–4 outputs: summary,
rules applied (grouped syntax / defect / semantic), defects repaired, open
`TODO(SME)` items, validation result. A reviewer must be able to sign off from
this document alone.

Then append a dated entry to `02_rules/06_lessons_learned.md` capturing anything
that would change how the next file is handled. Reference the Stage-6 semantic
doc; do not duplicate it.

To refresh `report.html`, run `python3 05_report/build_report.py` (or the task
**S2S: Refresh interactive report**). Never hand-write the HTML — the generator
builds the rich interactive report from the stage outputs.
