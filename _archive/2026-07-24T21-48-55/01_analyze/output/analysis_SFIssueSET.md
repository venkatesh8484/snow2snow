# Stage 1 — Analysis: `SFIssueSET.sql`

**Input:** `00_input/SFIssueSET.sql`
**Teradata ground truth:** none (`00_input/SFIssueSET.teradata.sql` not present).
**Target dialect:** Snowflake.
**Date:** 2026-07-24.

> **Archive note:** Prior outputs for this unit were archived by the
> orchestrator (`05_report/archive_outputs.py SFIssueSET`). No stale live
> artifacts remain in `01_analyze/output/` for this unit.

---

## 1. Column-count check

The statement is a single `INSERT INTO staging.wrk_target` with **no explicit
INSERT column list** (line 1). The SELECT is three branches joined by `UNION`
(lines 30, 60). Because there is no target column list, the SELECT expression
count must equal the number of columns in `staging.wrk_target` (unknown — no
DDL supplied).

| Branch | Lines | SELECT expression count | Duplicates in branch |
|---|---|---|---|
| Branch 1 (marketing leg) | 2–28 | 8 | none |
| Branch 2 (operational leg) | 32–58 | 8 | none |
| Branch 3 (codeshare leg) | 62–88 | 8 | none |

SELECT expressions per branch (identical position list in all three):

| # | Expression (branch 1 line) | Alias |
|---|---|---|
| 1 | `src.airline_cd` (3) | — |
| 2 | `src.flgt_no` (4) | — |
| 3 | `src.flgt_dt` (5) | — |
| 4 | `SUBSTR(MAX(src.effective_dt \|\| leg.company_cd), 11, 99)` (6) | `company_cd` |
| 5 | `SUBSTR(MAX(src.effective_dt \|\| leg.direction_ind), 11, 99)` (7) | `direction_ind` |
| 6 | `SUBSTR(MAX(src.effective_dt \|\| leg.operating_airline_cd), 11, 3)` (8–9) | `operating_airline_cd` |
| 7 | `SUBSTR(MAX(src.effective_dt \|\| leg.operating_flgt_no), 11, 99)` (10–11) | `operating_flgt_no` |
| 8 | `SUBSTR(MAX(src.effective_dt \|\| leg.operating_sfx_cd), 11, 99)` (12–13) | `operating_sfx_cd` |

**Net:** 8 expressions per branch, 0 duplicates within any branch. All three
branches expose the same 8 columns in the same order — the `UNION` is
positionally consistent.

**DEF-05 check:** INSERT column count cannot be verified because no target
column list is present and no `CREATE TABLE staging.wrk_target` DDL is supplied.
This is **not** a defect in the SQL itself, but it is an open dependency — see
the SME question in §4 (SEM-05) and the dependency inventory in §6.

---

## 2. Syntax errors / residual-Teradata constructs

| # | Line(s) | Construct | Rule | Why invalid / action |
|---|---|---|---|---|
| — | — | — | — | **None found.** |

The file contains **no** residual Teradata constructs. Specifically, none of the
following are present: `CONTAINS`/`OVERLAPS` (SFX-01/02), `SEL` (SFX-04),
`SET`/`MULTISET` in DDL (SFX-05), `PRIMARY INDEX` (SFX-06), `COLLECT STATS`
(SFX-07), BTEQ directives (SFX-08), `LOCKING` (SFX-09), `(+)` joins (SFX-10),
unbalanced parens (SFX-11), trailing/missing commas (SFX-12), `TOP` (SFX-13),
`MINUS` (SFX-14), `CAST(... FORMAT ...)` (SFX-15/FNX-08), `ZEROIFNULL`/
`NULLIFZERO` (FNX-01/02), `INDEX` (FNX-04), `OREPLACE`/`OTRANSLATE`/
`STRTOK` (FNX-05/06/07), `**` (FNX-10), `LIKE ANY` (FNX-11), `HASHROW` etc
(FNX-12), `TITLE`/`FORMAT` phrases (FNX-13), `SUBSTRING(s FROM a FOR b)`
(FNX-15).

