# Validation Report — SFIssueSET

- **Fixed file:** `03_fix/output/SFIssueSET_fixed.sql`
- **Control (buggy input):** `00_input/SFIssueSET.sql`
- **Date:** 2026-07-24
- **Validator:** `04_validate/validate.py` (sqlglot parse + Snowflake EXPLAIN backend)
- **Mode:** Stage 4 — mechanical verification (script first, judgment second)

## Reviewer guidance note

The target table `staging.wrk_target` is a **SET table** (confirmed by reviewer
in `07_review/output/review_SFIssueSET.md`). A single `INSERT … SELECT … UNION
… SELECT … UNION … SELECT` into a SET table silently deduplicates across all
branches, dropping rows that legitimately belong to different business
branches. The SEM-05 fix splits the single multi-branch INSERT into 3
independent `INSERT … ( SELECT … EXCEPT SELECT * FROM staging.wrk_target )`
statements so each branch deduplicates only against the existing target rows,
preserving cross-branch distinctness.

## Fixed-file validation output

```
PASS  snowflake connection: probe returned 1
PASS  parse: 3 statement(s) parsed as snowflake using snowflake
PASS  snowflake EXPLAIN stmt 1: compiled OK
PASS  snowflake EXPLAIN stmt 2: compiled OK
PASS  snowflake EXPLAIN stmt 3: compiled OK
PASS  stmt 1: INSERT columns (8) == SELECT expressions (8)
PASS  stmt 1: no duplicate INSERT columns
PASS  stmt 2: INSERT columns (8) == SELECT expressions (8)
PASS  stmt 2: no duplicate INSERT columns
PASS  stmt 3: INSERT columns (8) == SELECT expressions (8)
PASS  stmt 3: no duplicate INSERT columns
PASS  no residual Teradata constructs
INFO  TODO(SME) markers outstanding: 8
------------------------------------------------------------
RESULT: PASS
```

**Mechanical verdict: PASS.** All 3 statements parse as Snowflake, compile via
EXPLAIN, and have matching INSERT-column / SELECT-expression counts (8 = 8) with
no duplicates. No residual Teradata constructs detected.

## Control validation output (buggy input)

```
PASS  snowflake connection: probe returned 1
PASS  parse: 1 statement(s) parsed as snowflake using snowflake
PASS  snowflake EXPLAIN stmt 1: compiled OK
PASS  no residual Teradata constructs
INFO  TODO(SME) markers outstanding: 0
------------------------------------------------------------
RESULT: PASS
```

**Control PASS — expected.** The original file parses and compiles clean on
Snowflake because the bug is purely **semantic** (SEM-05 SET-table dedup: a
single `INSERT … UNION … UNION` into a SET table). The mechanical validator
cannot detect semantic drift — it only checks parse, compile, column counts,
and residual Teradata constructs. A passing control is the expected outcome for
semantic-only defects and is **not** a reason to re-fix. This matches the
2026-07-24 lesson: *"A parse PASS is not correctness."* The decisive evidence
for the bug is the manual spot-check below, not the control result.

## Manual spot-checks

| # | Check | Result | Notes |
|---|-------|--------|-------|
| 1 | 3 separate INSERT statements (not a single INSERT…UNION) | **PASS** | Three distinct `INSERT INTO staging.wrk_target (…)` blocks; no `UNION` / `UNION ALL` operators anywhere in the file. |
| 2 | Each INSERT has an explicit column list (8 columns) | **PASS** | All 3 INSERTs declare the same explicit list: `airline_cd, flgt_no, flgt_dt, company_cd, direction_ind, operating_airline_cd, operating_flgt_no, operating_sfx_cd`. |
| 3 | Each INSERT uses `EXCEPT SELECT * FROM staging.wrk_target` (SET-table dedup) | **PASS** | Every branch ends with `EXCEPT SELECT * FROM staging.wrk_target` inside the parenthesised SELECT, so each branch dedups only against existing target rows. |
| 4 | JOIN keys intact in each branch | **PASS** | Branch 1: `synthetic_mkg_flgt_leg` on `marketing_airline_cd / marketing_flgt_no / gmt_flgt_dt`. Branch 2: `synthetic_operational_flgt_leg` on `operating_airline_cd / operating_flgt_no / gmt_flgt_dt`. Branch 3: `synthetic_codeshare_flgt_leg` on `codeshare_airline_cd / codeshare_flgt_no / gmt_flgt_dt`. All three-key joins preserved exactly. |
| 5 | GROUP BY preserved in each branch | **PASS** | Each branch groups by `src.airline_cd, src.flgt_no, src.flgt_dt` — identical to the original. |
| 6 | No residual Teradata constructs | **PASS** | No `UNION`, `ZEROIFNULL`, `CONTAINS`, `MULTISET`, `(+)`, `MINUS`, `SEL`, or BTEQ dot-commands. Validator confirms. |
| 7 | TODO(SME) markers present | **PASS** | 8 `TODO(SME)` markers present, covering SEM-02/FN-LATEST (×3, one per branch), SEM-06/DTX-10 (×3, one per branch), SEM-05 column-order (×1), SEM-03 width (×1). |

## Overall verdict

**PASS**

- Mechanical validation: PASS (3 statements, all compile, 8 = 8 columns each, no residual Teradata).
- Control: PASS (expected for semantic-only SEM-05 bug — not a re-fix trigger).
- Manual spot-checks: 7 / 7 PASS.
- 8 `TODO(SME)` markers outstanding — these are assumptions flagged for SME
  review (latest-value trick key format, implicit date cast, column-order
  confirmation, SUBSTR width). They do not block the mechanical PASS and are
  carried forward to Stage 5 / Stage 6 for human review.

No hand-back to s2s-fix required.