# Stage 1 — Analysis: `SFIssueSET.sql`

**Input:** `00_input/SFIssueSET.sql`
**Teradata ground truth:** none supplied (no `00_input/SFIssueSET.teradata.sql`).
**Reviewer guidance:** `07_review/output/review_SFIssueSET.md` — *"This is a SET
table in teradata. So, there should not be any duplicates. You need to handle the
dedup logic in the query."* → `staging.wrk_target` is a **SET table**; SEM-05 is
confirmed and classified **FIX** (not SME).

---

## 1. Column-count check (INSERT target cols vs SELECT expressions)

The statement is a single `INSERT INTO staging.wrk_target` (no explicit target
column list) followed by a 3-branch `UNION`.

- **INSERT target columns:** none listed explicitly — Snowflake binds by ordinal
  position to the target table's physical column order. Because no target DDL
  is supplied, the target column order is **unknown** and must be flagged
  `TODO(SME)`.
- **SELECT expressions per branch:** 8, identical across all 3 branches:

| # | SELECT expression | Alias |
|---|---|---|
| 1 | `src.airline_cd` | — |
| 2 | `src.flgt_no` | — |
| 3 | `src.flgt_dt` | — |
| 4 | `SUBSTR(MAX(src.effective_dt \|\| leg.company_cd), 11, 99)` | `company_cd` |
| 5 | `SUBSTR(MAX(src.effective_dt \|\| leg.direction_ind), 11, 99)` | `direction_ind` |
| 6 | `SUBSTR(MAX(src.effective_dt \|\| leg.operating_airline_cd), 11, 3)` | `operating_airline_cd` |
| 7 | `SUBSTR(MAX(src.effective_dt \|\| leg.operating_flgt_no), 11, 99)` | `operating_flgt_no` |
| 8 | `SUBSTR(MAX(src.effective_dt \|\| leg.operating_sfx_cd), 11, 99)` | `operating_sfx_cd` |

- **Duplicates on either side:** none within a branch.
- **Net after removing duplicates:** 8 expressions per branch.
- **Branch-to-branch consistency:** all 3 branches project the same 8 columns in
  the same order — `UNION` set-operator column alignment is valid.
- **Count verdict:** 8 = 8 per branch; no INSERT/SELECT count mismatch (DEF-05
  does not fire). The open risk is the **unknown target column order** (no DDL),
  which is a SEM-05/SME concern, not a count defect.

---

## 2. Syntax errors / residual-Teradata constructs

The file is **parse-clean Snowflake**. No `SFX-*`, `FNX-*`, or `DTX-*` rule
fires. Inventory below confirms the scan.

| Line(s) | Construct | Rule | Invalid on Snowflake? | Classification |
|---|---|---|---|---|
| — | `CONTAINS` / `OVERLAPS` (PERIOD ops) | SFX-01/02 | n/a — absent | — |
| — | `ZEROIFNULL` / `NULLIFZERO` | FNX-01/02 | n/a — absent | — |
| — | `SEL` shorthand | SFX-04 | n/a — absent | — |
| — | `SET`/`MULTISET` in DDL | SFX-05 | n/a — no DDL in file | — |
| — | `PRIMARY INDEX` | SFX-06 | n/a — absent | — |
| — | `COLLECT STATS` / `HELP STATS` | SFX-07 | n/a — absent | — |
| — | BTEQ dot-commands | SFX-08 | n/a — absent | — |
| — | `LOCKING ROW/TABLE FOR ACCESS` | SFX-09 | n/a — absent | — |
| — | `(+)` outer joins | SFX-10 | n/a — absent | — |
| — | Unbalanced parens | SFX-11 | n/a — absent | — |
| — | Trailing/missing comma | SFX-12 | n/a — absent | — |
| — | `TOP n` | SFX-13 | n/a — absent | — |
| — | `MINUS` | SFX-14 | n/a — absent (uses `UNION`) | — |
| — | `CAST(... FORMAT ...)` | SFX-15 / FNX-08 | n/a — absent | — |
| — | `BYTEINT`, `CHARACTER SET LATIN` | DTX-01/02 | n/a — no DDL | — |
| — | `INDEX`, `OREPLACE`, `OTRANSLATE`, `STRTOK` | FNX-04/05/06/07 | n/a — absent | — |
| — | `**`, `MOD` infix, `LIKE ANY` | FNX-09/10/11 | n/a — absent | — |
| — | `HASHROW`/`HASHBUCKET`/`HASHAMP` | FNX-12 | n/a — absent | — |
| — | `TITLE`/`FORMAT` phrases | FNX-13 | n/a — absent | — |

**SnowSQL client layer (SNZ-*):** input is `.sql`, not `.snowsql` — no
`<% %>` template tags, no `PUT`/`GET` commands. SNZ rules do not apply.

