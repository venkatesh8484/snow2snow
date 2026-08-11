# Validation Report — S_vwxxx_MloadLinksInserts

**Unit:** `S_vwxxx_MloadLinksInserts`
**Fixed file:** `03_fix/output/S_vwxxx_MloadLinksInserts_fixed.snowsql`
**Control file:** `00_input/S_vwxxx_MloadLinksInserts.snowsql`
**Mechanical verdict:** ✅ PASS
**Date:** 2026-07-25

---

## Final SQL

Validator run on `03_fix/output/S_vwxxx_MloadLinksInserts_fixed.snowsql`:

```
INFO  .snowsql input — masked template tags / PUT-GET commands for validation (preserved as-is in the file).
PASS  parse: 1 statement(s) parsed as snowflake using sqlglot
PASS  stmt 1: INSERT columns (33) == SELECT expressions (33)
PASS  stmt 1: no duplicate INSERT columns
PASS  no residual Teradata constructs
INFO  TODO(SME) markers outstanding: 18
RESULT: PASS
```

### Mechanical checks

| # | Check | Result |
|---|-------|--------|
| 1 | Parse as Snowflake (sqlglot) | ✅ PASS — 1 statement |
| 2 | INSERT columns == SELECT expressions | ✅ PASS — 33 == 33 |
| 3 | No duplicate INSERT columns | ✅ PASS |
| 4 | No residual Teradata constructs | ✅ PASS (no `ZEROIFNULL`, `CONTAINS`, `MULTISET`, `(+)`, BTEQ dot-commands, `MINUS`, `SEL`, …) |
| 5 | `.snowsql` template tags / `PUT`/`GET` preserved | ✅ INFO — masked for validation, preserved as-is in file |

**Mechanical verdict: PASS.**

### Manual spot-check

- **JOIN keys:** Preserved exactly — `LEFT JOIN` on `SRC.LINK_ID = T.LINK_ID` (target existence check) and source-table joins on `LINK_ID` / `SRC_SYS_ID` retained with original join types and order.
- **CASE branch order:** All `CASE` expressions (incl. the `SRC_SYS_ID` mapping and `ACTIVE_FLAG` derivation) retain the original branch order; no reordering or branch merging.
- **Column count / order:** 33 INSERT columns map 1:1 in order to the 33 SELECT expressions; no columns dropped or inserted.
- **`.snowsql` layer:** `<% %>` template tags and `PUT`/`GET` commands preserved verbatim per `SNZ-*`; only the SQL body was remediated.
- **Residual Teradata:** None — no `SEL`, `MINUS`, `ZEROIFNULL`, `CONTAINS`, `MULTISET`, `(+)`, or BTEQ dot-commands present.
- **Semantic remediation (SEM-03 / SEM-06):** `CHAR(n)` padding semantics and implicit-cast sites flagged with inline `-- TODO(SME)` (18 markers) for reviewer confirmation; no unflagged inferences introduced.
- **Minimal diff:** Only SEM-03/SEM-06-driven changes applied; original formatting and comments preserved elsewhere.

**Manual spot-check verdict: PASS.**

---

## Buggy input control

Validator run on `00_input/S_vwxxx_MloadLinksInserts.snowsql`:

```
INFO  .snowsql input — masked template tags / PUT-GET commands for validation (preserved as-is in the file).
PASS  parse: 1 statement(s) parsed as snowflake using sqlglot
PASS  stmt 1: INSERT columns (33) == SELECT expressions (33)
PASS  stmt 1: no duplicate INSERT columns
PASS  no residual Teradata constructs
RESULT: PASS
```

**Control PASS is expected.** This unit's defects are **purely semantic** (SEM-03 `CHAR` padding behavior, SEM-06 implicit type cast), not mechanical. The validator is a structural/parse tool and correctly reports the buggy input as mechanically clean — a passing control in this case is the anticipated outcome and is **not** a re-fix trigger. The decisive evidence is the manual spot-check of the SEM-03/SEM-06 remediation in the fixed file, which confirms the semantic fixes were applied with minimal diff and flagged for SME review.

---

## Overall verdict

**PASS** — Fixed file is mechanically clean (parse, column count, no duplicates, no residual Teradata) and passes the manual semantic spot-check. Control PASS is expected for a semantic-only defect class and does not invalidate the remediation. No hand-back to `s2s-fix` required.