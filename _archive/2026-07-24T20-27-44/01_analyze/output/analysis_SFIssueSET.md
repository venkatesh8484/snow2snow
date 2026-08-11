# Stage 1 Analysis — `SFIssueSET.sql`

**Input:** `00_input/SFIssueSET.sql` (90 lines)
**Teradata ground truth:** None. No `00_input/SFIssueSET.teradata.sql` is
present. Per the Stage-1 contract, semantic intent is inferred from `02_rules/`
and the Snowflake input alone; every inference is flagged `TODO(SME)`. The
pipeline is **never** to reach outside the workspace for a Teradata original.
**File name:** `SFIssueSET` (not `SFFixedSET`).

## 0. Statement shape

The file is a single `INSERT … SELECT … UNION SELECT … UNION SELECT … ;`
statement:

- Line 1: `INSERT INTO staging.wrk_target` — **no explicit target column list.**
- Lines 2–29: Branch 1 — `synthetic_flgt_source` ⋈ `synthetic_mkg_flgt_leg`,
  `GROUP BY` airline/flgt/dt.
- Line 30: `UNION` (set operator, **not** `UNION ALL`).
- Lines 32–59: Branch 2 — `synthetic_flgt_source` ⋈
  `synthetic_operational_flgt_leg`, same `GROUP BY`.
- Line 60: `UNION`.
- Lines 62–90: Branch 3 — `synthetic_flgt_source` ⋈
  `synthetic_codeshare_flgt_leg`, same `GROUP BY`.
- Line 90: terminating `;`.

There is **one** statement (one `INSERT`, three `SELECT` branches, two `UNION`).
There is **no** `CREATE TABLE` DDL for `staging.wrk_target` in this file.

## 1. Column-count check

There is **no explicit INSERT target column list** (line 1 is bare
`INSERT INTO staging.wrk_target`). The target column set is therefore unknown
from this script alone — it is defined by the target table's DDL, which is not
supplied. The check is performed on the **SELECT expression lists** of the three
branches to confirm they are mutually consistent (a prerequisite for `UNION`).

Each branch selects the same 7 expressions in the same order:

| # | Expression (all three branches) | Alias on branches 1 & 2 | Alias on branch 3 |
|---|---|---|---|
| 1 | `src.airline_cd` | — | — |
| 2 | `src.flgt_no` | — | — |
| 3 | `src.flgt_dt` | — | — |
| 4 | `SUBSTR(MAX(src.effective_dt || <t>.company_cd), 11, 99)` | `company_cd` | `company_cd` |
| 5 | `SUBSTR(MAX(src.effective_dt || <t>.direction_ind), 11, 99)` | `direction_ind` | `direction_ind` |
| 6 | `SUBSTR(MAX(src.effective_dt || <t>.operating_airline_cd), 11, 3)` | `operating_airline_cd` | `operating_airline_cd` |
| 7 | `SUBSTR(MAX(src.effective_dt || <t>.operating_flgt_no), 11, 99)` | `operating_flgt_no` | `operating_flgt_no` |
| 8 | `SUBSTR(MAX(src.effective_dt || <t>.operating_sfx_cd), 11, 99)` | `operating_sfx_cd` | `operating_sfx_cd` |

Wait — recount. Each branch has **8** SELECT expressions (3 bare keys + 5
`SUBSTR(MAX(...))` aggregates). All three branches are positionally identical
(8 expressions, same order, same types). `UNION` therefore type-checks.

| Branch | SELECT expression count | Duplicate expressions? |
|---|---|---|
| 1 (lines 2–13) | 8 | None |
| 2 (lines 32–43) | 8 | None |
| 3 (lines 62–73) | 8 | None |

**Net:** 8 expressions per branch, branches aligned. **No DEF-05 mismatch
between branches.** The INSERT-vs-SELECT count cannot be verified because the
target column list is absent — see the open SME question in §4.

## 2. Syntax errors / residual-Teradata constructs

Scanned for every construct in `02_rules/01_syntax_fixes.md` (`SFX-*`) and
`02_rules/03_function_fixes.md` (`FNX-*`), plus `02_rules/02_datatype_rules.md`
(`DTX-*`).

