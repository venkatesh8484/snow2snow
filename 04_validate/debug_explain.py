#!/usr/bin/env python3
"""Debug helper: run EXPLAIN on a fixed SQL file and print the full error."""
import sys
import snowflake.connector
from pathlib import Path
import tomllib

cfg = tomllib.loads((Path.home() / '.snowflake' / 'connections.toml').read_text())
profile = next(iter(cfg.values()))
conn = snowflake.connector.connect(
    account=profile['account'], user=profile['user'], password=profile['password'],
    role=profile.get('role') or None, warehouse='COMPUTE_WH',
    database=profile.get('database') or None, schema=profile.get('schema') or None,
    authenticator=profile.get('authenticator') or None,
)
cur = conn.cursor()

sql_file = sys.argv[1] if len(sys.argv) > 1 else '03_fix/output/ins_wrk_dc_priority_snowflake_fixed.sql'
sql = Path(sql_file).read_text()

# strip comment-only lines
lines = [ln for ln in sql.splitlines() if not ln.strip().startswith('--')]
stmt = "\n".join(lines).strip().rstrip(';')

try:
    cur.execute(f"EXPLAIN\n{stmt}")
    cur.fetchall()
    print("EXPLAIN OK")
except Exception as e:
    print(f"FULL ERROR:\n{e}")

conn.close()