**Syntax verdict:** 0 mechanical syntax fixes. The file parses and compiles on
Snowflake. The bugs are **purely semantic** (see §4).

---

## 3. Defects (DEF-*)

| Line(s) | Defect | Rule | Classification |
|---|---|---|---|
| — | Duplicate column in INSERT list | DEF-01 | n/a — absent |
| — | Missing whitespace / keyword typo | DEF-02 | n/a — absent |
| — | Unbalanced parentheses | DEF-03 | n/a — absent |
| — | Malformed function call | DEF-04 | n/a — absent |
| 1 / each branch | INSERT col count ≠ SELECT expr count | DEF-05 | n/a — 8 = 8 per branch (see §1) |
| — | Alias ≠ target column name | DEF-06 | n/a — aliases are cosmetic; positional binding |
| — | Wrong column referenced (copy-paste) | DEF-07 | n/a — no sibling-pattern evidence |

**Defect verdict:** 0 defects. The `SUBSTR(MAX(...), 11, N)` pattern is
syntactically valid; its semantic correctness is assessed under §4 (SEM-02 /
FN-LATEST).

---

## 4. Semantic risks (SEM-*)

| ID | Risk | Present? | Detail | Classification |
|---|---|---|---|---|
| **SEM-05** | **SET-table dedup** | **Yes — confirmed** | Single `INSERT INTO staging.wrk_target` with 3 `UNION` branches. Reviewer confirms `staging.wrk_target` is a **SET table** in Teradata. A Teradata SET table silently drops full-row duplicates on INSERT. The buggy Snowflake collapses 3 independent Teradata INSERTs into one `INSERT … UNION … UNION`, which (a) re-inserts rows already present in the target and (b) de-duplicates **across** branches via `UNION` — the wrong dedup axis. Per SEM-05 (SET confirmed), port each branch as an independent `INSERT INTO staging.wrk_target (col list) (SELECT … EXCEPT SELECT * FROM staging.wrk_target)`. Remove `UNION` operators entirely. Add an explicit target column list so the `EXCEPT SELECT *` positional match is unambiguous. | **FIX** |
| SEM-02 | Dedup / `MAX` ordering (FN-LATEST) | Yes | `SUBSTR(MAX(src.effective_dt \|\| <val>), 11, N)` in all 3 branches (lines 5–10, 28–33, 51–56). This is the "latest-value trick": concatenate a sortable date key with the value, take `MAX`, then `SUBSTR` off the key. Correctness depends on `effective_dt` being a **fixed-width, lexicographically sortable** string. If `effective_dt` is a `DATE`/`TIMESTAMP`, Snowflake's implicit cast to string may not be zero-padded or may include time components, so `MAX` can pick the wrong row. The fix is to format the key explicitly: `TO_CHAR(src.effective_dt,'YYYY-MM-DD') \|\| LPAD(<val>::VARCHAR, n, ' ')` before `MAX`. Requires source DDL / data-type confirmation before a mechanical change is safe. | **SME** |
| SEM-06 | Implicit cast / NULL in comparison | Yes | `src.flgt_dt > (SELECT param_value FROM synthetic_sys_param WHERE param_id = 'UPDATE_CUTOFF')` (lines 18–22, 41–45, 64–68). `param_value` is an implicit string→date cast: if `param_value` is `VARCHAR` and `flgt_dt` is `DATE`, Snowflake's strict casting may error or mismatch depending on the string format. Also `effective_dt \|\| <val>` (the FN-LATEST concatenation) relies on implicit date→string cast whose format depends on session defaults. Make casts explicit (`TO_DATE(param_value, '<fmt>')`, `TO_CHAR(effective_dt, 'YYYY-MM-DD')`). Requires DDL / format confirmation. | **SME** |
| SEM-03 | `CHAR(n)` padding & comparison | Maybe | Join keys `airline_cd`, `flgt_no`, `company_cd`, `*_stn_cd`, etc. may be `CHAR(n)` in source/target. If so, Teradata blank-pads and ignores trailing spaces in `=`; Snowflake does not pad, so join/`EXCEPT` matching can drift. Cannot confirm without DDL. | **SME** |
| SEM-04 | Timestamp / timezone | Maybe | `flgt_dt` / `gmt_flgt_dt` / `effective_dt` may be `TIMESTAMP` vs `TIMESTAMP_TZ` vs `DATE`. If `gmt_*` columns carry timezone semantics, a NTZ/TZ mismatch shifts values. Cannot confirm without DDL. | **SME** |
| SEM-07 | `NULL` ordering | No | No `ORDER BY` feeding a `QUALIFY`/`TOP`. The `MAX` aggregate ignores NULLs by default; not a NULL-ordering risk here. | — |
| SEM-01 | Integer division | No | No `/` division present. | — |
| SEM-08 | Empty string vs NULL | No | No `''` / `NULLIF(x,'')` present. | — |
| SEM-09 | Aggregate of empty set | No | `MAX` over an empty group returns NULL by design; no downstream division depends on it. | — |
| SEM-10 | Lookup join direction | Maybe | The 3 branches join `synthetic_flgt_source` to `synthetic_mkg_flgt_leg`, `synthetic_operational_flgt_leg`, and `synthetic_codeshare_flgt_leg` respectively. Join key direction (marketing vs operating vs codeshare) is plausible from the names but cannot be verified against Teradata without ground truth. Flag for SME spot-check. | **SME** |

