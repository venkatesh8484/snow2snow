#!/usr/bin/env python3
"""Build the interactive report.html from the ICM stage outputs.

This is the CANONICAL report generator. Agents/humans must run THIS instead of
hand-authoring report.html — that keeps every run's report at the same quality
and never clobbers it with an ad-hoc page.

Usage:
    python3 05_report/build_report.py            # scans all units, writes ../report.html
    python3 05_report/build_report.py --open     # also print the output path

It discovers every remediation unit (one per analysis_*.md), parses the
analysis / fix report / validation / semantic markdown, and renders a single
self-contained HTML file: summary cards, a stage-completion matrix, a unit
sidebar, and per-unit sub-tabs (Overview / Fixes / Semantic / Validation).

The Validation tab is NOT copied from the hand-written stage-4 markdown — the
generator runs 04_validate/validate.py itself on the fixed file and the buggy
input, so every unit's Validation tab has the identical layout (Final SQL block
+ Buggy input control block + a standard note). If the validator can't run
(e.g. sqlglot missing), it falls back to rendering the stage-4 markdown.
"""
from __future__ import annotations
import difflib
import html
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DIRS = {
    "analysis":   ROOT / "01_analyze" / "output",
    "report":     ROOT / "05_report" / "output",
    "semantic":   ROOT / "06_explain" / "output",
    "validation": ROOT / "04_validate" / "output",
}
FIX_DIR = ROOT / "03_fix" / "output"
RULES_DIR = ROOT / "02_rules"
REVIEW_DIR = ROOT / "07_review" / "output"


# ----------------------------- tiny markdown -> html -----------------------------
def md_inline(s: str) -> str:
    """Inline-only markdown (code + bold) for single-line snippets such as SME
    items. Unlike md_to_html it has no table/list heuristics, so a line that
    contains a SQL pipe (`a || b`) or leading bold renders correctly instead of
    being swallowed."""
    s = s.replace("\\|", "|")
    s = html.escape(s)
    s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
    s = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", s)
    return s


