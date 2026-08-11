#!/usr/bin/env python3
"""One-time (idempotent) dependency setup for the snowflake2snowflake pipeline.

Why this exists
---------------
Stage 4 needs `sqlglot`, which is comparatively slow to download. If every
pipeline run reinstalls it, you pay that cost over and over. This script fixes
that: it FIRST checks whether the dependencies already import, and only runs
`pip install` when something is actually missing. When everything is present it
exits in a few milliseconds and prints "deps OK" — so it is safe to call at the
start of any run without adding install latency.

Usage
-----
    python3 bootstrap.py            # ensure deps for THIS python3
    python3 bootstrap.py --force    # reinstall from requirements.txt regardless

Install to the SAME interpreter that runs the pipeline scripts. The VS Code
tasks and the stage scripts all use `python3`, so run this with `python3` too.
"""
from __future__ import annotations

import importlib.util
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
REQ = ROOT / "requirements.txt"

# import-name -> pip requirement. Only REQUIRED deps are checked here; optional
# extras (snowflake-connector-python) are left commented in requirements.txt.
REQUIRED = {
    "sqlglot": "sqlglot>=25.0",
}


def _present(mod: str) -> bool:
    return importlib.util.find_spec(mod) is not None


def missing() -> list[str]:
    return [mod for mod in REQUIRED if not _present(mod)]


def pip_install(args: list[str]) -> int:
    cmd = [sys.executable, "-m", "pip", "install", *args]
    print("  $", " ".join(cmd))
    return subprocess.call(cmd)


def main(argv: list[str]) -> int:
    force = "--force" in argv

    if not force:
        gaps = missing()
        if not gaps:
            print(f"deps OK — all required packages import for {sys.executable}")
            return 0
        print(f"missing: {', '.join(gaps)} — installing (one time)…")

    # Prefer the pinned requirements file; fall back to the inline pins.
    if REQ.exists():
        rc = pip_install(["-r", str(REQ)])
    else:
        rc = pip_install(list(REQUIRED.values()))

    if rc != 0:
        print("\nERROR: pip install failed.", file=sys.stderr)
        print("If you use an externally-managed Python, retry with:", file=sys.stderr)
        print(f"  {sys.executable} -m pip install --user -r {REQ}", file=sys.stderr)
        return rc

    still = missing()
    if still:
        print(f"\nERROR: still missing after install: {', '.join(still)}", file=sys.stderr)
        return 1
    print("deps OK — install complete")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
