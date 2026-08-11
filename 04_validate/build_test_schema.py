#!/usr/bin/env python3
"""Build a DDL + sample-data script for Snowflake validation.

Parses every *_fixed.sql file in 03_fix/output/, extracts:
  - INSERT target table + column list (with order)
  - All source tables referenced in FROM/JOIN clauses
  - All columns referenced via alias.column on those source tables

Emits a single SQL script that:
  1. Creates the schema + all tables (broad VARCHAR/NUMBER/DATE types)
  2. Inserts one sample row per source table
  3. Creates the target tables (empty)

Run:  python3 04_validate/build_test_schema.py
Then: snowflake -f 04_validate/output/test_schema.sql
"""
from __future__ import annotations

import re
from pathlib import Path
from collections import OrderedDict

ROOT = Path(__file__).resolve().parent.parent
FIXED_DIR = ROOT / "03_fix" / "output"
OUT_FILE = ROOT / "04_validate" / "output" / "test_schema.sql"

# ── helpers ────────────────────────────────────────────────────────────────

def strip_comments(sql: str) -> str:
    """Remove -- line comments and /* */ block comments before parsing."""
    sql = re.sub(r"--[^\n]*", "", sql)
    sql = re.sub(r"/\*.*?\*/", "", sql, flags=re.DOTALL)
    return sql


def parse_insert_target(sql: str) -> tuple[str | None, list[str]]:
    """Return (target_table, [col, ...]) from the first INSERT statement."""
    m = re.search(r"INSERT\s+INTO\s+([\w.]+)\s*\(([^;]*?)\)\s*SELECT",
                  sql, re.IGNORECASE | re.DOTALL)
    if not m:
        return None, []
    table = m.group(1).lower().replace("staging.", "")
    cols_block = m.group(2)
    # strip comments
    cols_block = re.sub(r"--[^\n]*", "", cols_block)
    cols = [c.strip().split()[-1].lower() for c in cols_block.split(",") if c.strip()]
    return table, cols


def parse_source_tables(sql: str) -> dict[str, set[str]]:
    """Return {table_alias: set(column)} for every alias.col reference."""
    tables: dict[str, set[str]] = {}
    # FROM/JOIN <table> [AS] <alias>
    for m in re.finditer(
        r"(?:FROM|JOIN)\s+([\w.]+)\s+(?:AS\s+)?(\w+)",
        sql, re.IGNORECASE,
    ):
        tbl = m.group(1).lower().replace("staging.", "")
        alias = m.group(2).lower()
        if alias not in ("on", "where", "group", "order", "qualify", "select", "by", "and", "or", "not", "is", "null", "in", "as", "from", "join", "left", "right", "full", "inner", "outer", "case", "when", "then", "else", "end", "over", "partition", "distinct", "all", "union", "except", "intersect", "with", "into", "values", "set", "create", "table", "view", "schema", "database", "use", "drop", "insert", "update", "delete", "select", "logic"):
            tables.setdefault(alias, set())
            tables[alias]  # touch
            tables[alias].add("__table__:" + tbl)
    # alias.column references
    for m in re.finditer(r"(\w+)\.(\w+)", sql):
        alias = m.group(1).lower()
        col = m.group(2).lower()
        if alias in tables:
            tables[alias].add(col)
    return tables


def infer_type(col: str) -> str:
    """Broad type inference from column-name suffix."""
    c = col.lower()
    if c.endswith("_dt") or c.endswith("_date") or c.endswith("_dte"):
        return "DATE"
    if c.endswith("_tm") or c.endswith("_time") or c.endswith("_timestamp"):
        return "TIMESTAMP_LTZ"
    if c.endswith("_ts"):
        return "TIMESTAMP_LTZ"
    if c.endswith("_no") or c.endswith("_qty") or c.endswith("_id") or c.endswith("_seq"):
        return "NUMBER(18,4)"
    if c.endswith("_vlu") or c.endswith("_rte") or c.endswith("_factor"):
        return "NUMBER(18,6)"
    if c.endswith("_ind") or c.endswith("_cd") or c.endswith("_typ") or c.endswith("_txt"):
        return "VARCHAR(100)"
    if c.endswith("_yr") or c.endswith("_year") or c.endswith("_month") or c.endswith("_week"):
        return "NUMBER(6,0)"
    return "VARCHAR(200)"


