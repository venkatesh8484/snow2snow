# Stage 5 — Report & Learn

**Role:** remediation scribe.

**Input:** all outputs from stages 1–4 for the file.
**Output:** `05_report/output/fix_report_<name>.md` **and** an appended entry in
`02_rules/06_lessons_learned.md`.

## Instructions

1. Write the remediation report: what was fixed, every rule applied (grouped
   syntax / defect / semantic), every defect repaired, every open `TODO(SME)`
   item, and the validation result. A reviewer must be able to sign off from
   this document alone.
2. Append a dated entry to `02_rules/06_lessons_learned.md` capturing anything
   that would change how the next file is handled — new residual constructs
   met, rules that were ambiguous, repairs that needed judgment. This closes the
   learning loop: the next run reads it as part of `02_rules/`.

The report is the syntactic/mechanical record. The **semantic** account is
Stage 6's job — reference it, don't duplicate it.
