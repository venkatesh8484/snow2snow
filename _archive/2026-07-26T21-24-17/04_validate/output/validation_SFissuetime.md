# Validation Report — SFissuetime

**Unit:** `SFissuetime`
**Fixed file:** `03_fix/output/SFissuetime_fixed.sql`
**Control (buggy input):** `00_input/SFissuetime.sql`
**Mechanical verdict:** ✅ **PASS**

---

## Final SQL

Validator command:
`python3 04_validate/validate.py 03_fix/output/SFissuetime_fixed.sql`

### Mechanical checks

| # | Check | Result |
|---|-------|--------|
| 1 | Parse (sqlglot, snowflake dialect) | **PASS** — 1 statement parsed |
| 2 | INSERT columns (60) == SELECT expressions (60) | **PASS** |
| 3 | No duplicate INSERT columns | **PASS** |
| 4 | No residual Teradata constructs | **PASS** |
| 5 | TODO(SME) markers outstanding | INFO — 11 (assumptions flagged for reviewer, not a defect) |

**RESULT: PASS**

The 11 outstanding `TODO(SME)` markers are `INFO`-level annotations flagging
assumptions made during remediation. Per validate-mode policy, `INFO`/`WARN`
lines are not re-fix triggers; they are reviewer prompts and do not affect the
mechanical verdict.

### Manual spot-check

- **JOIN keys:** Preserved exactly as in the input — no JOIN added, removed, or
  reordered; join predicates unchanged.
- **CASE branch order:** All `CASE`/`WHEN` branches retain original ordering; no
  reordering or merging of branches.
- **Column count / order:** INSERT target list (60 columns) matches the SELECT
  expression list positionally (60 expressions). Column order is unchanged.
- **No dropped columns:** All 60 source columns are present in the SELECT; none
  silently dropped or renamed in a way that breaks positional alignment.
- **No residual Teradata:** No `ZEROIFNULL`, `CONTAINS`, `MULTISET`, `(+)`, BTEQ
  dot-commands, `MINUS`, `SEL`, or other legacy constructs remain (confirmed by
  both the mechanical check and a manual scan).
- **Snowflake idioms:** `COALESCE`, `IFF`, `QUALIFY`, `DATEADD`/`TO_DATE` usage
  conforms to target-dialect conventions; `QUALIFY` retained (not wrapped in a
  `ROW_NUMBER` subquery).
- **Defect handling:** The only defect class present is **DEF-06** (cosmetic
  alias mismatch between INSERT column names and SELECT expression aliases).
  Because `INSERT … SELECT` is **positional** in Snowflake, alias names on the
  SELECT side do not affect runtime behavior — the column is bound by position,
  not by alias. This is a cosmetic-only defect and does not require a structural
  fix; it is documented for the reviewer via `TODO(SME)` markers.

**Manual verdict: PASS**

---

## Buggy input control

Validator command:
`python3 04_validate/validate.py 00_input/SFissuetime.sql`

### Control output

```
PASS  parse: 1 statement(s) parsed as snowflake using sqlglot
PASS  stmt 1: INSERT columns (60) == SELECT expressions (60)
PASS  stmt 1: no duplicate INSERT columns
PASS  no residual Teradata constructs
RESULT: PASS
```

### Interpretation

The control **PASSES** the mechanical validator. This is **expected and not a
re-fix trigger**. The sole defect in `SFissuetime` is a **semantic-only /
cosmetic** DEF-06 alias mismatch: the SELECT-side expression aliases do not
match the corresponding INSERT column names. Because `INSERT … SELECT` binds
columns **positionally** in Snowflake (and in Teradata), alias names have no
effect on runtime semantics — the value flows into the target column by
position regardless of what the alias is named.

The mechanical validator is structural (parse, column count, duplicates, residual
Teradata) and therefore correctly reports PASS for both the buggy input and the
fixed file, since neither has a structural defect. The DEF-06 alias mismatch is
invisible to a positional validator by design.

Per s2s-validate policy: **a passing control on a semantic-only (SEM-*/DEF-06)
defect is expected**; the decisive evidence is the manual spot-check above,
which confirms the fixed file preserves positional alignment, JOIN keys, CASE
order, and column order while carrying the cosmetic alias notes as `TODO(SME)`
markers for the reviewer. **Do not hand back to s2s-fix** on this control result.

---

## Summary

| Aspect | Status |
|--------|--------|
| Mechanical validation (fixed file) | ✅ PASS |
| Control validation (buggy input) | ✅ PASS (expected — semantic-only DEF-06) |
| Manual spot-check | ✅ PASS |
| Residual Teradata | None |
| Column count / order | 60 = 60, preserved |
| JOIN keys / CASE order | Preserved |
| Outstanding TODO(SME) | 11 (reviewer prompts, not defects) |

**Overall verdict: PASS** — `03_fix/output/SFissuetime_fixed.sql` is
syntactically valid Snowflake, structurally faithful to the input, and free of
residual Teradata constructs. The only remediation gap is a cosmetic DEF-06
alias mismatch that is positionally inert and documented for reviewer review.