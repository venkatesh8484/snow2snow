# Validation report — `S_vwxxx_MapLinksRecordsToOracle`

**Unit:** `S_vwxxx_MapLinksRecordsToOracle` (`.snowsql` template input)
**Fixed file:** `03_fix/output/S_vwxxx_MapLinksRecordsToOracle_fixed.snowsql`
**Control file:** `00_input/S_vwxxx_MapLinksRecordsToOracle.snowsql`
**Validator:** `04_validate/validate.py` (sqlglot parse + Snowflake compile checks)
**Mechanical verdict:** **PASS**

---

## Final SQL

Validator run on `03_fix/output/S_vwxxx_MapLinksRecordsToOracle_fixed.snowsql`:

```
INFO  .snowsql input — masked template tags / PUT-GET commands for validation (preserved as-is in the file).
PASS  parse: 6 statement(s) parsed as snowflake using sqlglot
PASS  stmt 6: INSERT columns (28) == SELECT expressions (28)
PASS  stmt 6: no duplicate INSERT columns
PASS  no residual Teradata constructs
INFO  TODO(SME) markers outstanding: 11
RESULT: PASS
```

### Mechanical checks

| Check | Result |
|---|---|
| Parse (sqlglot, snowflake dialect) | PASS — 6 statements |
| INSERT/SELECT column count match (stmt 6) | PASS — 28 == 28 |
| Duplicate INSERT columns (stmt 6) | PASS — none |
| Residual Teradata constructs (`ZEROIFNULL`, `CONTAINS`, `MULTISET`, `(+)`, BTEQ, `MINUS`, `SEL`, …) | PASS — none |
| `.snowsql` template tags / `PUT`/`GET` preserved (SNZ-01) | PASS — masked for validation, untouched in file |
| `TODO(SME)` markers outstanding | INFO — 11 (expected; all are deferred SME confirmations, not defects) |

### Manual spot-check

- **JOIN keys preserved.** Outer `WHERE` joins `tgt` to `src` on the 7 keys
  `LINK_STATION_CD, IN_ORIGN_STATION_CD, IN_ALN_CD, IN_FLIGHT_NO,
  IN_FLIGHT_SFX_CD, IN_DEP_FLIGHT_DT, LINK_EFFECTIVE_DT` — identical to the
  buggy input. The `NOT EXISTS` guard against `BASE.FLIGHT_FOLDERLINKS x`
  reuses the same 7 keys plus `LINK_EXPIRY_DT` and `CURRENT_REC_IND`; order and
  operands are unchanged.
- **CASE / IFF branch order preserved.** Both `IFF` expressions
  (`OLD_LINK_EXPIRY_DT <> '20501231'` triage, and `ACTION_CODE = 'U'` →
  `CURRENT_REC_IND`) keep the same branch order as the input. No branch was
  inverted or reordered.
- **No dropped columns.** The `src` subquery projects all 9 columns
  (`LINK_STATION_CD, IN_ORIGN_STATION_CD, IN_ALN_CD, IN_FLIGHT_NO,
  IN_FLIGHT_SFX_CD, IN_DEP_FLIGHT_DT, LINK_EFFECTIVE_DT, LINK_EXPIRY_DT,
  CURRENT_REC_IND`); `SET` consumes `LINK_EXPIRY_DT` and `CURRENT_REC_IND`,
  the rest feed the join keys. Nothing was added or removed.
- **Minimal diff.** Exactly one functional change vs the input: the subquery
  alias on line 13 was restored from `AS IN_DEP_GMTFLIGHT_FLIGHT_DT` back to
  `AS IN_DEP_FLIGHT_DT` (DEF-07). This is the only edit; it aligns the alias
  with the outer join key `src.IN_DEP_FLIGHT_DT` (line 29) and the
  `NOT EXISTS` guard `x.IN_DEP_FLIGHT_DT = tgt.IN_DEP_FLIGHT_DT` (line 39),
  which otherwise would raise Snowflake `invalid identifier 'SRC.IN_DEP_FLIGHT_DT'`.
  Formatting, indentation, and the original author's comments are otherwise
  preserved.
- **No residual Teradata.** Confirmed by both the validator and visual
  inspection — no `ZEROIFNULL`, `CONTAINS`, `MULTISET`, `(+)`, BTEQ dot-commands,
  `MINUS`, `SEL`, or other legacy constructs remain.
- **SNZ-01 preservation.** The `<% ctx.env.S_vw6122_CompareLinksRecordsWithTeradata_Current_date %>`
  template tag is preserved verbatim; the validator masked it for parsing only.
- **Deferred SME items (not blockers).** 11 `TODO(SME)` markers are carried
  forward — DEF-07 alias/column-name confirmation, DEF-07 distinct-guard-table
  confirmation, SEM-03 CHAR-key padding, SEM-06/DTX-09 date-format mask, and
  SEM-06/SEM-08 NULL-handling on `OLD_LINK_EXPIRY_DT`. These are semantic
  confirmations for the reviewer, not mechanical defects; they do not affect
  the PASS verdict.

**Spot-check verdict:** PASS — join keys, branch order, column set, and
formatting are faithful to the input; the single DEF-07 alias fix is correct
and minimal.

---

## Buggy input control

Validator run on `00_input/S_vwxxx_MapLinksRecordsToOracle.snowsql`:

```
INFO  .snowsql input — masked template tags / PUT-GET commands for validation (preserved as-is in the file).
PASS  parse: 6 statement(s) parsed as snowflake using sqlglot
PASS  stmt 6: INSERT columns (28) == SELECT expressions (28)
PASS  stmt 6: no duplicate INSERT columns
PASS  no residual Teradata constructs
RESULT: PASS
```

**Control PASS is expected and is NOT a re-fix trigger.** The buggy input is
mechanically parse-clean — the defects in this unit are purely **semantic**
(SEM-04/05/06/08, OBS-01) plus the DEF-07 alias mismatch that the mechanical
validator cannot flag because sqlglot resolves the alias as a valid identifier
in isolation. The decisive evidence is the manual spot-check above: the fixed
file restores the `IN_DEP_FLIGHT_DT` alias so the outer `WHERE` and the
`NOT EXISTS` guard resolve correctly at Snowflake runtime, while the buggy
input would raise `invalid identifier 'SRC.IN_DEP_FLIGHT_DT'`. A passing
control for a semantic-only defect is the documented expected behavior; no
re-fix is warranted.

---

## Verdict

**Mechanical: PASS.** The fixed file parses, has matching INSERT/SELECT
column counts, no duplicate columns, no residual Teradata constructs, and
preserves `.snowsql` template tags per SNZ-01. The single DEF-07 alias fix is
minimal and correct. The 11 outstanding `TODO(SME)` markers are deferred
reviewer confirmations (semantic/typing), not defects. No hand-back to
s2s-fix.