The file **parses** on Snowflake as written. The bugs are semantic, not
syntactic (see §4). This matches the 2026-07-24 lesson: *"A parse PASS is not
correctness."*

---

## 3. Defects (DEF-*)

| # | Line(s) | Defect | Rule | Class | Notes |
|---|---|---|---|---|---|
| — | — | — | — | — | **No structural defects found.** |

No duplicate INSERT columns (DEF-01), no whitespace typos (DEF-02), no
unbalanced parentheses (DEF-03), no malformed function calls (DEF-04), no
INSERT/SELECT count mismatch detectable from the SQL alone (DEF-05 — see §1),
no wrong column references provable without Teradata (DEF-07).

---

## 4. Semantic risks (SEM-*)

| # | Line(s) | Risk | Rule | Class | Detail |
|---|---|---|---|---|---|
| S1 | 1, 30, 60 | **SET-table dedup — single INSERT with 3 UNION branches into one target** | **SEM-05** | **SME** | The file is one `INSERT INTO staging.wrk_target` whose SELECT is three branches joined by `UNION`. Per SEM-05 and the 2026-07-24 lesson, this is a SET-dedup **signal**: the delivered file appears to have collapsed three independent Teradata INSERTs into a SET table into one Snowflake `INSERT … UNION …`. **No `CREATE TABLE staging.wrk_target` DDL is supplied**, so SET vs MULTISET cannot be decided from the SQL alone. **SME question: "Is `staging.wrk_target` a SET table?"** If yes, each branch must be ported as a separate `INSERT INTO staging.wrk_target (SELECT … EXCEPT SELECT * FROM staging.wrk_target)` — never a single cross-branch `UNION`. Do **not** assume SET. |
| S2 | 30, 60 | **`UNION` vs `UNION ALL` set-semantics** | SEM-05 (cross-ref lesson) | **SME** | Two `UNION` operators (de-duplicating) join the three branches. The 2026-07-24 lesson says: flag every `UNION` for a set-semantics check. With no Teradata ground truth, we cannot confirm whether the original used separate INSERTs (SET-table dedup) or `UNION ALL`. `UNION` here both (a) de-duplicates *across* branches and (b) re-inserts rows already present in the target if the target is not SET. Both behaviors are likely wrong. **SME question: "Should the three branches be `UNION ALL` (preserve cross-branch duplicates) or separate INSERTs (SET-table dedup)?"** |
| S3 | 6–13, 33–40, 63–70 | **Latest-value trick needs fixed-width key** | SEM-02 / lesson FN-LATEST | **SME** | Every value column uses `SUBSTR(MAX(src.effective_dt \|\| <val>), 11, …)` to pick the value from the row with the maximum `effective_dt` per group. This "latest-value" trick concatenates a date and a value, takes `MAX`, then strips the date prefix. It is correct **only if** the concatenated key is fixed-width so that string `MAX` ordering matches chronological ordering. `src.effective_dt` is concatenated raw (no `TO_CHAR` format) and the value is not `LPAD`-ed to a fixed width. If `effective_dt` is a DATE/TIMESTAMP, Snowflake's implicit cast to string may not be lexicographically sortable (e.g. timestamp with spaces/colons), and variable-width values can break the `MAX` tie-break. Per the 2026-07-24 lesson: format as `TO_CHAR(effective_dt,'YYYY-MM-DD') \|\| LPAD(val::VARCHAR,n,' ')` before `MAX`. **SME question: "Is `src.effective_dt` a DATE (sortable as `YYYY-MM-DD`) or a TIMESTAMP (needs explicit format)? What is the max display width of each concatenated value column for LPAD?"** |
| S4 | 6–13, 33–40, 63–70 | **`MAX` over string concatenation — tie-break non-determinism** | SEM-02 | **SME** | `MAX(src.effective_dt \|\| <val>)` orders by the concatenated string. If two rows share the same `effective_dt` but differ in the value, the `MAX` picks the lexicographically larger *value*, not necessarily the intended one. This is inherent to the latest-value idiom and is only safe when `effective_dt` is unique per group. **SME question: "Is `effective_dt` unique per `(airline_cd, flgt_no, flgt_dt)` group, or can ties occur?"** |
| S5 | 17, 47, 77 | **Scalar subquery `param_value` implicit cast** | SEM-06 | **SME** | `src.flgt_dt > (SELECT param_value FROM synthetic_sys_param WHERE param_id = 'UPDATE_CUTOFF')`. `param_value` is presumably a string parameter table; comparing it to `flgt_dt` (a date) relies on an implicit string→date cast. Snowflake is stricter than Teradata (SEM-06/DTX-10). If `param_value` is not in an ISO date format, this may error or silently mismatch. **SME question: "Is `synthetic_sys_param.param_value` a date-formatted string (e.g. `YYYY-MM-DD`)? Should the comparison be `src.flgt_dt > TO_DATE(param_value, 'YYYY-MM-DD')`?"** |
| S6 | 8–9, 35–36, 65–66 | **`operating_airline_cd` truncated to width 3 vs others width 99** | SEM (consistency) | **SME** | `operating_airline_cd` uses `SUBSTR(..., 11, 3)` while all other value columns use `SUBSTR(..., 11, 99)`. This is likely intentional (airline codes are 2–3 chars) but, with no Teradata ground truth, cannot be confirmed. Not a defect (DEF-06/DEF-07 do not apply without ground truth). **SME question: "Is the width-3 truncation on `operating_airline_cd` intentional?"** |

