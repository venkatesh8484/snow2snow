#!/usr/bin/env python3
"""Archive generated stage outputs so a re-run starts from a clean slate.

`report.html` is built by scanning the stage `output/` folders (analysis_*.md,
*_fixed.sql, validation_*.md, ...). Re-running the pipeline leaves the previous
run's files behind, so stale artifacts from inputs that no longer exist leak
into the next report. Run THIS before a fresh run: it moves the generated
outputs into `_archive/<timestamp>/` (preserving their stage path), leaving the
output folders holding only what the current `00_input/` files regenerate.

What is moved (generated OUTPUTS only), by stage:
    01_analyze/output/   analysis_*.md
    03_fix/output/       *_fixed.sql, *_final.sql
    04_validate/output/  validation_*.md
    05_report/output/    fix_report_*.md, reremediate_*.prompt.md
    06_explain/output/   semantic_*.md

What is NEVER touched (these are INPUTS to a run, not generated outputs):
    00_input/            the source SQL — the single source of truth
    02_rules/            the knowledge base
    07_review/output/    reviewer comments (consumed as guidance by re-remediation)
    04_validate/output/test_schema.sql and any other fixtures (not matched above)

Usage:
    python3 05_report/archive_outputs.py                 # full sweep (all units)
    python3 05_report/archive_outputs.py SFIssueSET      # just this unit's outputs
    python3 05_report/archive_outputs.py A B C            # several units
    python3 05_report/archive_outputs.py --include-review # also archive 07_review
    python3 05_report/archive_outputs.py --dry-run        # show, move nothing
"""
from __future__ import annotations

import argparse
import datetime as dt
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ARCHIVE_ROOT = ROOT / "_archive"

# Generated outputs, per stage output dir -> glob patterns that identify them.
# Anything not matching a pattern here (e.g. test_schema.sql, .gitkeep) is left
# in place — only real generated artifacts are archived.
STAGE_OUTPUTS: dict[Path, list[str]] = {
    ROOT / "01_analyze" / "output": ["analysis_*.md"],
    ROOT / "03_fix" / "output": ["*_fixed.sql", "*_final.sql"],
    ROOT / "04_validate" / "output": ["validation_*.md"],
    ROOT / "05_report" / "output": ["fix_report_*.md", "reremediate_*.prompt.md"],
    ROOT / "06_explain" / "output": ["semantic_*.md"],
}
REVIEW_DIR = ROOT / "07_review" / "output"


def all_output_files() -> list[Path]:
    """Every generated output file across all stages (full-sweep mode)."""
    seen: dict[Path, Path] = {}
    for d, pats in STAGE_OUTPUTS.items():
        for pat in pats:
            for p in d.glob(pat):
                if p.is_file():
                    seen[p.resolve()] = p
    return sorted(seen.values())


def files_for_base(base: str, include_review: bool) -> list[Path]:
    """Exactly this unit's generated outputs — matched by exact filename so a
    prefix like `ins_wrk_dc_priority` never sweeps up `ins_wrk_dc_priority_snowflake`."""
    named = [
        ROOT / "01_analyze" / "output" / f"analysis_{base}.md",
        ROOT / "03_fix" / "output" / f"{base}_fixed.sql",
        ROOT / "03_fix" / "output" / f"{base}_final.sql",
        ROOT / "04_validate" / "output" / f"validation_{base}.md",
        ROOT / "05_report" / "output" / f"fix_report_{base}.md",
        ROOT / "05_report" / "output" / f"reremediate_{base}.prompt.md",
        ROOT / "06_explain" / "output" / f"semantic_{base}.md",
    ]
    if include_review:
        named.append(REVIEW_DIR / f"review_{base}.md")
    return [p for p in named if p.is_file()]


def main() -> None:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("bases", nargs="*", help="unit base name(s); omit for a full sweep")
    ap.add_argument("--include-review", action="store_true",
                    help="also archive 07_review/output/review_<base>.md")
    ap.add_argument("--dry-run", action="store_true", help="show what would move; move nothing")
    args = ap.parse_args()

    bases = [b.strip() for b in args.bases if b.strip()]
    if bases:
        files: list[Path] = []
        for base in bases:
            files += files_for_base(base, args.include_review)
        scope = ", ".join(bases)
    else:
        files = all_output_files()
        if args.include_review and REVIEW_DIR.exists():
            files += sorted(p for p in REVIEW_DIR.glob("review_*.md") if p.is_file())
        scope = "ALL units"

    # de-dupe while keeping order
    seen: dict[Path, Path] = {}
    for p in files:
        seen[p.resolve()] = p
    files = list(seen.values())

    if not files:
        print(f"Nothing to archive for {scope} — output folders are already clean.")
        return

    # Unique archive folder per run — never reuse or merge into an existing one,
    # so files from different runs can share a name without ever colliding.
    ts = dt.datetime.now().strftime("%Y-%m-%dT%H-%M-%S")
    dest_root = ARCHIVE_ROOT / ts
    suffix = 1
    while dest_root.exists():
        suffix += 1
        dest_root = ARCHIVE_ROOT / f"{ts}_{suffix}"
    ts_label = dest_root.name

    def unique(path: Path) -> Path:
        """Never overwrite an already-archived file — disambiguate on collision."""
        if not path.exists():
            return path
        i = 1
        while True:
            cand = path.with_name(f"{path.stem}__{i}{path.suffix}")
            if not cand.exists():
                return cand
            i += 1

    for src in files:
        rel = src.relative_to(ROOT)
        dest = unique(dest_root / rel)
        print(f"{'DRY  ' if args.dry_run else 'MOVE '}{rel}  ->  _archive/{ts_label}/{dest.relative_to(dest_root)}")
        if not args.dry_run:
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(src), str(dest))

    verb = "(dry-run) would archive" if args.dry_run else "Archived"
    print(f"\n{verb} {len(files)} file(s) for {scope} -> _archive/{ts_label}/")
    if not args.dry_run:
        print("Output folders now reflect only the current 00_input/ files once you re-run.")


if __name__ == "__main__":
    main()