def md_to_html(md: str) -> str:
    """Render a practical subset of Markdown: headings, tables, lists, code
    fences, inline code/bold. Good enough for the stage artifacts."""
    if not md.strip():
        return "<p class='muted'>—</p>"
    lines = md.splitlines()
    out, i, n = [], 0, len(lines)

    def inline(s: str) -> str:
        s = s.replace("\\|", "|")            # unescape literal pipes
        s = html.escape(s)
        s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
        s = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", s)
        return s

    def cells(s: str):
        # split a table row on UNescaped pipes only (so SQL `||` survives)
        s = s.strip()
        s = re.sub(r"^\||\|$", "", s)
        return [c.strip() for c in re.split(r"(?<!\\)\|", s)]

    while i < n:
        line = lines[i]
        # fenced code
        if line.strip().startswith("```"):
            i += 1
            buf = []
            while i < n and not lines[i].strip().startswith("```"):
                buf.append(html.escape(lines[i]))
                i += 1
            i += 1
            out.append("<pre class='code'>" + "\n".join(buf) + "</pre>")
            continue
        # table
        if "|" in line and i + 1 < n and re.match(r"^\s*\|?[\s:|-]+\|[\s:|-]*$", lines[i + 1]):
            header = cells(line)
            ncol = len(header)
            i += 2
            rows = []
            while i < n and "|" in lines[i] and lines[i].strip():
                row = cells(lines[i])
                # never emit more cells than the header (guards stray pipes)
                if len(row) > ncol:
                    row = row[:ncol - 1] + [" | ".join(row[ncol - 1:])]
                rows.append(row)
                i += 1
            th = "".join(f"<th>{inline(c)}</th>" for c in header)
            trs = "".join("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in r) + "</tr>" for r in rows)
            out.append(f"<table><thead><tr>{th}</tr></thead><tbody>{trs}</tbody></table>")
            continue
        # heading
        m = re.match(r"^(#{1,6})\s+(.*)$", line)
        if m:
            lvl = min(len(m.group(1)) + 2, 6)
            out.append(f"<h{lvl}>{inline(m.group(2))}</h{lvl}>")
            i += 1
            continue
        # list
        if re.match(r"^\s*([-*]|\d+\.)\s+", line):
            ordered = bool(re.match(r"^\s*\d+\.", line))
            tag = "ol" if ordered else "ul"
            items = []
            while i < n and re.match(r"^\s*([-*]|\d+\.)\s+", lines[i]):
                items.append("<li>" + inline(re.sub(r"^\s*([-*]|\d+\.)\s+", "", lines[i])) + "</li>")
                i += 1
            out.append(f"<{tag}>" + "".join(items) + f"</{tag}>")
            continue
        # blank
        if not line.strip():
            i += 1
            continue
        # paragraph
        buf = []
        # NOTE: list markers must be followed by whitespace ([-*]\s / \d+\.\s) so a
        # line that merely *starts* with bold (**text**) is NOT mistaken for a
        # bullet and silently dropped. That bug blanked every **-led SME item.
        while i < n and lines[i].strip() and not re.match(r"^\s*([-*]\s|\d+\.\s|#{1,6}\s|```)", lines[i]) and "|" not in lines[i]:
            buf.append(lines[i].strip())
            i += 1
        if buf:
            out.append("<p>" + inline(" ".join(buf)) + "</p>")
        else:
            i += 1
    return "\n".join(out)


# ----------------------------- parsing helpers -----------------------------
def read(p: Path) -> str:
    return p.read_text(encoding="utf-8") if p.exists() else ""


def section(md: str, title_re: str) -> str:
    m = re.search(rf"^#{{1,6}}\s*[\d.]*\s*{title_re}[^\n]*\n(.*?)(?=^#{{1,6}}\s|\Z)",
                  md, re.S | re.M | re.I)
    return m.group(1).strip() if m else ""


def first_para(md: str) -> str:
    for p in re.split(r"\n\s*\n", md.strip()):
        p = p.strip()
        if p and not p.startswith("#") and not p.startswith("|"):
            return re.sub(r"\s+", " ", p)
    return ""


def val_result(md: str) -> str:
    # first RESULT: in the doc = the fixed file
    m = re.search(r"RESULT:\s*\**\s*(PASS|FAIL)", md, re.I)
    if m:
        return m.group(1).upper()
    if re.search(r"\bPASS\b", md) and not re.search(r"\bFAIL\b", md):
        return "PASS"
    if re.search(r"\bFAIL\b", md):
        return "FAIL"
    return "UNKNOWN"


def count_todo(*mds: str) -> int:
    return sum(len(re.findall(r"TODO\(SME\)", m)) for m in mds)


_SME_EMPTY = {"", "-", "—", "n/a", "na", "none", "none.", "tbd", "todo"}


def sme_items(semantic: str) -> list[str]:
    sec = section(semantic, r"Open SME questions")
    items = []
    for l in sec.splitlines():
        if not re.match(r"^\s*(\d+\.|[-*])\s+", l):
            continue
        t = re.sub(r"^\s*(\d+\.|[-*])\s+", "", l).strip()
        # drop placeholder / blank items so the report never shows an empty
        # numbered list (e.g. "1. 2. 3." with no text)
        if t.lower() not in _SME_EMPTY:
            items.append(t)
    return items


INPUT_DIR = ROOT / "00_input"


def discover() -> list[str]:
    bases = set()
    for f in DIRS["analysis"].glob("analysis_*.md"):
        bases.add(f.name[len("analysis_"):-len(".md")])
    return sorted(bases)


def find_input(base: str) -> Path | None:
    """The original buggy Snowflake input for this unit (exclude .teradata.sql)."""
    cands = [p for p in INPUT_DIR.glob(f"{base}*.sql") if ".teradata." not in p.name]
    cands += [p for p in INPUT_DIR.glob(f"{base}*.snowsql") if ".teradata." not in p.name]
    cands.sort(key=lambda p: len(p.name))  # prefer the closest name match
    return cands[0] if cands else None


def find_final(base: str) -> Path | None:
    for pat in (f"{base}*_final.sql", f"{base}*_final.snowsql",
                f"{base}*_fixed.sql", f"{base}*_fixed.snowsql"):
        c = sorted(FIX_DIR.glob(pat), key=lambda p: len(p.name))
        if c:
            return c[0]
    return None


def find_fixed(base: str) -> Path | None:
    """The mechanically-validated fixed file (prefer *_fixed.sql over *_final.sql)."""
    for pat in (f"{base}*_fixed.sql", f"{base}*_fixed.snowsql",
                f"{base}*_final.sql", f"{base}*_final.snowsql"):
        c = sorted(FIX_DIR.glob(pat), key=lambda p: len(p.name))
        if c:
            return c[0]
    return None


VALIDATE_PY = ROOT / "04_validate" / "validate.py"
_val_cache: dict[str, dict] = {}


def run_validate(path: Path | None) -> dict | None:
    """Run 04_validate/validate.py on a file and capture its output uniformly.

    Returns {"text": <stdout>, "result": PASS|FAIL} or None if the file is
    missing or the validator could not run (caller falls back to the md)."""
    if not path or not path.exists() or not VALIDATE_PY.exists():
        return None
    key = str(path)
    if key in _val_cache:
        return _val_cache[key]
    try:
        proc = subprocess.run([sys.executable, str(VALIDATE_PY), str(path)],
                              capture_output=True, text=True, cwd=str(ROOT), timeout=120)
    except Exception:
        return None
    out = (proc.stdout or "").strip()
    # A missing dependency (e.g. sqlglot) prints to stderr and exits non-zero
    # with no real check output — treat that as "could not run".
    if not out or "not installed" in (proc.stderr or "").lower():
        return None
    m = re.search(r"RESULT:\s*(PASS|FAIL)", out, re.I)
    res = m.group(1).upper() if m else ("FAIL" if proc.returncode else "PASS")
    val = {"text": out, "result": res}
    _val_cache[key] = val
    return val


def parse_fixlog(final_sql: str) -> list[tuple[str, str]]:
    """Extract (rule-id, description) pairs from the FIX LOG comment block."""
    out = []
    for m in re.finditer(r"^--\s*\[([^\]]+)\]\s*(.+)$", final_sql, re.M):
        rid, desc = m.group(1).strip(), m.group(2).strip()
        # skip the SEMANTIC header lines / SEM notes
        if rid.upper().startswith(("SEM-",)) and "kept" not in desc.lower():
            pass
        out.append((rid, desc))
    # de-dupe, keep order
    seen, uniq = set(), []
    for rid, desc in out:
        k = (rid, desc)
        if k not in seen:
            seen.add(k)
            uniq.append((rid, desc))
    return uniq[:40]


# FIX LOG entries that record a *non-change* — not a real issue fixed.
_NOOP_FIX = re.compile(
    r"kept as-is|no rewrite|no change|no truncation|left as-is|already (parses|snowflake)"
    r"|\bpreserved\b|\bverified\b|\bconfirmed\b", re.I)


def count_fixes(fixlog: list[tuple[str, str]]) -> int:
    """Number of real issues repaired for a unit, from its FIX LOG.

    Excludes `[AUTO]` placeholders (files that were already clean) and no-op
    notes like 'kept as-is' / 'verified' — those record that nothing changed."""
    n = 0
    for rid, desc in fixlog:
        if rid.upper() == "AUTO":
            continue
        if _NOOP_FIX.search(desc):
            continue
        n += 1
    return n


_SEM_BLOCK = re.compile(
    r"[ \t]*--[ \t]*<<< SEMANTIC EXPLANATION.*?--[ \t]*>>> SEMANTIC EXPLANATION[^\n]*\n?",
    re.S)


def strip_injected(sql: str) -> str:
    """Remove the generator-injected commentary — the SEMANTIC EXPLANATION header
    block and the top-of-file FIX LOG comment block — so the comparison diff
    reflects only real SQL changes, not the notes the pipeline layers on top.

    Inline annotations tied to specific lines (e.g. `-- SEM ▸ …`) are kept: the
    FIX LOG run is bounded to its own contiguous `--` comment lines and stops at
    the first blank/code line, so annotations after it survive."""
    sql = _SEM_BLOCK.sub("", sql)
    lines = sql.splitlines()
    out, i, n = [], 0, len(lines)
    while i < n:
        if re.match(r"^[ \t]*--[ \t]*FIX LOG\b", lines[i], re.I):
            i += 1
            while i < n and lines[i].lstrip().startswith("--"):
                i += 1
            continue
        out.append(lines[i])
        i += 1
    return "\n".join(out).lstrip("\n")


def side_by_side_diff(a_text: str, b_text: str, wrap_id: str = ""):
    """Return (summary, html) — an aligned, highlighted original-vs-final diff."""
    a, b = a_text.splitlines(), b_text.splitlines()
    sm = difflib.SequenceMatcher(a=a, b=b, autojunk=False)
    rows, add, rem, chg = [], 0, 0, 0
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == "equal":
            for k in range(i2 - i1):
                rows.append((i1 + k + 1, a[i1 + k], "eq", j1 + k + 1, b[j1 + k], "eq"))
        elif tag == "replace":
            left, right = a[i1:i2], b[j1:j2]
            m = max(len(left), len(right)); chg += m
            for k in range(m):
                ln, lt, lc = (i1 + k + 1, left[k], "chg") if k < len(left) else ("", None, "pad")
                rn, rt, rc = (j1 + k + 1, right[k], "chg") if k < len(right) else ("", None, "pad")
                rows.append((ln, lt, lc, rn, rt, rc))
        elif tag == "delete":
            for k in range(i1, i2):
                rem += 1; rows.append((k + 1, a[k], "del", "", None, "pad"))
        elif tag == "insert":
            for k in range(j1, j2):
                add += 1; rows.append(("", None, "pad", k + 1, b[k], "ins"))
    trs = []
    for ln, lt, lc, rn, rt, rc in rows:
        lcode = "" if lt is None else html.escape(lt)
        rcode = "" if rt is None else html.escape(rt)
        trs.append(f"<tr><td class='ln'>{ln}</td><td class='dl {lc}'>{lcode}</td>"
                   f"<td class='ln'>{rn}</td><td class='dl {rc}'>{rcode}</td></tr>")
    summary = (f"<b style='color:var(--ok)'>{add}</b> added · "
               f"<b style='color:var(--bad)'>{rem}</b> removed · "
               f"<b style='color:var(--warn)'>{chg}</b> changed line(s)")
    if add == rem == chg == 0:
        summary = "<b>No line-level differences</b> between original and final."
    wid = f" id='{wrap_id}'" if wrap_id else ""
    table = (f"<div class='diffwrap'{wid}><table class='diff2'>"
             "<colgroup><col class='lncol'><col><col class='lncol'><col></colgroup>"
             "<thead><tr>"
             "<th class='ln'>#</th><th class='o'>Original (as delivered)</th>"
             "<th class='ln'>#</th><th class='f'>Final (remediated)</th></tr></thead><tbody>"
             + "".join(trs) + "</tbody></table></div>")
    return summary, table


def build_unit(base: str) -> dict:
    analysis = read(DIRS["analysis"] / f"analysis_{base}.md")
    report = read(DIRS["report"] / f"fix_report_{base}.md")
    semantic = read(DIRS["semantic"] / f"semantic_{base}.md")
    validation = read(DIRS["validation"] / f"validation_{base}.md")
    review = read(REVIEW_DIR / f"review_{base}.md")
    purpose = first_para(section(semantic, r"Purpose")) or first_para(semantic) or first_para(report)

    in_path = find_input(base)
    fin_path = find_final(base)
    original_sql = read(in_path) if in_path else ""
    final_sql = read(fin_path) if fin_path else ""

    # Uniform validation: the generator runs validate.py itself so every unit's
    # Validation tab has the identical layout, regardless of how the stage-4
    # markdown was hand-written. Falls back to the md if the validator can't run.
    val_fixed = run_validate(find_fixed(base))
    val_buggy = run_validate(in_path)
    status = (val_fixed["result"] if val_fixed else val_result(validation))

    stages = {
        "01 Analyze": bool(analysis),
        "03 Fix": bool(fin_path),
        "04 Validate": bool(validation),
        "05 Report": bool(report),
        "06 Explain": bool(semantic),
    }
    return {
        "base": base,
        "purpose": purpose or "—",
        "status": status,
        "val_fixed": val_fixed,
        "val_buggy": val_buggy,
        "todos": count_todo(semantic, report),
        "sme": sme_items(semantic),
        "stages": stages,
        "has_final": bool(fin_path),
        "final_name": fin_path.name if fin_path else f"{base}_final.sql",
        "input_name": in_path.name if in_path else "",
        "original_sql": original_sql,
        "final_sql": final_sql,
        "fixlog": parse_fixlog(final_sql),
        "fixes": count_fixes(parse_fixlog(final_sql)),
        "review": review,
        "md": {"analysis": analysis, "report": report, "semantic": semantic, "validation": validation},
    }


# ----------------------------- HTML -----------------------------
CSS = """
:root{--bg:#fff;--panel:#f6f8fa;--panel2:#eef1f4;--border:#d0d7de;--txt:#1f2328;
--muted:#57606a;--accent:#0969da;--sf:#29b5e8;--sf2:#0550ae;--ok:#1a7f37;--warn:#9a6700;
--bad:#cf222e;--sme:#8250df;--mono:'SF Mono',ui-monospace,Consolas,Menlo,monospace}
*{box-sizing:border-box;margin:0;padding:0}
html,body{max-width:100%;overflow-x:hidden}
body{background:var(--bg);color:var(--txt);font:15px/1.55 -apple-system,'Segoe UI',Roboto,sans-serif;padding:24px 28px 60px}
.wrap{max-width:min(2000px,98vw);margin:0 auto}
h1{font-size:25px}h1 .sf{color:var(--sf2)}
.sub{color:var(--muted);margin:6px 0 20px;max-width:900px}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:12px;margin:14px 0}
.card{background:var(--panel);border:1px solid var(--border);border-radius:10px;padding:14px 16px}
.card .big{font-size:26px;font-weight:700}.card .lbl{color:var(--muted);font-size:13px}
.card.ok .big{color:var(--ok)}.card.bad .big{color:var(--bad)}.card.sme .big{color:var(--sme)}
.card.fix .big{color:var(--sf2)}
h2{font-size:18px;margin:26px 0 10px}
table{border-collapse:collapse;width:100%;margin:10px 0;font-size:13.5px}
th,td{border:1px solid var(--border);padding:6px 9px;text-align:left;vertical-align:top}
th{background:var(--panel)}tbody tr:nth-child(even){background:var(--panel)}
.matrix td.y{color:var(--ok);font-weight:700;text-align:center}
.matrix td.n{color:var(--border);text-align:center}
.badge{display:inline-block;font:600 11px var(--mono);padding:2px 8px;border-radius:20px;color:#fff}
.badge.pass{background:var(--ok)}.badge.fail{background:var(--bad)}.badge.unknown{background:var(--warn)}
.layout{display:grid;grid-template-columns:250px minmax(0,1fr);gap:18px;margin-top:14px}
.layout>div{min-width:0}
.detail,.dbody,.unit,.dpane{min-width:0;max-width:100%}
.dbody table{display:block;overflow-x:auto;max-width:100%}
.dbody pre.code{max-width:100%}
.side{border:1px solid var(--border);border-radius:10px;overflow:hidden;height:fit-content}
.side button{display:block;width:100%;text-align:left;background:var(--bg);border:none;
border-bottom:1px solid var(--border);padding:11px 14px;cursor:pointer;font:inherit;transition:background .12s}
.side button:hover{background:var(--panel2)}
.side button.active{background:var(--sf2);color:#fff}
.side button .st{font:600 10px var(--mono);opacity:.8;display:block;margin-top:2px}
.detail{border:1px solid var(--border);border-radius:10px;padding:0}
.detail .dhead{padding:16px 20px;border-bottom:1px solid var(--border);background:var(--panel)}
.detail .dhead h3{font-size:18px}
.subtabs{display:flex;gap:2px;padding:0 12px;border-bottom:1px solid var(--border);flex-wrap:wrap}
.subtabs button{background:none;border:none;border-bottom:2px solid transparent;padding:10px 14px;
cursor:pointer;font:600 14px inherit;color:var(--muted);margin-bottom:-1px}
.subtabs button.active{color:var(--accent);border-bottom-color:var(--accent)}
.dbody{padding:16px 20px}
.dpane{display:none}.dpane.active{display:block}
.unit{display:none}.unit.active{display:block}
.code{font:12px/1.5 var(--mono);background:#0d1117;color:#e6edf3;border-radius:8px;padding:12px 14px;overflow-x:auto;white-space:pre;margin:8px 0}
.dbody h4,.dbody h5{margin:14px 0 6px}.dbody p{margin:8px 0}.dbody ul,.dbody ol{margin:8px 0 8px 20px}
.dbody code{font:12.5px var(--mono);background:var(--panel2);padding:1px 5px;border-radius:5px}
.muted{color:var(--muted)}.links a{color:var(--accent);margin-right:14px}
.footer{color:var(--muted);font-size:13px;margin-top:26px;border-top:1px solid var(--border);padding-top:12px}
/* comparison — highlighted aligned diff */
.diffsummary{font-size:13.5px;margin:2px 0 4px}
.difflegend{font-size:12px;color:var(--muted);margin:2px 0 10px}
.difflegend span{padding:1px 7px;border-radius:4px;margin-right:8px}
.difflegend .a{background:#e6ffec}.difflegend .r{background:#ffebe9}.difflegend .c{background:#fff8c5}
.difftoolbar{display:flex;align-items:center;gap:10px;margin:2px 0 8px}
.diffwrap{border:1px solid var(--border);border-radius:8px;overflow:auto;max-height:580px}
/* fixed 50/50 layout: the two code columns always split the width evenly, so a
   long line on the Final side can never squeeze the Original side to nothing */
.diff2{border-collapse:collapse;width:100%;table-layout:fixed;font:11.5px/1.55 var(--mono)}
.diff2 col.lncol{width:46px}
.diff2 th{position:sticky;top:0;background:var(--panel);z-index:1;text-align:left;padding:6px 8px;border-bottom:1px solid var(--border)}
.diff2 th.o{color:var(--bad)}.diff2 th.f{color:var(--ok)}
/* default: wrap long lines so the whole diff is readable with NO horizontal
   scrolling; row alignment is preserved because both cells share the <tr> */
.diff2 td{padding:0 8px;white-space:pre-wrap;overflow-wrap:anywhere;word-break:break-word;vertical-align:top;border-bottom:1px solid #f2f2f2}
.diff2 td.ln{color:var(--muted);text-align:right;user-select:none;background:var(--panel);padding:0 6px;white-space:nowrap}
/* no-wrap mode (toggled): single-line rows + an always-visible horizontal
   scrollbar (not the macOS overlay bar that stays hidden until you swipe) */
.diffwrap.nowrap{overflow-x:scroll}
.diffwrap.nowrap .diff2{table-layout:auto;width:max-content;min-width:100%}
.diffwrap.nowrap .diff2 td{white-space:pre;overflow-wrap:normal;word-break:normal}
.diffwrap.nowrap .diff2 td.dl{min-width:360px}
.diffwrap::-webkit-scrollbar{height:13px;width:13px}
.diffwrap::-webkit-scrollbar-thumb{background:#b6bec7;border-radius:7px;border:3px solid var(--panel)}
.diffwrap::-webkit-scrollbar-thumb:hover{background:#98a2ac}
.diffwrap::-webkit-scrollbar-track{background:var(--panel)}
.diff2 td.del{background:#ffebe9}.diff2 td.ins{background:#e6ffec}.diff2 td.chg{background:#fff8c5}
.diff2 td.pad{background:#fafbfc}
.changes td:first-child{font:600 11px var(--mono);white-space:nowrap;color:var(--sf2)}
/* editor + toolbar */
.toolbar{display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin:4px 0 12px;
padding:8px 10px;background:var(--panel);border:1px solid var(--border);border-radius:8px}
.toolbar .note{color:var(--muted);font-size:13px;margin-right:auto}
.btn{font:600 12.5px inherit;padding:6px 11px;border-radius:7px;border:1px solid var(--border);
background:var(--bg);color:var(--txt);cursor:pointer}
.btn:hover{background:var(--panel2)}
.btn.primary{background:var(--accent);border-color:var(--accent);color:#fff}
.btn.primary:hover{filter:brightness(1.08)}
.sem-edit{display:none;width:100%;min-height:360px;font:12.5px/1.55 var(--mono);
border:1px solid var(--border);border-radius:8px;padding:12px;color:var(--txt);background:#fffef7;resize:vertical}
.editing .sem-edit{display:block}.editing .sem-rendered{display:none}
.review-edit{display:block;width:100%;min-height:240px;font:13.5px/1.6 -apple-system,'Segoe UI',Roboto,sans-serif;
border:1px solid var(--border);border-radius:8px;padding:12px;color:var(--txt);background:#fffef7;resize:vertical;margin:8px 0}
.toast{position:fixed;bottom:20px;left:50%;transform:translateX(-50%);background:#1f2328;color:#fff;
padding:10px 16px;border-radius:8px;font-size:13px;opacity:0;transition:opacity .2s;pointer-events:none;z-index:99}
.toast.show{opacity:1}
"""

JS = """
document.querySelectorAll('.side button').forEach(function(b){
  b.addEventListener('click',function(){
    document.querySelectorAll('.side button').forEach(x=>x.classList.remove('active'));
    document.querySelectorAll('.unit').forEach(x=>x.classList.remove('active'));
    b.classList.add('active');
    document.getElementById('unit-'+b.dataset.u).classList.add('active');
  });
});
document.querySelectorAll('.subtabs button').forEach(function(b){
  b.addEventListener('click',function(){
    var scope=b.closest('.unit,.rulesbox');
    scope.querySelectorAll('.subtabs button').forEach(x=>x.classList.remove('active'));
    scope.querySelectorAll('.dpane').forEach(x=>x.classList.remove('active'));
    b.classList.add('active');
    scope.querySelector('#'+b.dataset.pane).classList.add('active');
  });
});

// Comparison diff: toggle line-wrapping (default on = no horizontal scroll).
// Off => single-line rows with an always-visible horizontal scrollbar.
document.querySelectorAll('[data-wrap]').forEach(function(b){
  b.addEventListener('click',function(){
    var w=document.getElementById(b.dataset.wrap);
    if(!w) return;
    var off=w.classList.toggle('nowrap');
    b.textContent=off?'Wrap: off':'Wrap: on';
  });
});

function toast(msg){var t=document.getElementById('toast');t.textContent=msg;t.classList.add('show');
  setTimeout(()=>t.classList.remove('show'),2200);}
function download(name,text,type){var b=new Blob([text],{type:type||'text/plain'});
  var a=document.createElement('a');a.href=URL.createObjectURL(b);a.download=name;
  document.body.appendChild(a);a.click();a.remove();URL.revokeObjectURL(a.href);}
// POST to the local serve_report.py backend. Rejects when the page is opened
// via file:// (no server) so callers can fall back to a plain download.
function post(path,payload){
  if(location.protocol==='file:') return Promise.reject(new Error('no server'));
  return fetch(path,{method:'POST',headers:{'Content-Type':'application/json'},
    body:JSON.stringify(payload)}).then(function(res){
      if(!res.ok) throw new Error('HTTP '+res.status); return res.json();});}
function currentSemantic(idx){var ta=document.getElementById('semta-'+idx);
  return ta && ta.value!=null ? ta.value : (UNITS[idx].semantic||'');}
function semHeader(sem){
  var body=sem.split('\\n').map(l=>l.length?'-- '+l:'--').join('\\n');
  return '-- <<< SEMANTIC EXPLANATION (added from report.html)\\n'+body+
         '\\n-- >>> SEMANTIC EXPLANATION\\n\\n';}
function stripHeader(sql){
  return sql.replace(/-- <<< SEMANTIC EXPLANATION[\\s\\S]*?-- >>> SEMANTIC EXPLANATION\\n?\\n?/,'');}

// synchronized scrolling for the original-vs-final comparison panes
document.querySelectorAll('table.cmp').forEach(function(t){
  var pres=t.querySelectorAll('pre');
  if(pres.length<2) return;
  var a=pres[0], b=pres[1], lock=false;
  function link(src,dst){
    src.addEventListener('scroll',function(){
      if(lock) return; lock=true;
      dst.scrollTop=src.scrollTop; dst.scrollLeft=src.scrollLeft;
      requestAnimationFrame(function(){lock=false;});
    });
  }
  link(a,b); link(b,a);
});

document.querySelectorAll('[data-act]').forEach(function(b){
  b.addEventListener('click',function(){
    var idx=b.dataset.idx, u=UNITS[idx], act=b.dataset.act;
    if(act==='edit'){
      var pane=document.getElementById('se-'+idx);
      pane.classList.toggle('editing');
      b.textContent=pane.classList.contains('editing')?'Editing — click to preview':'Edit';
    }else if(act==='save'){
      var content=currentSemantic(idx);
      post('/save',{base:u.base,content:content}).then(function(r){
        toast('Saved → '+(r.path||'06_explain/output/semantic_'+u.base+'.md'));
      }).catch(function(){
        download('semantic_'+u.base+'.md', content, 'text/markdown');
        toast('No local server — downloaded instead. Run 05_report/serve_report.py to save directly.');
      });
    }else if(act==='prepend'){
      var sql=semHeader(currentSemantic(idx))+stripHeader(u.final||'');
      download(u.final_name, sql, 'text/plain');
      toast('Downloaded '+u.final_name+' with semantic header at the top');
    }else if(act==='reremediate'){
      var content=currentSemantic(idx);
      var old=b.textContent; b.disabled=true; b.textContent='Triggering…';
      post('/reremediate',{base:u.base,content:content,input_name:u.input_name||''}).then(function(r){
        toast(r.opened
          ? 's2s-remediate triggered for '+u.base+' — opening in VS Code'
          : 'Re-remediate queued for '+u.base+' — open the prompt shown below in Copilot');
        var box=document.getElementById('reprompt-'+idx);
        if(box && r.prompt){box.style.display='block';box.textContent=r.prompt;}
      }).catch(function(){
        // no server: fall back to the old download + clipboard behavior
        download('semantic_'+u.base+'.md', content, 'text/markdown');
        var prompt='@s2s-remediate Re-remediate '+u.base+' using my updated semantics.\\n'+
          '1. I saved an enriched 06_explain/output/semantic_'+u.base+'.md — read it as authoritative reviewer guidance.\\n'+
          '2. Re-run the pipeline on 00_input/'+(u.input_name||u.base+'.sql')+', honoring the clarifications and SME answers in that file.\\n'+
          '3. Then re-run 06_explain/annotate.py and python3 05_report/build_report.py.';
        if(navigator.clipboard){navigator.clipboard.writeText(prompt);}
        var box=document.getElementById('reprompt-'+idx); if(box){box.style.display='block';box.textContent=prompt;}
        toast('No local server — saved md + copied prompt. Run 05_report/serve_report.py to auto-trigger.');
      }).finally(function(){b.disabled=false;b.textContent=old;});
    }else if(act==='savereview'){
      var ta=document.getElementById('revta-'+idx);
      var content=ta?ta.value:'';
      post('/save_review',{base:u.base,content:content}).then(function(r){
        toast('Saved → '+(r.path||'07_review/output/review_'+u.base+'.md'));
      }).catch(function(){
        download('review_'+u.base+'.md', content, 'text/markdown');
        toast('No local server — downloaded instead. Run 05_report/serve_report.py to save directly.');
      });
    }else if(act==='reremediatereview'){
      var ta=document.getElementById('revta-'+idx);
      var content=ta?ta.value:'';
      var old=b.textContent; b.disabled=true; b.textContent='Triggering…';
      post('/reremediate_review',{base:u.base,content:content,input_name:u.input_name||''}).then(function(r){
        toast(r.opened
          ? 's2s-remediate triggered for '+u.base+' — opening in VS Code'
          : 'Re-remediate queued for '+u.base+' — open the prompt shown below in Copilot');
        var box=document.getElementById('revprompt-'+idx);
        if(box && r.prompt){box.style.display='block';box.textContent=r.prompt;}
      }).catch(function(){
        download('review_'+u.base+'.md', content, 'text/markdown');
        var prompt='@s2s-remediate Re-remediate '+u.base+' using my review comments.\\n'+
          '1. I saved reviewer comments to 07_review/output/review_'+u.base+'.md — read them as authoritative reviewer guidance and address every point.\\n'+
          '2. Re-run the pipeline on 00_input/'+(u.input_name||u.base+'.sql')+', honoring every comment.\\n'+
          '3. Then re-run 06_explain/annotate.py and python3 05_report/build_report.py.';
        if(navigator.clipboard){navigator.clipboard.writeText(prompt);}
        var box=document.getElementById('revprompt-'+idx); if(box){box.style.display='block';box.textContent=prompt;}
        toast('No local server — saved md + copied prompt. Run 05_report/serve_report.py to auto-trigger.');
      }).finally(function(){b.disabled=false;b.textContent=old;});
    }
  });
});
"""


def esc(s: str) -> str:
    return html.escape(s)


def validation_pane(u: dict) -> str:
    """Render the Validation tab in ONE standard layout for every unit:
    a 'Final SQL' block and a 'Buggy input control' block, both showing
    validate.py output. If the validator could not run for this unit, fall
    back to the stage-4 markdown so nothing is lost."""
    vf, vb = u.get("val_fixed"), u.get("val_buggy")
    if not vf and not vb:
        return md_to_html(u["md"]["validation"])

    def block(title: str, val: dict | None, missing: str) -> str:
        if not val:
            return f"<h4>{title}</h4><p class='muted'>{missing}</p>"
        return (f"<h4>{title} <span class='badge {val['result'].lower()}'>{val['result']}</span></h4>"
                f"<pre class='code'>{esc(val['text'])}</pre>")

    out = [f"<h3>Validation — <code>{esc(u['base'])}</code></h3>",
           block("Final SQL", vf, "No fixed SQL found for this unit."),
           block("Buggy input control", vb, "No buggy input found for this unit.")]

    # Standard, auto-generated note: if the buggy control PASSes the mechanical
    # checks, the defect is semantic — a parser cannot catch it, so a green
    # control is NOT evidence the delivered file was correct.
    if vb and vb["result"] == "PASS":
        out.append(
            "<p class='muted'><b>Note:</b> the buggy input also parses PASS — "
            "the defect for this unit is <b>semantic</b>, so the mechanical "
            "validator cannot distinguish good from bad. A green control here is "
            "not evidence the delivered file was correct; see the Semantic tab.</p>")
    else:
        out.append(
            "<p class='muted'>The control fails as expected — proof the defects "
            "were real and that the validator catches them. Every failure maps to "
            "a fix applied in Stage 3.</p>")
    return "\n".join(out)


def rules_pane() -> str:
    """One shared, report-level tabbed panel showing the 02_rules/ knowledge
    base — the same rules every remediation run reads. One sub-tab per file."""
    files = sorted(RULES_DIR.glob("*.md"))
    if not files:
        return ""

    def label(p: Path) -> str:
        name = re.sub(r"^\d+[_-]", "", p.stem)          # drop leading "01_"
        name = name.replace("_", " ").strip()
        if "readme" in name.lower():
            return "Overview"
        return name[:1].upper() + name[1:]

    tabs, panes = "", ""
    for i, p in enumerate(files):
        pid = f"ru-{i}"
        act = " active" if i == 0 else ""
        tabs += f"<button class='{act.strip()}' data-pane='{pid}'>{esc(label(p))}</button>"
        panes += f"<div class='dpane{act}' id='{pid}'>{md_to_html(read(p))}</div>"

    return (
        "<div class='rulesbox detail'>"
        "<div class='dhead'><h3>Rules — knowledge base</h3>"
        "<span class='muted'> · read on every run from <code>02_rules/</code></span></div>"
        f"<div class='subtabs'>{tabs}</div>"
        f"<div class='dbody'>{panes}</div>"
        "</div>")


def render(units: list[dict]) -> str:
    total = len(units)
    passed = sum(1 for u in units if u["status"] == "PASS")
    failed = sum(1 for u in units if u["status"] == "FAIL")
    sme_total = sum(len(u["sme"]) or u["todos"] for u in units)
    fixes_total = sum(u["fixes"] for u in units)
    stage_names = ["01 Analyze", "03 Fix", "04 Validate", "05 Report", "06 Explain"]

    # summary matrix
    mrows = ""
    for u in units:
        cells = "".join(
            f"<td class='{'y' if u['stages'][s] else 'n'}'>{'✓' if u['stages'][s] else '·'}</td>"
            for s in stage_names)
        badge = u["status"].lower()
        mrows += (f"<tr><td><b>{esc(u['base'])}</b></td>{cells}"
                  f"<td><span class='badge {badge}'>{u['status']}</span></td>"
                  f"<td style='text-align:center'>{u['fixes']}</td>"
                  f"<td style='text-align:center'>{len(u['sme']) or u['todos']}</td></tr>")
    matrix = ("<table class='matrix'><thead><tr><th>Unit</th>"
              + "".join(f"<th>{s}</th>" for s in stage_names)
              + "<th>Validation</th><th>Issues&nbsp;fixed</th><th>SME</th></tr></thead><tbody>"
              + mrows + "</tbody></table>"
              + "<p class='muted' style='font-size:12.5px;margin-top:4px'>"
              + "Stage <b>02 (<code>02_rules/</code>)</b> is the shared rules knowledge base read on "
              + "every run — not a per-file stage, so it has no column here. Numbering follows the "
              + "folder names (<code>00_input</code>, <code>01_analyze</code>, <code>02_rules</code>, "
              + "<code>03_fix</code>, <code>04_validate</code>, <code>05_report</code>, "
              + "<code>06_explain</code>).</p>")

    # sidebar + units
    side, panes = "", ""
    for idx, u in enumerate(units):
        b = u["base"]
        active = " active" if idx == 0 else ""
        side += (f"<button class='{'active' if idx==0 else ''}' data-u='{idx}'>{esc(b)}"
                 f"<span class='st'>{u['status']} · {len(u['sme']) or u['todos']} SME</span></button>")

        links = []
        for label, d, pre in [("Analysis", "analysis", "01_analyze/output/analysis_"),
                              ("Fix report", "report", "05_report/output/fix_report_"),
                              ("Validation", "validation", "04_validate/output/validation_"),
                              ("Semantic", "semantic", "06_explain/output/semantic_")]:
            links.append(f"<a href='{pre}{esc(b)}.md'>{label}</a>")
        if u["has_final"]:
            links.append(f"<a href='03_fix/output/{esc(b)}_final.sql'>Final SQL (with comments)</a>")
        elif list(FIX_DIR.glob(f"{b}*_fixed.sql")):
            fx = list(FIX_DIR.glob(f"{b}*_fixed.sql"))[0].name
            links.append(f"<a href='03_fix/output/{esc(fx)}'>Fixed SQL</a>")

        sme_html = ("<ol>" + "".join(f"<li>{md_inline(q)}</li>"
                    for q in u["sme"]) + "</ol>") if u["sme"] else "<p class='muted'>None open.</p>"

        fixes_note = ("<span class='muted'> — input was already clean (no repairs "
                      "needed)</span>" if u["fixes"] == 0 else "")
        overview = (f"<h4>Purpose</h4><p>{esc(u['purpose'])}</p>"
                    f"<h4>Validation</h4><p><span class='badge {u['status'].lower()}'>{u['status']}</span></p>"
                    f"<h4>Issues fixed</h4><p><b>{u['fixes']}</b>{fixes_note}</p>"
                    f"<h4>Open SME questions</h4>{sme_html}"
                    f"<h4>Artifacts</h4><p class='links'>{''.join(links)}</p>")

        # --- Comparison sub-tab: highlighted diff + issues + changes ---
        # Strip the pipeline-injected SEMANTIC EXPLANATION + FIX LOG comment blocks
        # from the final so the diff shows only real SQL changes.
        final_for_diff = strip_injected(u["final_sql"])
        diff_summary, diff_html = side_by_side_diff(
            u["original_sql"], final_for_diff, wrap_id=f"diffwrap-{idx}")
        # issues from Stage-1 analysis (Findings/table)
        findings = section(u["md"]["analysis"], r"Findings") or section(u["md"]["analysis"], r"Defects")
        issues_html = ("<h4>Issues identified <span class='muted' style='font-weight:400'>"
                       "(from Stage-1 analysis)</span></h4>" + md_to_html(findings)) if findings.strip() else ""
        if u["fixlog"]:
            chg = "".join(f"<tr><td>[{esc(r)}]</td><td>{esc(d)}</td></tr>" for r, d in u["fixlog"])
            changes = ("<h4>Changes applied <span class='muted' style='font-weight:400'>"
                       "(from the FIX LOG)</span></h4><table class='changes'><thead><tr><th>Rule</th>"
                       "<th>What changed</th></tr></thead><tbody>" + chg + "</tbody></table>")
        else:
            changes = "<h4>Changes applied</h4><p class='muted'>No FIX LOG entries parsed for this unit.</p>"
        comparison = (
            f"<h4>Original → Final &nbsp;<code>{esc(u['input_name'] or b+'.sql')}</code> → "
            f"<code>{esc(u['final_name'])}</code></h4>"
            f"<p class='diffsummary'>{diff_summary}</p>"
            "<div class='difftoolbar'>"
            "<p class='difflegend' style='margin:0'><span class='r'>removed</span>"
            "<span class='a'>added</span><span class='c'>changed</span> — rows are aligned; "
            "injected SEMANTIC EXPLANATION &amp; FIX LOG comments are excluded so only real SQL changes show."
            "</p>"
            f"<button class='btn' data-wrap='diffwrap-{idx}'>Wrap: on</button>"
            "</div>"
            + diff_html + issues_html + changes)

        # --- Semantic sub-tab: editable + save/prepend/re-remediate ---
        semantic_pane = (
            "<div class='toolbar'>"
            "<span class='note'>Edit the semantic explanation, then Save "
            "(writes the .md directly when served via serve_report.py), or "
            "Re-remediate to trigger the s2s-remediate agent for this script.</span>"
            f"<button class='btn' data-act='edit' data-idx='{idx}'>Edit</button>"
            f"<button class='btn' data-act='save' data-idx='{idx}'>Save .md</button>"
            f"<button class='btn' data-act='prepend' data-idx='{idx}'>Prepend to final SQL</button>"
            f"<button class='btn primary' data-act='reremediate' data-idx='{idx}'>Re-remediate…</button>"
            "</div>"
            f"<div class='sem-rendered'>{md_to_html(u['md']['semantic'])}</div>"
            f"<textarea class='sem-edit' id='semta-{idx}'>{esc(u['md']['semantic'])}</textarea>"
            f"<pre class='code' id='reprompt-{idx}' style='display:none'></pre>")

        # --- Review comments sub-tab: reviewer feedback on the fixed SQL ---
        review_pane = (
            "<div class='toolbar'>"
            "<span class='note'>Comment on the <b>fixed SQL</b> for this unit, then "
            "<b>Save comments</b> (writes <code>07_review/output/review_"
            f"{esc(b)}.md</code> when served via serve_report.py), or "
            "<b>Re-remediate</b> to trigger the <code>s2s-remediate</code> agent with "
            "your comments as authoritative reviewer guidance.</span>"
            f"<button class='btn' data-act='savereview' data-idx='{idx}'>Save comments</button>"
            f"<button class='btn primary' data-act='reremediatereview' data-idx='{idx}'>Re-remediate…</button>"
            "</div>"
            f"<textarea class='review-edit' id='revta-{idx}' "
            "placeholder='Add your review comments on the fixed SQL for this unit…'>"
            f"{esc(u['review'])}</textarea>"
            f"<pre class='code' id='revprompt-{idx}' style='display:none'></pre>")

        panes += f"""
        <div class="unit{active}" id="unit-{idx}">
          <div class="detail">
            <div class="dhead"><h3>{esc(b)}</h3>
              <span class="badge {u['status'].lower()}">{u['status']}</span>
              <span class="muted"> · {len(u['sme']) or u['todos']} open SME item(s)</span>
            </div>
            <div class="subtabs">
              <button class="active" data-pane="ov-{idx}">Overview</button>
              <button data-pane="cp-{idx}">Comparison</button>
              <button data-pane="fx-{idx}">Fixes</button>
              <button data-pane="se-{idx}">Semantic</button>
              <button data-pane="va-{idx}">Validation</button>
              <button data-pane="rv-{idx}">Review comments</button>
            </div>
            <div class="dbody">
              <div class="dpane active" id="ov-{idx}">{overview}</div>
              <div class="dpane" id="cp-{idx}">{comparison}</div>
              <div class="dpane" id="fx-{idx}">{md_to_html(u['md']['report'])}</div>
              <div class="dpane" id="se-{idx}">{semantic_pane}</div>
              <div class="dpane" id="va-{idx}">{validation_pane(u)}</div>
              <div class="dpane" id="rv-{idx}">{review_pane}</div>
            </div>
          </div>
        </div>"""

    # data for the client-side save / prepend / re-remediate actions
    data = {str(i): {"base": u["base"], "input_name": u["input_name"],
                     "final_name": u["final_name"], "final": u["final_sql"],
                     "semantic": u["md"]["semantic"], "review": u["review"]}
            for i, u in enumerate(units)}
    units_json = json.dumps(data, ensure_ascii=False).replace("</", "<\\/")

    return f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Snowflake → Snowflake · Remediation Report</title>
<style>{CSS}</style></head><body>
<div class="wrap">
  <h1><span class="sf">Snowflake → Snowflake</span> · Remediation Report</h1>
  <p class="sub">Generated from the ICM stage outputs by <code>05_report/build_report.py</code> —
  {total} remediation unit(s). Pick a unit on the left; each has Overview, Comparison, Fixes,
  Semantic, Validation, and Review-comments views built from that unit's stage artifacts.</p>
  <div class="cards">
    <div class="card"><div class="big">{total}</div><div class="lbl">Units</div></div>
    <div class="card ok"><div class="big">{passed}</div><div class="lbl">Validated PASS</div></div>
    <div class="card bad"><div class="big">{failed}</div><div class="lbl">Validation FAIL</div></div>
    <div class="card fix"><div class="big">{fixes_total}</div><div class="lbl">Issues fixed</div></div>
    <div class="card sme"><div class="big">{sme_total}</div><div class="lbl">Open SME items</div></div>
  </div>
  <h2>Stage-completion matrix</h2>
  {matrix}
  <h2>Rules</h2>
  {rules_pane()}
  <h2>Unit detail</h2>
  <div class="layout">
    <div class="side">{side}</div>
    <div>{panes}</div>
  </div>
  <div class="footer">Regenerated by <code>05_report/build_report.py</code>. Re-run it (or the VS Code task
  <b>S2S: Refresh interactive report</b>) after every remediation — do not hand-edit this file.
  Serve it with <code>python3 05_report/serve_report.py</code> so the Semantic tab can save into
  <code>06_explain/output/</code> and trigger re-remediation directly; opened from <code>file://</code>
  those buttons fall back to downloads.</div>
</div>
<div class="toast" id="toast"></div>
<script>const UNITS = {units_json};</script>
<script>{JS}</script>
</body></html>"""


def main():
    units = [build_unit(b) for b in discover()]
    if not units:
        sys.exit("No units found — run at least Stage 1 (analyze) first.")
    out = ROOT / "report.html"
    out.write_text(render(units), encoding="utf-8")
    print(f"OK  wrote {out} from {len(units)} unit(s): {', '.join(u['base'] for u in units)}")
    if "--open" in sys.argv:
        print(f"    open: {out}")


if __name__ == "__main__":
    main()
