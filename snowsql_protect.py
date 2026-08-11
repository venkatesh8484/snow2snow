#!/usr/bin/env python3
"""SnowSQL "preserve-as-is" protector for the Snowflake->Snowflake pipeline.

Some inputs are **SnowSQL** files (extension ``.snowsql``) rather than plain
``.sql``. They are mostly ordinary Snowflake SQL, but they carry two constructs
that are NOT plain SQL and must never be rewritten by the remediation stages:

  1. ``<% ctx.env.VARNAME %>`` — orchestrator template placeholders. These are
     resolved at run time by the job runner, not by Snowflake. sqlglot cannot
     parse a bare ``<% ... %>`` token, so Stage-4 validation would hard-fail
     before it ever looked at the real SQL.
  2. ``PUT`` / ``GET`` — SnowSQL-CLI-only file-transfer commands. sqlglot parses
     them only as opaque "Command" objects; the fix stage must leave them alone.
     (``COPY INTO`` / ``REMOVE`` / ``LIST`` parse fine and need no protection.)

The policy (chosen by the project owner) is **preserve as-is**: this module
masks those constructs so the *existing* validator/analysis can run on the real
SQL, then restores the originals byte-for-byte. It does NOT change behaviour for
plain ``.sql`` files — protection is gated on the ``.snowsql`` extension.

Public API
----------
    is_snowsql(path)            -> bool     # gate: does this file get protected?
    protect(text)               -> (masked_text, ctx)
    restore(masked_text, ctx)   -> original_text

``ctx`` is an opaque dict; pass the same object from ``protect`` back into
``restore``. ``restore(protect(x)[0], protect(x)[1]) == x`` for any input.

CLI (for eyeballing / debugging)::

    python3 snowsql_protect.py --selftest
    python3 snowsql_protect.py mask   00_input/foo.snowsql   # print masked SQL
    python3 snowsql_protect.py tokens 00_input/foo.snowsql   # list what was masked
"""
from __future__ import annotations

import re
import sys
from pathlib import Path
from typing import Dict, List, Tuple

# --- constructs we protect -------------------------------------------------

# 1. Orchestrator template tags: <% ... %> (non-greedy, may span nothing fancy).
_TEMPLATE_RE = re.compile(r"<%.*?%>", re.DOTALL)

# 2. SnowSQL CLI file-transfer commands: a PUT or GET statement (statement =
#    up to the terminating semicolon or end of file). These are the only client
#    commands that can't run through a normal SQL connection.
_CLIENT_CMD_RE = re.compile(
    r"^[ \t]*(?:PUT|GET)\b.*?(?:;|\Z)",
    re.IGNORECASE | re.DOTALL | re.MULTILINE,
)

# Mask tokens. Bare identifiers parse cleanly in every position these tags
# appear (value context, stage path @__TPL_0__/f, file:// path, SELECT item).
_TPL_TOKEN = "__TPL_{n}__"
# Client commands are lifted out entirely and replaced with a comment line so
# the surrounding SQL still parses and the line numbers stay stable-ish.
_CMD_TOKEN = "-- __SNOWSQL_CMD_{n}__"


SNOWSQL_EXT = ".snowsql"


def is_snowsql(path) -> bool:
    """True if *path* should go through the protect step (``.snowsql`` file)."""
    return str(path).lower().endswith(SNOWSQL_EXT)


def protect(text: str) -> Tuple[str, Dict[str, List]]:
    """Mask template tags and PUT/GET commands. Returns (masked_text, ctx).

    ``ctx["subs"]`` is an ordered list of ``(token, original)`` pairs. Restore
    replays them in reverse so a later token can never be a prefix of an
    earlier one (``__TPL_1__`` vs ``__TPL_12__``).
    """
    subs: List[Tuple[str, str]] = []
    n_cmd = [0]
    n_tpl = [0]

    # Order matters: lift whole PUT/GET commands FIRST (they may themselves
    # contain <% %> tags), then mask any remaining template tags in real SQL.
    def _take_cmd(m: re.Match) -> str:
        original = m.group(0)
        base = _CMD_TOKEN.format(n=n_cmd[0])
        n_cmd[0] += 1
        # Preserve the original line count so validator line numbers don't shift:
        # a 3-line PUT becomes a comment line + blank padding lines.
        pad = "\n" * original.count("\n")
        token = base + pad
        subs.append((token, original))
        return token

    masked = _CLIENT_CMD_RE.sub(_take_cmd, text)

    def _take_tpl(m: re.Match) -> str:
        original = m.group(0)
        token = _TPL_TOKEN.format(n=n_tpl[0])
        n_tpl[0] += 1
        subs.append((token, original))
        return token

    masked = _TEMPLATE_RE.sub(_take_tpl, masked)

    return masked, {"subs": subs}


