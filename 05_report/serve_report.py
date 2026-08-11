#!/usr/bin/env python3
"""Local server for the interactive report.html.

report.html is a static file, so its Semantic-tab buttons can only *download*
files when opened via file://. Serve it through THIS server instead and those
buttons gain two real powers:

    POST /save          -> writes 06_explain/output/semantic_<base>.md directly
    POST /reremediate   -> writes the semantic .md, drops a re-remediate prompt
                           file, and opens VS Code so Copilot's `s2s-remediate`
                           orchestrator can pick it up for that script.
    POST /save_review        -> writes 07_review/output/review_<base>.md directly
    POST /reremediate_review -> writes the review .md, drops a re-remediate prompt
                           pointing at those comments, and opens VS Code so
                           `s2s-remediate` can pick it up for that script.

Everything else (GET /, static assets) is served straight from the repo root.

Usage:
    python3 05_report/serve_report.py            # http://127.0.0.1:8765
    python3 05_report/serve_report.py --port 9000
    python3 05_report/serve_report.py --no-open  # don't auto-open the browser

The `code` CLI is used to focus VS Code on the re-remediate prompt. If it isn't
on PATH the endpoint still succeeds (the prompt file is written and returned to
the page), it just can't raise the editor automatically.
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import webbrowser
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SEMANTIC_DIR = ROOT / "06_explain" / "output"
PROMPT_DIR = ROOT / "05_report" / "output"
REVIEW_DIR = ROOT / "07_review" / "output"

# Only bare file stems are ever accepted as a unit base — no path separators,
# no traversal. Anything else is rejected before it touches the filesystem.
SAFE_BASE = re.compile(r"^[A-Za-z0-9._-]+$")


def safe_base(base: str) -> str:
    base = (base or "").strip()
    if not base or not SAFE_BASE.match(base) or base in (".", ".."):
        raise ValueError(f"unsafe or empty base: {base!r}")
    return base


def reremediate_prompt(base: str, input_name: str) -> str:
    """The orchestrator prompt handed to Copilot's s2s-remediate agent."""
    inp = input_name or f"{base}.sql"
    return (
        f"@s2s-remediate Re-remediate `{base}` using my updated semantics.\n\n"
        f"0. Archive this unit's prior outputs first: "
        f"`python3 05_report/archive_outputs.py {base}` so stale files don't leak "
        f"into the report.\n"
        f"1. I saved an enriched `06_explain/output/semantic_{base}.md` — read it "
        f"as authoritative reviewer guidance and treat its clarifications and SME "
        f"answers as ground truth.\n"
        f"2. Re-run the pipeline for `00_input/{inp}` in order — s2s-analyze, "
        f"s2s-fix, s2s-validate (fixed must PASS, buggy control must FAIL), "
        f"s2s-report, s2s-explain.\n"
        f"3. Re-embed the semantic comments (06_explain/annotate.py) and refresh "
        f"the report (`python3 05_report/build_report.py`).\n"
        f"4. Report the counts (residual constructs, defects, open TODO(SME)) when "
        f"done.\n"
    )


def review_reremediate_prompt(base: str, input_name: str) -> str:
    """Orchestrator prompt for a re-remediate triggered from the Review-comments
    tab — points s2s-remediate at the reviewer's comments on the fixed SQL."""
    inp = input_name or f"{base}.sql"
    return (
        f"@s2s-remediate Re-remediate `{base}` using my review comments.\n\n"
        f"0. Archive this unit's prior outputs first: "
        f"`python3 05_report/archive_outputs.py {base}` so stale files don't leak "
        f"into the report.\n"
        f"1. I saved reviewer comments on the fixed SQL to "
        f"`07_review/output/review_{base}.md` — read them as authoritative "
        f"reviewer guidance and address every point.\n"
        f"2. Re-run the pipeline for `00_input/{inp}` in order — s2s-analyze, "
        f"s2s-fix, s2s-validate (fixed must PASS, buggy control must FAIL), "
        f"s2s-report, s2s-explain.\n"
        f"3. Re-embed the semantic comments (06_explain/annotate.py) and refresh "
        f"the report (`python3 05_report/build_report.py`).\n"
        f"4. Report the counts (residual constructs, defects, open TODO(SME)) and "
        f"summarize how each review comment was resolved when done.\n"
    )


