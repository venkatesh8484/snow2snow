# Validation — `ins_wrk_dc_priority_snowflake_fixed.sql` (2026-07-23)

## Script results (`validate.py`, sqlglot, dialect=snowflake)

### Fixed output — `03_fix/output/ins_wrk_dc_priority_snowflake_fixed.sql`

```
PASS  parse: 1 statement(s) parsed as snowflake
PASS  stmt 1: INSERT columns (131) == SELECT expressions (131)
PASS  stmt 1: no duplicate INSERT columns
PASS  no residual Teradata constructs
INFO  TODO(SME) markers outstanding: 5
------------------------------------------------------------
RESULT: PASS
```

| Check | Result |
|---|---|
| Parses as Snowflake | **PASS** (1 statement) |
| INSERT columns == SELECT expressions | **PASS** (131 == 131) |
| No duplicate INSERT columns | **PASS** |
| No residual Teradata constructs | **PASS** |
| TODO(SME) markers outstanding | 5 (D3 constant, D4 yq_curr_vlu, SFX-01 period cols ×2, D3 inline) |

### Control run — buggy input `00_input/ins_wrk_dc_priority_snowflake.sql`

```
FAIL  parse: Expecting ). Line 218, Col: 12.   (malformed CAST — defect D3)
FAIL  residual Teradata constructs: 4 found
        line 164: ZEROIFNULL (Teradata) -> COALESCE(x,0)  [FNX-01]
        line 165: ZEROIFNULL (Teradata) -> COALESCE(x,0)  [FNX-01]
        line 451: PERIOD CONTAINS (Teradata) -> BETWEEN   [SFX-01]
        line 456: PERIOD CONTAINS (Teradata) -> BETWEEN   [SFX-01]
RESULT: FAIL (2 hard check(s))
```

The control confirms the delivered "converted" file does **not** parse (D3 is a
real parse-blocking bug, not a dialect quirk) and carries four residual Teradata
constructs. Every failure maps to a fix applied in Stage 3.

## Manual spot-checks

- All 10 JOINs preserved with identical keys and filter predicates.
- All CASE branches for `yq_vlu` (9) and `oc_yq_src_cd` (4) preserved in order.
- Final QUALIFY dedup logic unchanged; QUALIFY kept (not rewritten).
- Column order verified against the INSERT list (positions 1–131).
- `ZEROIFNULL` → `COALESCE(x, 0)` preserves NULL-to-zero semantics.
- No residual `CONTAINS`, `ZEROIFNULL`, `(+)`, `MULTISET`, or BTEQ directive.

## Verdict

**PASS** — ready for Stage 5/6. Execution against a live Snowflake account with
the migrated DDL is still required before production sign-off (needs the 5 SME
items resolved).