def restore(masked: str, ctx: Dict[str, List]) -> str:
    """Inverse of :func:`protect` — put every original construct back verbatim."""
    text = masked
    for token, original in reversed(ctx.get("subs", [])):
        text = text.replace(token, original)
    return text


def protect_if_snowsql(text: str, path) -> Tuple[str, Dict[str, List]]:
    """Convenience: protect only when *path* is a ``.snowsql`` file, else no-op."""
    if is_snowsql(path):
        return protect(text)
    return text, {"templates": [], "commands": []}


# --- CLI / self-test -------------------------------------------------------

_SELFTEST_SAMPLES = [
    "SELECT * FROM t WHERE d BETWEEN <% ctx.env.Period_start %> AND <% ctx.env.Period_end %>;",
    "COPY INTO STAGING.T FROM @<% ctx.env.LANDING_STAGE %>/f.csv FILE_FORMAT=(TYPE='CSV');",
    "PUT file://<% ctx.env.DIR %>\n    @<% ctx.env.STAGE %>\n    OVERWRITE = TRUE AUTO_COMPRESS = FALSE;",
    "GET @<% ctx.env.STAGE %>/out.csv file://<% ctx.env.OUT %> OVERWRITE = TRUE;",
    "REMOVE @<% ctx.env.STAGE %>/out.csv;\nSELECT <% ctx.env.Current_date %> AS run_dt;",
]


def _selftest() -> int:
    ok = True
    # 1. round-trip fidelity on samples + a joined blob
    blob = "\n\n".join(_SELFTEST_SAMPLES)
    for sample in _SELFTEST_SAMPLES + [blob]:
        masked, ctx = protect(sample)
        assert "<%" not in masked, "template tag leaked into masked text"
        restored = restore(masked, ctx)
        if restored != sample:
            ok = False
            print("FAIL round-trip:\n  in :", repr(sample), "\n  out:", repr(restored))
    # 2. masked blob must parse under sqlglot (the whole point)
    try:
        import sqlglot

        masked, _ = protect(blob)
        sqlglot.parse(masked, read="snowflake")
        print("PASS masked SnowSQL parses under sqlglot")
    except ImportError:
        print("INFO sqlglot not installed — skipped parse check")
    except Exception as exc:
        ok = False
        print(f"FAIL masked SnowSQL did not parse: {exc}")
    # 3. plain .sql is untouched by the gate
    plain = "SELECT 1;"
    out, _ = protect_if_snowsql(plain, "foo.sql")
    if out != plain:
        ok = False
        print("FAIL plain .sql was modified by the gate")
    print("SELFTEST:", "PASS" if ok else "FAIL")
    return 0 if ok else 1


def main(argv: List[str]) -> int:
    if not argv or argv[0] == "--selftest":
        return _selftest()
    cmd = argv[0]
    if cmd in ("mask", "tokens") and len(argv) >= 2:
        text = Path(argv[1]).read_text(encoding="utf-8")
        masked, ctx = protect(text)
        if cmd == "mask":
            sys.stdout.write(masked)
        else:
            tpl = [(t, o) for t, o in ctx["subs"] if t.startswith("__TPL_")]
            cmds = [(t, o) for t, o in ctx["subs"] if t.startswith("-- __SNOWSQL_CMD_")]
            print(f"{len(tpl)} template tag(s), "
                  f"{len(cmds)} PUT/GET command(s) protected:")
            for token, original in tpl:
                print(f"  {token}  <-  {original}")
            for token, original in cmds:
                first = original.strip().splitlines()[0]
                print(f"  {token.strip()}  <-  {first[:70]}")
        return 0
    print(__doc__)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
