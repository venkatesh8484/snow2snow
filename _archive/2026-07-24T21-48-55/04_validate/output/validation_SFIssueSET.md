# Validation Report — SFIssueSET

- **Unit:** SFIssueSET
- **Date:** 2026-07-24
- **Validator:** `04_validate/validate.py` (sqlglot parse + Snowflake EXPLAIN backend)
- **Fixed file:** `03_fix/output/SFIssueSET_fixed.sql`
- **Control (buggy input):** `00_input/SFIssueSET.sql`

---

## 1. Fixed-file validation

```
PASS  snowflake connection: probe returned 1
PASS  parse: 1 statement(s) parsed as snowflake using snowflake
PASS  snowflake EXPLAIN stmt 1: compiled OK
PASS  no residual Teradata constructs
INFO  TODO(SME) markers outstanding: 10
------------------------------------------------------------
RESULT: PASS
```

**Verdict: PASS.** The fixed file parses, compiles against a live Snowflake
backend (EXPLAIN OK), and contains no residual Teradata constructs. The 10
`TODO(SME)` markers are informational — they flag semantic-risk locations for
human review, not mechanical defects.

---

## 2. Control validation (buggy input)

```
PASS  snowflake connection: probe returned 1
PASS  parse: 1 statement(s) parsed as snowflake using snowflake
PASS  snowflake EXPLAIN stmt 1: compiled OK
PASS  no residual Teradata constructs
INFO  TODO(SME) markers outstanding: 0
------------------------------------------------------------
RESULT: PASS
```

**Control PASS — EXPECTED for this unit.** The defects in `SFIssueSET.sql` are
purely semantic:

- **SEM-05** — SET-table dedup semantics (Snowflake treats all tables as
  MULTISET; the buggy file relies on implicit dedup that no longer occurs).
- **SEM-02** — latest-value trick (Teradata `MAX(...) OVER` / correlated
  subquery pattern that drifts under Snowflake semantics).
- **SEM-06** — implicit character→numeric cast (Teradata coerces silently;
  Snowflake is stricter).

A file with only semantic drift will parse and compile cleanly on Snowflake —
the mechanical validator (sqlglot parse + EXPLAIN) cannot detect semantic
incorrectness. A passing control is therefore the **expected** outcome for a
semantic-only unit and is **not** a reason to re-fix. This matches the
2026-07-24 lesson recorded in `02_rules/06_lessons_learned.md`:
*"A parse PASS is not correctness."*

The decisive evidence for this unit is the **manual spot-check** below, not the
control's mechanical result.

---

## 3. Manual spot-checks

| # | Check | Result | Notes |
|---|-------|--------|-------|
| 1 | JOIN keys intact (3 branches: marketing, operational, codeshare — each joins on `airline_cd` / `flgt_no` / `flgt_dt`) | **PASS** | All three UNION branches retain the same join key set; no key dropped or reordered. |
| 2 | CASE / GROUP BY branches in original order | **PASS** | CASE-branch order and GROUP BY column order preserved exactly per the minimal-diff policy. |
| 3 | No dropped columns (8 SELECT expressions per branch, UNION-consistent) | **PASS** | Each of the 3 UNION branches selects the same 8 expressions in the same order; column count and position are UNION-consistent. |
| 4 | No residual Teradata function/operator (`ZEROIFNULL`, `CONTAINS`, `SEL`, `MINUS`, `MULTISET`, `(+)`, BTEQ dot-commands) | **PASS** | None present. Validator's residual-construct scan confirms; manual scan agrees. |
| 5 | `TODO(SME)` markers present at semantic-risk locations | **PASS** | 10 markers placed at SEM-05 dedup, SEM-02 latest-value, and SEM-06 implicit-cast sites. |

---

## 4. Overall verdict

**PASS**

The fixed file `03_fix/output/SFIssueSET_fixed.sql` is mechanically valid
(parses + compiles on Snowflake, no residual Teradata) and passes all five
manual spot-checks. The control's PASS is expected for a semantic-only unit
and does not indicate a need to re-fix.

### Outstanding items for SME review

- **10 `TODO(SME)` markers** are outstanding. All are semantic in nature
  (SEM-05 SET-dedup, SEM-02 latest-value trick, SEM-06 implicit cast) and
  await human confirmation of the inferred intent. None is a mechanical
  defect blocking this stage.