| Line(s) | Construct | Why invalid / rule | Class |
|---|---|---|---|
| — | `ZEROIFNULL`, `NULLIFZERO` | Not present. | — |
| — | `CONTAINS` / `OVERLAPS` (PERIOD ops) | Not present. | — |
| — | `SEL`, `MINUS`, `TOP`, `(+)` joins, `PRIMARY INDEX`, `COLLECT STATS`, BTEQ dot-commands, `LOCKING ROW` | Not present. | — |
| — | `CAST(... FORMAT ...)`, `**`, `MOD`, `INDEX()`, `OREPLACE`, `OTRANSLATE`, `STRTOK`, `LIKE ANY`, `TITLE`/`FORMAT` phrases | Not present. | — |
| — | `BYTEINT`, `CHARACTER SET`, `PERIOD(...)`, `BYTE/VARBYTE`, `CLOB/BLOB`, `INTERVAL`, `DATE FORMAT` in DDL | Not present (no DDL in file). | — |

**Result: no `SFX-*`, `FNX-*`, or `DTX-*` syntax errors.** The file parses
cleanly on Snowflake. This matches the `06_lessons_learned.md` entry for this
file: *"A `parse PASS` is not correctness."* The bug is purely semantic (§4), not
syntactic.

The only function-family construct present is the **latest-value trick**
`SUBSTR(MAX(src.effective_dt || <col>), 11, …)`, discussed under semantic risks
below (it parses, but its correctness depends on key width — `FN-LATEST`).

## 3. Defects (`DEF-*`)

| Line(s) | Defect | Rule | Class |
|---|---|---|---|
| 1 | `INSERT INTO staging.wrk_target` has **no target column list**. Not a DEF by itself (Snowflake allows positional insert), but it makes the INSERT-vs-SELECT count unverifiable from this script and hides any positional drift. | DEF-05 (related) | SME |
| 4–9, 34–39, 64–69 | `SUBSTR(MAX(src.effective_dt || <col>), 11, 99)` — the `||` concatenation relies on `effective_dt` being a **fixed-width** string of width 10 so that `SUBSTR(..., 11, …)` lands on the value. If `effective_dt` is a `DATE`/`TIMESTAMP`, Snowflake will implicitly cast it to a string whose width depends on the type and session settings, so the `11` offset and the `MAX` ordering can both drift. This is a latent malformed-expression risk, not a parse error. | DEF-04 / FN-LATEST | SME |
| 6, 36, 66 | `SUBSTR(..., 11, 3)` for `operating_airline_cd` vs `11, 99` for the other four aggregates — the `3` is intentional (airline codes are 2–3 chars) but is the only place the width is bounded. Not a defect per se; flagged for the semantic pass. | — | — |

**No DEF-01 (duplicate columns), DEF-02 (keyword typos), DEF-03 (unbalanced
parens), DEF-04 (malformed function call in the strict sense), or DEF-05
(branch-vs-branch count mismatch).** Parentheses are balanced in every branch;
the `SUBSTR(MAX(... || ...), 11, n)` calls are well-formed syntactically.

## 4. Semantic risks (`SEM-*`)