**SEM-05 is the critical finding.** Per the mode instructions and SEM-05 rule:
SET vs MULTISET lives in the target's `CREATE TABLE` DDL, not in an INSERT-only
script. No DDL for `staging.wrk_target` is supplied. The file has a `UNION`
whose branches all write to one target — a SET-dedup signal. **Do not decide.**
Raise the SME question and classify `SME`.

---

## 5. Classification summary

| Finding | Rule | Class |
|---|---|---|
| S1 — SET-table dedup signal (single INSERT, 3 UNION branches, no DDL) | SEM-05 | **SME** |
| S2 — `UNION` vs `UNION ALL` set-semantics | SEM-05 / lesson | **SME** |
| S3 — Latest-value trick needs fixed-width key | SEM-02 / FN-LATEST | **SME** |
| S4 — `MAX` over string concat tie-break non-determinism | SEM-02 | **SME** |
| S5 — Scalar subquery implicit string→date cast | SEM-06 / DTX-10 | **SME** |
| S6 — `operating_airline_cd` width-3 truncation consistency | SEM (consistency) | **SME** |

**AUTO:** 0 — nothing to fix mechanically; the file parses clean.
**FIX:** 0 — no structural defects.
**SME:** 6 — all findings require human/subject-matter-expert decisions.

---

## 6. Table dependency inventory

| Role | Table / alias | Lines | Notes |
|---|---|---|---|
| **Target (INSERT)** | `staging.wrk_target` | 1 | SET vs MULTISET unknown — no DDL supplied (SEM-05). |
| Source | `synthetic_flgt_source` (`src`) | 11, 41, 71 | Common source in all 3 branches; provides `airline_cd`, `flgt_no`, `flgt_dt`, `effective_dt`. |
| Source | `synthetic_mkg_flgt_leg` (`leg`) | 12 | Branch 1 — marketing leg; joined on marketing carrier/flight/date. |
| Source | `synthetic_operational_flgt_leg` (`leg`) | 42 | Branch 2 — operational leg; joined on operating carrier/flight/date. |
| Source | `synthetic_codeshare_flgt_leg` (`cs`) | 72 | Branch 3 — codeshare leg; joined on codeshare carrier/flight/date. |
| Source | `synthetic_sys_param` | 19, 49, 79 | Parameter lookup; `param_id = 'UPDATE_CUTOFF'` scalar subquery in all 3 branches. |

---

## 7. Verdict

**Parses clean on Snowflake (0 syntax/defect findings) but carries 6 SME
semantic risks — the critical one being SEM-05: a single `INSERT … UNION …
UNION` into `staging.wrk_target` with no target DDL is a SET-table dedup signal
that must be confirmed by SME before any fix.**