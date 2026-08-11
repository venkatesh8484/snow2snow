#!/usr/bin/env python3
"""Per-run audit logger for the s2s-remediate orchestrator.

Every orchestrator run gets ONE timestamped log file under `logs/`, e.g.
`logs/orchestrator_2026-07-24T19-57-03_SFIssueSET.log`. Everything the run does —
each stage, each shell command and its full stdout/stderr, and each artifact the
subagents produce — is appended there so the run can be audited end to end.

The "current" run is tracked by a pointer file `logs/.current_run` so that
separate command invocations across the run all write to the same log.

Commands
--------
  start [run_name]              Open a new run log, print its path, set it current.
  log  "<stage>" "<message>"    Append a timestamped note under a stage.
  run  "<stage>" -- <cmd...>    Run <cmd>, tee its stdout+stderr into the log,
                                 exit with the command's return code.
  append "<label>" <file>       Append a file's contents under a labelled header
                                 (use for subagent output .md/.sql artifacts).
  end                           Write a footer with total run duration; clear current.
  path                          Print the current run-log path (for shell teeing).

Typical orchestrator usage
--------------------------
  python3 audit_log.py start SFIssueSET
  python3 audit_log.py run "0-archive" -- python3 05_report/archive_outputs.py SFIssueSET
  python3 audit_log.py log "1-analyze" "s2s-analyze produced analysis_SFIssueSET.md"
  python3 audit_log.py append "analysis" 01_analyze/output/analysis_SFIssueSET.md
  python3 audit_log.py run "4-validate" -- python3 04_validate/validate.py 03_fix/output/SFIssueSET_fixed.sql
  ...
  python3 audit_log.py end
"""
from __future__ import annotations

import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent
LOG_DIR = ROOT / "logs"
POINTER = LOG_DIR / ".current_run"


def _now() -> str:
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def _stamp() -> str:
    # Filesystem-safe timestamp for the filename.
    return datetime.now().strftime("%Y-%m-%dT%H-%M-%S")


def _current_log() -> Path | None:
    if POINTER.exists():
        p = Path(POINTER.read_text(encoding="utf-8").strip())
        if p.exists():
            return p
    return None


def _require_log() -> Path:
    log = _current_log()
    if log is None:
        # Be forgiving: auto-open a run rather than crashing a pipeline mid-stage.
        log = _start(None)
        _write(log, f"[{_now()}] [audit] WARN no active run found — auto-started one.")
    return log


def _write(log: Path, text: str) -> None:
    with log.open("a", encoding="utf-8") as fh:
        fh.write(text.rstrip("\n") + "\n")


def _safe_unlink(path: Path) -> None:
    """Remove a transient pointer file, tolerating filesystems that forbid it.
    A pointer we can't delete must never crash a run."""
    try:
        path.unlink(missing_ok=True)
    except OSError:
        pass


def _start(run_name: str | None) -> Path:
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    suffix = f"_{run_name}" if run_name else ""
    log = LOG_DIR / f"orchestrator_{_stamp()}{suffix}.log"
    header = [
        "=" * 72,
        f"ORCHESTRATOR RUN AUDIT LOG",
        f"run           : {run_name or '(unnamed)'}",
        f"started (local): {_now()}",
        f"started (utc)  : {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')}",
        f"log file      : {log}",
        "=" * 72,
        "",
    ]
    log.write_text("\n".join(header), encoding="utf-8")
    POINTER.write_text(str(log), encoding="utf-8")
    # Record wall-clock start for the eventual duration footer.
    (LOG_DIR / ".current_start").write_text(str(datetime.now().timestamp()), encoding="utf-8")
    return log


def cmd_start(argv: list[str]) -> int:
    run_name = argv[0] if argv else None
    log = _start(run_name)
    print(str(log))
    return 0


def cmd_log(argv: list[str]) -> int:
    if len(argv) < 2:
        sys.exit('usage: audit_log.py log "<stage>" "<message>"')
    stage, message = argv[0], " ".join(argv[1:])
    _write(_require_log(), f"[{_now()}] [{stage}] {message}")
    return 0


def cmd_run(argv: list[str]) -> int:
    if "--" not in argv:
        sys.exit('usage: audit_log.py run "<stage>" -- <command ...>')
    sep = argv.index("--")
    stage = " ".join(argv[:sep]) or "(cmd)"
    command = argv[sep + 1:]
    if not command:
        sys.exit("no command given after --")

    log = _require_log()
    _write(log, "")
    _write(log, "-" * 72)
    _write(log, f"[{_now()}] [{stage}] $ {' '.join(command)}")
    _write(log, "-" * 72)

    # Tell child scripts (e.g. validate.py) that this run wrapper is already
    # capturing their stdout, so their own auto-tee doesn't double-log.
    import os
    child_env = dict(os.environ, AUDIT_LOG_WRAPPED="1")
    proc = subprocess.run(
        command, capture_output=True, text=True, cwd=str(ROOT), env=child_env
    )
    if proc.stdout:
        _write(log, proc.stdout)
        sys.stdout.write(proc.stdout)  # still show the operator the live output
    if proc.stderr:
        _write(log, "[stderr]")
        _write(log, proc.stderr)
        sys.stderr.write(proc.stderr)
    _write(log, f"[{_now()}] [{stage}] exit code: {proc.returncode}")
    return proc.returncode


def cmd_append(argv: list[str]) -> int:
    if len(argv) < 2:
        sys.exit('usage: audit_log.py append "<label>" <file>')
    label, file_path = argv[0], argv[1]
    log = _require_log()
    src = Path(file_path)
    _write(log, "")
    _write(log, "-" * 72)
    _write(log, f"[{_now()}] [artifact:{label}] {file_path}")
    _write(log, "-" * 72)
    if src.exists():
        _write(log, src.read_text(encoding="utf-8", errors="replace"))
    else:
        _write(log, f"(file not found: {file_path})")
    return 0


def cmd_end(_argv: list[str]) -> int:
    log = _current_log()
    if log is None:
        print("no active run to end")
        return 0
    duration = ""
    start_file = LOG_DIR / ".current_start"
    if start_file.exists():
        try:
            started = float(start_file.read_text(encoding="utf-8").strip())
            secs = int(datetime.now().timestamp() - started)
            duration = f"{secs // 60}m {secs % 60}s"
        except ValueError:
            pass
        _safe_unlink(start_file)
    _write(log, "")
    _write(log, "=" * 72)
    _write(log, f"[{_now()}] RUN COMPLETE" + (f" — duration {duration}" if duration else ""))
    _write(log, "=" * 72)
    _safe_unlink(POINTER)
    print(str(log))
    return 0


def cmd_path(_argv: list[str]) -> int:
    log = _current_log()
    if log is None:
        sys.exit("no active run")
    print(str(log))
    return 0


DISPATCH = {
    "start": cmd_start,
    "log": cmd_log,
    "run": cmd_run,
    "append": cmd_append,
    "end": cmd_end,
    "path": cmd_path,
}


def main() -> int:
    if len(sys.argv) < 2 or sys.argv[1] not in DISPATCH:
        sys.exit(__doc__)
    return DISPATCH[sys.argv[1]](sys.argv[2:])


if __name__ == "__main__":
    sys.exit(main())