def open_in_vscode(*targets: Path) -> bool:
    """Best-effort: raise VS Code on the given files/folder. Returns True if the
    `code` CLI was found and launched, False otherwise."""
    code = shutil.which("code")
    if not code:
        return False
    try:
        subprocess.Popen(
            [code, "--reuse-window", str(ROOT), *[str(t) for t in targets]],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return True
    except Exception:
        return False


class Handler(SimpleHTTPRequestHandler):
    # Serve everything relative to the repo root regardless of cwd.
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    # keep the console quiet-ish
    def log_message(self, fmt, *args):
        sys.stderr.write("  %s - %s\n" % (self.address_string(), fmt % args))

    def do_GET(self):
        if self.path in ("/", ""):
            self.path = "/report.html"
        return super().do_GET()

    # ------------------------------------------------------------------ POST
    def _read_json(self) -> dict:
        length = int(self.headers.get("Content-Length", 0) or 0)
        raw = self.rfile.read(length) if length else b""
        return json.loads(raw or b"{}")

    def _send_json(self, obj: dict, status: int = 200):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        try:
            if self.path.rstrip("/") == "/save":
                return self._handle_save()
            if self.path.rstrip("/") == "/reremediate":
                return self._handle_reremediate()
            if self.path.rstrip("/") == "/save_review":
                return self._handle_save_review()
            if self.path.rstrip("/") == "/reremediate_review":
                return self._handle_reremediate_review()
            self._send_json({"ok": False, "error": "unknown endpoint"}, 404)
        except ValueError as e:
            self._send_json({"ok": False, "error": str(e)}, 400)
        except Exception as e:  # never leak a stack trace to the page
            self._send_json({"ok": False, "error": repr(e)}, 500)

    def _write_semantic(self, base: str, content: str) -> Path:
        SEMANTIC_DIR.mkdir(parents=True, exist_ok=True)
        path = SEMANTIC_DIR / f"semantic_{base}.md"
        path.write_text(content or "", encoding="utf-8")
        return path

    def _handle_save(self):
        data = self._read_json()
        base = safe_base(data.get("base", ""))
        path = self._write_semantic(base, data.get("content", ""))
        rel = path.relative_to(ROOT).as_posix()
        print(f"SAVE  wrote {rel} ({len(data.get('content','') or '')} chars)")
        self._send_json({"ok": True, "path": rel})

    def _write_review(self, base: str, content: str) -> Path:
        REVIEW_DIR.mkdir(parents=True, exist_ok=True)
        path = REVIEW_DIR / f"review_{base}.md"
        path.write_text(content or "", encoding="utf-8")
        return path

    def _handle_save_review(self):
        data = self._read_json()
        base = safe_base(data.get("base", ""))
        path = self._write_review(base, data.get("content", ""))
        rel = path.relative_to(ROOT).as_posix()
        print(f"REVIEW wrote {rel} ({len(data.get('content','') or '')} chars)")
        self._send_json({"ok": True, "path": rel})

    def _handle_reremediate_review(self):
        data = self._read_json()
        base = safe_base(data.get("base", ""))
        # 1. persist the reviewer comments as authoritative guidance
        review_path = self._write_review(base, data.get("content", ""))
        # 2. write the orchestrator prompt to a file next to the reports
        prompt = review_reremediate_prompt(base, (data.get("input_name") or "").strip())
        PROMPT_DIR.mkdir(parents=True, exist_ok=True)
        prompt_path = PROMPT_DIR / f"reremediate_{base}.prompt.md"
        prompt_path.write_text(prompt, encoding="utf-8")
        # 3. raise VS Code on the prompt + review so s2s-remediate can pick it up
        opened = open_in_vscode(prompt_path, review_path)
        rel = prompt_path.relative_to(ROOT).as_posix()
        print(f"REMED(review) triggered {base} -> {rel} (vscode opened: {opened})")
        self._send_json(
            {
                "ok": True,
                "base": base,
                "opened": opened,
                "prompt_path": rel,
                "review_path": review_path.relative_to(ROOT).as_posix(),
                "prompt": prompt,
            }
        )

    def _handle_reremediate(self):
        data = self._read_json()
        base = safe_base(data.get("base", ""))
        # 1. persist the edited semantics as authoritative reviewer guidance
        sem_path = self._write_semantic(base, data.get("content", ""))
        # 2. write the orchestrator prompt to a file next to the reports
        prompt = reremediate_prompt(base, (data.get("input_name") or "").strip())
        PROMPT_DIR.mkdir(parents=True, exist_ok=True)
        prompt_path = PROMPT_DIR / f"reremediate_{base}.prompt.md"
        prompt_path.write_text(prompt, encoding="utf-8")
        # 3. raise VS Code on the prompt so s2s-remediate can pick it up
        opened = open_in_vscode(prompt_path, sem_path)
        rel = prompt_path.relative_to(ROOT).as_posix()
        print(f"REMED triggered {base} -> {rel} (vscode opened: {opened})")
        self._send_json(
            {
                "ok": True,
                "base": base,
                "opened": opened,
                "prompt_path": rel,
                "semantic_path": sem_path.relative_to(ROOT).as_posix(),
                "prompt": prompt,
            }
        )


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--no-open", action="store_true", help="don't open the browser")
    args = ap.parse_args()

    if not (ROOT / "report.html").exists():
        print("report.html not found — run `python3 05_report/build_report.py` first.",
              file=sys.stderr)

    httpd = ThreadingHTTPServer((args.host, args.port), Handler)
    url = f"http://{args.host}:{args.port}/report.html"
    print(f"Serving {ROOT}")
    print(f"Report:  {url}")
    print("Semantic-tab buttons now save + re-remediate directly. Ctrl-C to stop.")
    if not args.no_open:
        try:
            webbrowser.open(url)
        except Exception:
            pass
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nbye")
        httpd.server_close()


if __name__ == "__main__":
    main()
