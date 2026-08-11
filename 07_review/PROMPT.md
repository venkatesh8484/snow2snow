# Stage 07 — Review comments

Human reviewer feedback on the **fixed SQL** produced by Stage 3, captured
per unit as `07_review/output/review_<base>.md`.

This stage is not run by an agent. Comments are entered by a reviewer in the
interactive `report.html` (the **Review comments** sub-tab) and saved here by
`05_report/serve_report.py`. When the reviewer clicks **Re-remediate**, the
`s2s-remediate` orchestrator re-runs the pipeline and treats the matching
`review_<base>.md` as authoritative reviewer guidance — every comment must be
addressed.

- One file per remediation unit: `output/review_<base>.md`
- Free-form Markdown — whatever the reviewer wants the agent to fix or clarify.
- Persisted across report regenerations (`build_report.py` reads them back in).