def sample_value(col: str, col_type: str) -> str:
    c = col.lower()
    if col_type.startswith("DATE"):
        return "'2026-01-15'::DATE"
    if col_type.startswith("TIMESTAMP"):
        return "'2026-01-15 10:30:00'::TIMESTAMP_LTZ"
    if col_type.startswith("TIME"):
        return "'10:30:00'::TIME"
    if col_type.startswith("NUMBER"):
        if c.endswith("_no") or c.endswith("_id") or c.endswith("_seq"):
            return "1"
        if c.endswith("_qty"):
            return "100"
        if c.endswith("_vlu") or c.endswith("_rte"):
            return "1.50"
        return "1"
    # varchar
    if c.endswith("_cd"):
        return "'XX'"
    if c.endswith("_ind"):
        return "'N'"
    if c.endswith("_txt"):
        return "'sample'"
    return "'sample'"


# ── main ──────────────────────────────────────────────────────────────────

def main():
    all_tables: OrderedDict[str, OrderedDict[str, str]] = OrderedDict()
    target_tables: dict[str, list[str]] = {}

    for sql_file in sorted(FIXED_DIR.glob("*_fixed.sql")):
        sql = strip_comments(sql_file.read_text())
        tgt, cols = parse_insert_target(sql)
        if tgt:
            target_tables.setdefault(tgt, [])
            for c in cols:
                if c not in target_tables[tgt]:
                    target_tables[tgt].append(c)

        sources = parse_source_tables(sql)
        for alias, cols in sources.items():
            tbl = None
            real_cols = set()
            for c in cols:
                if c.startswith("__table__:"):
                    tbl = c.split(":", 1)[1]
                else:
                    real_cols.add(c)
            if tbl and tbl not in target_tables:
                t = all_tables.setdefault(tbl, OrderedDict())
                for c in sorted(real_cols):
                    if c not in t:
                        t[c] = infer_type(c)

    # Build SQL
    lines: list[str] = []
    lines.append("-- Auto-generated DDL + sample data for Snowflake validation")
    lines.append("-- Generated by 04_validate/build_test_schema.py")
    lines.append("-- DO NOT EDIT — regenerate after changing fixed SQL")
    lines.append("")
    lines.append("CREATE SCHEMA IF NOT EXISTS tcs_poc;")
    lines.append("USE SCHEMA tcs_poc;")
    lines.append("USE WAREHOUSE COMPUTE_WH;")
    lines.append("")

    # Source tables (with sample data)
    lines.append("-- ============================================================")
    lines.append("-- SOURCE TABLES (with 1 sample row each)")
    lines.append("-- ============================================================")
    for tbl, cols in all_tables.items():
        lines.append(f"CREATE OR REPLACE TABLE {tbl} (")
        col_lines = [f"    {c} {t}" for c, t in cols.items()]
        lines.append(",\n".join(col_lines))
        lines.append(");")
        lines.append("")
        if cols:
            lines.append(f"INSERT INTO {tbl} ({', '.join(cols.keys())}) VALUES")
            vals = [sample_value(c, t) for c, t in cols.items()]
            lines.append(f"    ({', '.join(vals)});")
            lines.append("")

    # Target tables (empty)
    lines.append("-- ============================================================")
    lines.append("-- TARGET TABLES (empty — populated by the fixed SQL)")
    lines.append("-- ============================================================")
    for tbl, cols in target_tables.items():
        if not cols:
            lines.append(f"CREATE OR REPLACE TABLE {tbl} (placeholder VARCHAR);")
        else:
            lines.append(f"CREATE OR REPLACE TABLE {tbl} (")
            col_lines = [f"    {c} {infer_type(c)}" for c in cols]
            lines.append(",\n".join(col_lines))
            lines.append(");")
        lines.append("")

    OUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    OUT_FILE.write_text("\n".join(lines))
    print(f"Wrote {OUT_FILE}")
    print(f"  Source tables: {len(all_tables)}")
    print(f"  Target tables: {len(target_tables)}")


if __name__ == "__main__":
    main()