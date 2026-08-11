#!/usr/bin/env python3
"""Stage 6 — embed the semantic explanation into the SQL as comments.

The explanation in `06_explain/output/semantic_<name>.md` is the editable source
of truth: a human reviewer enriches it, then re-runs this script to refresh the
comments inside the final SQL. Regeneration always starts from the PURE fixed
file, so it is idempotent (re-running never stacks comments).

Usage:
  python3 06_explain/annotate.py \
      --sql   03_fix/output/<name>_fixed.sql \
      --md    06_explain/output/semantic_<name>.md \
      --out   03_fix/output/<name>_final.sql

What it injects:
  1. A top-of-file `SEMANTIC EXPLANATION` block comment (Purpose + open SME
     questions), placed right after the existing FIX LOG header.
  2. Inline `-- SEM ▸ <note>` comments, each placed above the first SQL line
     that contains the MATCH text from the md's `## 6. Inline anchors` section.

Only SQL comments are added — the statement itself is untouched, so it still
parses. Run 04_validate/validate.py on the output to confirm.
"""
import argparse
import re
import textwrap

HDR_START = "-- <<< SEMANTIC EXPLANATION (generated from 06_explain — edit the .md, not here)"
HDR_END = "-- >>> SEMANTIC EXPLANATION"
SEM_TAG = "-- SEM ▸ "  # "-- SEM ▸ "


def section(md: str, num: int) -> str:
    """Return the body text of '## {num}. ...' up to the next '## '."""
    m = re.search(rf"^##\s*{num}\.[^\n]*\n(.*?)(?=^##\s|\Z)", md, re.S | re.M)
    return m.group(1).strip() if m else ""


def parse_anchors(md: str):
    """Parse the ```anchors fenced block into [(match, note), ...]."""
    m = re.search(r"```anchors\s*\n(.*?)```", md, re.S)
    if not m:
        return []
    out = []
    for line in m.group(1).splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "::" not in line:
            continue
        match, note = line.split("::", 1)
        out.append((match.strip(), note.strip()))
    return out


LIST_RE = re.compile(r"^\s*(\d+\.\s|[-*]\s)")


def wrap_comment(text: str, width: int = 78) -> str:
    """Render markdown prose as `--`-prefixed comment lines. Paragraphs are
    reflowed (soft line breaks joined); list items are kept and their
    continuation lines indented."""
    out = []
    for block in re.split(r"\n\s*\n", text.strip()):
        block_lines = block.splitlines()
        is_list = any(LIST_RE.match(l) for l in block_lines)
        if is_list:
            # regroup: a new item starts at a list marker, continuations append
            items, cur = [], ""
            for l in block_lines:
                if LIST_RE.match(l):
                    if cur:
                        items.append(cur)
                    cur = l.strip()
                else:
                    cur += " " + l.strip()
            if cur:
                items.append(cur)
            for item in items:
                for i, seg in enumerate(textwrap.wrap(item, width=width)):
                    out.append(f"-- {'   ' if i else ''}{seg}")
        else:
            para = " ".join(l.strip() for l in block_lines)
            for seg in textwrap.wrap(para, width=width):
                out.append(f"-- {seg}")
        out.append("--")
    if out and out[-1] == "--":
        out.pop()
    return "\n".join(out)


def build_header(md: str, name: str) -> str:
    purpose = section(md, 1)
    sme = section(md, 5)
    parts = [
        HDR_START,
        "-- Source of truth: 06_explain/output/semantic_%s.md" % name,
        "--",
        "-- PURPOSE",
        wrap_comment(purpose),
        "--",
        "-- OPEN SME QUESTIONS",
        wrap_comment(sme),
        HDR_END,
    ]
    return "\n".join(parts)


def strip_existing(sql: str) -> str:
    """Remove a previously-injected header block and inline SEM tags so the run
    is idempotent."""
    sql = re.sub(re.escape(HDR_START) + r".*?" + re.escape(HDR_END) + r"\n?",
                 "", sql, flags=re.S)
    sql = "\n".join(l for l in sql.splitlines()
                    if not l.lstrip().startswith(SEM_TAG.strip()))
    # collapse any runs of 3+ blank lines left behind, so re-runs are stable
    sql = re.sub(r"\n{3,}", "\n\n", sql)
    return sql


def insert_header(sql: str, header: str) -> str:
    """Place the header after the FIX LOG banner (the last leading '-- ===' rule),
    else at the very top."""
    lines = sql.splitlines()
    insert_at = 0
    for i, l in enumerate(lines[:60]):
        if set(l.strip()) <= set("-= ") and "==" in l:
            insert_at = i + 1
    # skip a trailing blank line after the banner
    while insert_at < len(lines) and not lines[insert_at].strip():
        insert_at += 1
    out = lines[:insert_at] + ["", header, ""] + lines[insert_at:]
    return "\n".join(out)


def insert_anchors(sql: str, anchors):
    lines = sql.splitlines()
    placed, missed = [], []
    for match, note in anchors:
        for i, l in enumerate(lines):
            if match in l and not l.lstrip().startswith("--"):
                indent = l[: len(l) - len(l.lstrip())]
                lines.insert(i, f"{indent}{SEM_TAG}{note}")
                placed.append(match)
                break
        else:
            missed.append(match)
    return "\n".join(lines), placed, missed


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sql", required=True, help="pure fixed SQL (base)")
    ap.add_argument("--md", required=True, help="editable semantic markdown")
    ap.add_argument("--out", required=True, help="annotated final SQL")
    args = ap.parse_args()

    name = re.sub(r"^semantic_|\.md$", "", args.md.split("/")[-1])
    md = open(args.md).read()
    sql = strip_existing(open(args.sql).read())

    sql = insert_header(sql, build_header(md, name))
    sql, placed, missed = insert_anchors(sql, parse_anchors(md))

    if not sql.endswith("\n"):
        sql += "\n"
    open(args.out, "w").write(sql)

    print(f"OK  wrote {args.out}")
    print(f"    header block injected; {len(placed)} inline SEM comment(s) placed")
    if missed:
        print(f"    WARNING: {len(missed)} anchor(s) not found in SQL:")
        for m in missed:
            print(f"      - {m!r}")


if __name__ == "__main__":
    main()