| Line(s) | Risk | Rule | Present? | Class |
|---|---|---|---|---|
| 1, 30, 60 | **SET-table dedup / `UNION` collapse.** Three independent `SELECT` branches are merged with `UNION` into one `INSERT` on `staging.wrk_target`. Per `06_lessons_learned.md` (2026-07-24 entry) the original Teradata had **three separate `INSERT`s into a SET table**; the converter collapsed them into one `INSERT … UNION`. Two distinct semantic hazards: (a) `UNION` (not `UNION ALL`) de-duplicates **across branches**, so a row produced by both the marketing-leg and operational-leg branches is silently dropped — this is **not** what three independent SET-table INSERTs do (each INSERT dedups only against rows already in the target, not against the other INSERTs' output). (b) Even if the target were MULTISET, `UNION` still wrongly drops cross-branch duplicates. The target's SET/MULTISET attribute lives in `staging.wrk_target`'s `CREATE TABLE` DDL, which is **not supplied**. Per SEM-05 and the mode instructions, **do not assume** — raise an SME question. | SEM-05 | **Yes — primary finding** | **SME** |
| 4–9, 34–39, 64–69 | **Latest-value trick (`FN-LATEST`).** `SUBSTR(MAX(src.effective_dt || <col>), 11, …)` computes "value of `<col>` on the latest `effective_dt`" by concatenating a date key with the value and taking `MAX`. This is correct **only if** the concatenated key is fixed-width and lexicographically ordered. `effective_dt || <col>` is safe only when `effective_dt` is formatted as a fixed-width string (e.g. `TO_CHAR(effective_dt,'YYYY-MM-DD')`, width 10) **and** `<col>` is left-padded to a fixed width (e.g. `LPAD(<col>::VARCHAR, n, ' ')`). As written, if `effective_dt` is a `DATE`, Snowflake's implicit cast yields `'YYYY-MM-DD'` (width 10) so the `11` offset is correct *today*, but the `MAX` tie-break between two rows with the same `effective_dt` but different `<col>` values is **non-deterministic and width-dependent** — a longer `operating_flgt_no` can sort after a shorter one only if the shorter is blank-padded. The lesson (`FN-LATEST`) requires formatting the key explicitly before `MAX`. | SEM-02 (tie-break) + FN-LATEST | **Yes** | **SME** |
| 4–9, 34–39, 64–69 | **Implicit string cast in `||`.** `src.effective_dt || <col>` implicitly casts `effective_dt` (likely `DATE`/`TIMESTAMP`) and the `<col>` values to string. Snowflake is stricter than Teradata here (DTX-10 / SEM-06): if any `<col>` is numeric, the `||` may error or produce a different string than Teradata's cast. | SEM-06 / DTX-10 | **Yes** | SME |
| 15, 45, 75 | **Join-key direction (SEM-10).** Branch 1 joins `src.airline_cd = leg.marketing_airline_cd`; branch 2 joins `src.airline_cd = leg.operating_airline_cd`; branch 3 joins `src.airline_cd = cs.codeshare_airline_cd`. The alias names are self-consistent with the table names (`synthetic_mkg_flgt_leg`, `synthetic_operational_flgt_leg`, `synthetic_codeshare_flgt_leg`), so direction looks correct — but with no Teradata ground truth this cannot be proven, only flagged. | SEM-10 | Possible | SME |
| 17–24, 47–54, 77–84 | **Subquery `param_value` type.** `src.flgt_dt > (SELECT param_value FROM synthetic_sys_param WHERE param_id = 'UPDATE_CUTOFF')`. If `param_value` is `VARCHAR` and `src.flgt_dt` is `DATE`, Snowflake will attempt an implicit cast that may fail or mis-compare (SEM-06 / DTX-10). Teradata was lenient. | SEM-06 / DTX-10 | Possible | SME |
| — | Integer division (SEM-01) | Not present — no `/` arithmetic. | — | — |
| — | `CHAR(n)` padding (SEM-03) | Cannot assess — no DDL supplied. Flag if target/source DDL uses `CHAR(n)` join keys. | SEM-03 | Unknown | SME |
| — | Timestamp/TZ (SEM-04) | `gmt_flgt_dt` / `effective_dt` may be `TIMESTAMP`; without DDL the NTZ/TZ choice is unknown. | SEM-04 | Unknown | SME |
| — | `NULL` ordering (SEM-07) | No `ORDER BY` feeds a `QUALIFY`/`TOP`; the `MAX()` aggregate over the concatenated key ignores NULLs by SQL standard. Not a risk here. | SEM-07 | No | — |
| — | Empty string vs NULL (SEM-08) | No `NULLIF(x,'')` or `''` literals. | SEM-08 | No | — |
| — | Aggregate of empty set (SEM-09) | `MAX` over an empty group returns NULL; `SUBSTR(NULL, 11, n)` returns NULL. Acceptable (becomes NULL row), but worth noting if the target rejects NULLs. | SEM-09 | Possible | SME |

### Open SME questions (must be answered before Stage 3 can finalize)

1. **Is `staging.wrk_target` a SET table?** (SEM-05) Its `CREATE TABLE` DDL is
   not in this file. If SET, the three branches must be ported as **three
   separate** `INSERT INTO staging.wrk_target ( SELECT … EXCEPT SELECT * FROM
   staging.wrk_target )` statements — **never** a single cross-branch `UNION`.
   If MULTISET, the operator should still be `UNION ALL` (not `UNION`) unless
   cross-branch dedup is explicitly intended. **This is the single most important
   finding.**
2. **What was the Teradata source's set operator / INSERT structure?** No
   `.teradata.sql` is supplied. The `06_lessons_learned.md` entry states the
   Teradata had three independent INSERTs into a SET table; that lesson is the
   only evidence. Confirm with the source team. If confirmed, the `UNION`
   on lines 30 and 60 is a **semantic bug** to be split back into three
   statements (SEM-05).
3. **Is `effective_dt` a `DATE`, `TIMESTAMP`, or already a formatted `VARCHAR`?**
   (FN-LATEST / SEM-06) Determines whether `SUBSTR(MAX(effective_dt || col), 11, …)`
   lands on the value correctly and whether the `MAX` tie-break is deterministic.
   If `DATE`, wrap as `TO_CHAR(src.effective_dt,'YYYY-MM-DD') || LPAD(<col>::VARCHAR, n, ' ')`
   before `MAX` (per `FN-LATEST`).
4. **What is the fixed width `n` for each `<col>` in the `LPAD`?** Needed only
   if Q3 says the key must be re-formatted. `operating_airline_cd` is bounded to
   `3` by `SUBSTR(...,11,3)`; the other four use `99` (effectively unbounded),
   which means the `MAX` tie-break among them is **not** fixed-width today.
5. **What is `param_value`'s type in `synthetic_sys_param`?** (SEM-06) If
   `VARCHAR`, the `src.flgt_dt > (SELECT param_value …)` comparison needs an
   explicit `TO_DATE(param_value, '…')` cast.
6. **What is the target column list of `staging.wrk_target`?** (DEF-05) The
   `INSERT` has no column list; add one to make the positional insert
   verifiable and robust to future DDL changes.
7. **Are the join-key directions in branches 1–3 correct vs the Teradata
   source?** (SEM-10) They look right by naming, but without ground truth this
   is an assumption.

## 5. Classification summary

| Class | Count | Findings |
|---|---|---|
| **AUTO** | 0 | No mechanical `SFX/FNX/DTX` rule applies — the file already parses. |
| **FIX** | 0 | No strict `DEF-01..04` defect with an obvious mechanical repair. |
| **SME** | 7 | SEM-05 (SET/`UNION` collapse — primary), FN-LATEST/SEM-02 (latest-value key width), SEM-06/DTX-10 (implicit casts in `||` and in `param_value` comparison), SEM-10 (join direction), DEF-05 (missing target column list), SEM-04/SEM-03 (TZ/CHAR — pending DDL). |

**Every finding is `SME`.** There is nothing for Stage 3 to fix mechanically
without human input — exactly as the lessons-learned entry predicts
(*"changed 0 SQL lines"* on the prior automated pass). The remediation is
**semantic**, not syntactic.

## 6. Table dependency inventory

| Role | Table | Lines |
|---|---|---|
| Target | `staging.wrk_target` | 1 (INSERT) |
| Source | `synthetic_flgt_source` (alias `src`) | 14, 44, 74 |
| Source | `synthetic_mkg_flgt_leg` (alias `leg`) | 15 |
| Source | `synthetic_operational_flgt_leg` (alias `leg`) | 45 |
| Source | `synthetic_codeshare_flgt_leg` (alias `cs`) | 75 |
| Source | `synthetic_sys_param` | 22, 52, 82 (correlated subquery, `param_id = 'UPDATE_CUTOFF'`) |

## 7. Verdict

**One statement** (one `INSERT`, three `SELECT` branches, two `UNION`). The file
**parses cleanly on Snowflake** — zero `SFX/FNX/DTX` syntax errors and zero
strict `DEF-*` defects. The entire remediation surface is **semantic**:

1. **SEM-05 (primary):** the three branches are merged with `UNION` into a
   single `INSERT` on `staging.wrk_target`. Per `06_lessons_learned.md` the
   Teradata original used three independent INSERTs into a SET table. `UNION`
   both (a) de-duplicates **across branches** (wrong — each SET-table INSERT
   dedups only against existing target rows) and (b) is the wrong operator even
   for a MULTISET target unless cross-branch dedup is intended. Because the
   target's `CREATE TABLE` DDL is **not supplied**, SET/MULTISET cannot be
   confirmed from this script — **raise SME question Q1** and do not assume.
   The likely fix (pending SME confirmation) is to split into three separate
   `INSERT … EXCEPT` statements (if SET) or three `INSERT … UNION ALL` branches
   (if MULTISET and cross-branch dedup is *not* intended).
2. **FN-LATEST / SEM-02:** the `SUBSTR(MAX(effective_dt || col), 11, …)`
   latest-value trick needs an explicit fixed-width key
   (`TO_CHAR(effective_dt,'YYYY-MM-DD') || LPAD(col::VARCHAR, n, ' ')`) before
   `MAX`, else the tie-break can pick the wrong row.
3. **SEM-06 / DTX-10:** implicit string casts in the `||` concatenation and in
   the `param_value` date comparison need explicit `TO_CHAR`/`TO_DATE`.

**Stage 3 must not touch this file until Q1 (SET vs MULTISET) is answered.**
Until then any "fix" would be a guess. All findings are `SME`.