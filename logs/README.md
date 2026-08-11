# Orchestrator run logs

One timestamped file per `s2s-remediate` run, e.g.
`orchestrator_2026-07-24T19-57-03_SFIssueSET.log`.

Each log captures the full audit trail for a single run: every stage, every shell
command with its complete stdout/stderr, and every artifact the subagents produced
(analysis, fixed SQL, validation report, fix report, semantic explanation).

Written by `../audit_log.py`. The orchestrator opens a log with
`audit_log.py start <name>` and closes it with `audit_log.py end`. Logs are never
overwritten — each run is a new file.

`.current_run` / `.current_start` are transient pointers to the in-flight run and
are not part of the audit record.