### SEM-05 detail (the critical finding)

- **Signal:** one `INSERT INTO staging.wrk_target` + 3 `UNION` branches, all
  writing to the same target.
- **DDL supplied?** No — but the **reviewer has confirmed** the target is a SET
  table, which is the missing DDL fact SEM-05 requires. Per the Stage-1 contract,
  reviewer confirmation closes the SME question and moves SEM-05 to **FIX**.
- **Why the current SQL is wrong:**
  1. `UNION` (not `UNION ALL`) de-duplicates **across** the 3 branches. In
     Teradata the 3 INSERTs were independent — each was deduped **against the
     target's existing rows** (SET semantics), not against each other. `UNION`
     is the wrong dedup axis.
  2. Even with `UNION ALL`, a plain `INSERT` would re-insert rows already
     present in the target, violating SET-table "drop rows already present"
     semantics.
- **Fix pattern (SEM-05, SET confirmed):** split into 3 independent
  `INSERT INTO staging.wrk_target (airline_cd, flgt_no, flgt_dt, company_cd,
  direction_ind, operating_airline_cd, operating_flgt_no, operating_sfx_cd)
  (SELECT … EXCEPT SELECT * FROM staging.wrk_target)` statements — one per
  branch. Remove `UNION` operators entirely. The explicit column list makes the
  `EXCEPT SELECT *` positional match unambiguous (the target column order
  itself remains `TODO(SME)` until DDL is supplied).

---

## 5. Classification summary

| Finding | Rule | Classification |
|---|---|---|
| SET-table dedup — 3 `UNION` branches into one SET target | SEM-05 | **FIX** (reviewer-confirmed SET) |
| Latest-value trick `SUBSTR(MAX(effective_dt \|\| val), 11, N)` — key width/sortability | SEM-02 / FN-LATEST | **SME** |
| Implicit `param_value` string→date cast in `WHERE` | SEM-06 / DTX-10 | **SME** |
| `effective_dt \|\| val` implicit date→string cast | SEM-06 | **SME** |
| `CHAR(n)` padding drift on join/`EXCEPT` keys | SEM-03 | **SME** |
| `TIMESTAMP` vs `TIMESTAMP_TZ` on `gmt_*` / `effective_dt` | SEM-04 | **SME** |
| Join-key direction (marketing/operating/codeshare) | SEM-10 | **SME** |
| Target column order unknown (no DDL) | SEM-05 (sub) | **SME** |

**Counts:** 1 FIX, 6 SME, 0 AUTO. 0 mechanical syntax/function/defect fixes.

---

## 6. Table dependency inventory

| Table | Role | Notes |
|---|---|---|
| `staging.wrk_target` | **TARGET** (SET table, reviewer-confirmed) | Single INSERT target; 3 `UNION` branches. No DDL supplied → column order is `TODO(SME)`. |
| `synthetic_flgt_source` | SOURCE | Joined in all 3 branches (alias `src`); provides `airline_cd`, `flgt_no`, `flgt_dt`, `effective_dt`. |
| `synthetic_mkg_flgt_leg` | SOURCE | Branch 1 join (alias `leg`); marketing-leg attributes. |
| `synthetic_operational_flgt_leg` | SOURCE | Branch 2 join (alias `leg`); operational-leg attributes. |
| `synthetic_codeshare_flgt_leg` | SOURCE | Branch 3 join (alias `cs`); codeshare-leg attributes. |
| `synthetic_sys_param` | SOURCE (param lookup) | Subquery in each branch's `WHERE`: `param_id = 'UPDATE_CUTOFF'` → `param_value`. |

---

## 7. Verdict

**Parse-clean, purely semantic.** The single critical fix is **SEM-05
(SET-table dedup, reviewer-confirmed)**: split the 3-branch `INSERT … UNION …
UNION` into 3 independent `INSERT … EXCEPT SELECT * FROM staging.wrk_target`
statements with an explicit target column list. Six SME-classified semantic
risks (FN-LATEST key width, implicit `param_value` cast, `CHAR` padding, TZ,
join direction, target column order) carry forward as `TODO(SME)` markers
pending source DDL / Teradata ground truth.