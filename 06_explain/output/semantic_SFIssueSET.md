# Stage 6 — Semantic explanation: `SFIssueSET.sql`

**Fixed SQL:** `03_fix/output/SFIssueSET_fixed.sql`
**Analysis:** `01_analyze/output/analysis_SFIssueSET.md`
**Validation:** `04_validate/output/validation_SFIssueSET.md` (PASS — 3 stmts, 8=8 cols, no residual Teradata, 8 TODO(SME))
**Teradata ground truth:** **none supplied** (no `00_input/SFIssueSET.teradata.sql`).
Every semantic inference below is therefore flagged `TODO(SME)`; intent is
inferred from `02_rules/` and the Snowflake input alone, per SEM policy.
**Reviewer guidance:** `02_rules/06_lessons_learned.md` records the reviewer's
authoritative confirmation verbatim — *"This is a SET table in teradata. So,
there should not be any duplicates. You need to handle the dedup logic in the
query."* — which closes the SEM-05 SME question and moves it to FIX.

---

## 1. Purpose

`SFIssueSET.sql` populates the target table `staging.wrk_target` with one row
per `(airline_cd, flgt_no, flgt_dt)` flight key, attaching the **latest**
known `company_cd`, `direction_ind`, `operating_airline_cd`,
`operating_flgt_no`, and `operating_sfx_cd` attributes for that flight. The
data is sourced from `synthetic_flgt_source` joined to three leg tables —
`synthetic_mkg_flgt_leg` (marketing), `synthetic_operational_flgt_leg`
(operational), and `synthetic_codeshare_flgt_leg` (codeshare) — one branch
per leg type. Each branch groups by the flight key, picks the most recent
`effective_dt` per attribute using the `SUBSTR(MAX(effective_dt || val), 11, N)`
"latest-value trick", and filters to flights after the `UPDATE_CUTOFF`
parameter. The target is a **SET table** (reviewer-confirmed), so each branch
must dedup its rows **against the target's existing rows** — not against the
other branches. The remediation therefore splits the original single
`INSERT … UNION … UNION` into three independent
`INSERT … ( SELECT … EXCEPT SELECT * FROM staging.wrk_target )` statements,
which reproduces Teradata SET-table "drop rows already present" semantics on
Snowflake.

---

## 2. Statement-by-statement walk-through

The fixed file contains **three** `INSERT INTO staging.wrk_target (col list)`
statements, one per leg type. They are structurally identical except for the
joined leg table and its join keys; the walk-through below uses branch 1
(marketing) and notes the per-branch deltas.

### 2.1 INSERT target list (all three statements)

```
INSERT INTO staging.wrk_target
( airline_cd, flgt_no, flgt_dt, company_cd, direction_ind,
  operating_airline_cd, operating_flgt_no, operating_sfx_cd )
```

An **explicit** 8-column target list is added by the SEM-05 fix. The original
buggy input had no explicit list (Snowflake bound by ordinal position to the
target's unknown physical order). The explicit list makes the
`EXCEPT SELECT * FROM staging.wrk_target` positional match unambiguous. The
target physical column order itself remains `TODO(SME)` until DDL is supplied
— if the physical order differs from this list, the `EXCEPT` will mismatch.

### 2.2 SELECT projection (8 columns)

1. `src.airline_cd`, `src.flgt_no`, `src.flgt_dt` — the flight key, carried
   straight from `synthetic_flgt_source`.
2. `SUBSTR(MAX(src.effective_dt || leg.company_cd), 11, 99) AS company_cd` —
   the **latest-value trick** (SEM-02 / FN-LATEST). Concatenate a sortable
   `effective_dt` key with the value, take `MAX` over the group, then `SUBSTR`
   off the 10-character key prefix to recover the value belonging to the
   latest `effective_dt`. Correctness depends on the key being fixed-width and
   lexicographically sortable; see §3 SEM-02.
3. The same trick is repeated for `direction_ind` (width 99),
   `operating_airline_cd` (width **3** — narrower than the others),
   `operating_flgt_no` (99), and `operating_sfx_cd` (99).

### 2.3 FROM / JOIN (per-branch delta)

- **Branch 1:** `synthetic_flgt_source src JOIN synthetic_mkg_flgt_leg leg`
  on `marketing_airline_cd / marketing_flgt_no / gmt_flgt_dt`.
- **Branch 2:** `… JOIN synthetic_operational_flgt_leg leg` on
  `operating_airline_cd / operating_flgt_no / gmt_flgt_dt`.
- **Branch 3:** `… JOIN synthetic_codeshare_flgt_leg cs` on
  `codeshare_airline_cd / codeshare_flgt_no / gmt_flgt_dt`.

The join-key direction (marketing vs operating vs codeshare) is plausible
from the names but unprovable without Teradata ground truth → SEM-10 SME.

### 2.4 WHERE

- `leg.dep_stn_cd <> leg.arr_stn_cd` — drops self-loops (departure station
  equals arrival station).
- `src.flgt_dt > ( SELECT param_value FROM synthetic_sys_param WHERE
  param_id = 'UPDATE_CUTOFF' )` — keeps only flights newer than the cutoff
  parameter. `param_value` is an implicit string→date cast (SEM-06/DTX-10).

### 2.5 GROUP BY

`GROUP BY src.airline_cd, src.flgt_no, src.flgt_dt` — collapses to one row per
flight key; the `MAX(…)` aggregates pick the latest attribute values.

### 2.6 EXCEPT SELECT * FROM staging.wrk_target (the SEM-05 fix)

Each branch's grouped SELECT is wrapped as
`( SELECT … EXCEPT SELECT * FROM staging.wrk_target )`. The `EXCEPT` removes
any row already present in the target, reproducing Teradata SET-table "drop
rows already present on INSERT" semantics. Doing this **per branch** preserves
the independent-dedup behaviour of the original three Teradata INSERTs.

### 2.7 Why UNION was removed

The buggy input collapsed the three Teradata INSERTs into one
`INSERT … SELECT … UNION … SELECT … UNION … SELECT …`. That was wrong on two
axes:

1. **`UNION` (not `UNION ALL`) de-duplicates *across* the three branches.** In
   Teradata the three INSERTs were independent — each was deduped *against the
   target's existing rows* (SET semantics), not against each other. `UNION` is
   the wrong dedup axis: a row present in both the marketing and operational
   branches would be silently dropped from one, which the original Teradata
   SET-table logic did not do.
2. **A plain `INSERT` re-inserts rows already present in the target**, violating
   SET-table "drop rows already present" semantics. Only the `EXCEPT SELECT *
   FROM tgt` form reproduces that.

The fix removes `UNION` entirely and emits three independent
`INSERT … EXCEPT` statements.

---

## 3. Semantic checks table

| SEM ID | Risk | Present? | Corrected how? | Equivalent to Teradata? |
|---|---|---|---|---|
| **SEM-05** | SET-table dedup | **Yes — confirmed (reviewer)** | Split the single `INSERT … UNION … UNION` into 3 independent `INSERT INTO staging.wrk_target (col list) ( SELECT … EXCEPT SELECT * FROM staging.wrk_target )` statements; `UNION` operators removed; explicit 8-column INSERT list added. | **Yes** — reproduces SET-table "drop rows already present" per-branch, which is what the three independent Teradata INSERTs did. |
| SEM-05 (sub) | Target column order unknown (no DDL) | Yes | Explicit INSERT column list added so `EXCEPT SELECT *` positional match is unambiguous. | **SME** — the physical column order of `staging.wrk_target` is unknown; if it differs from the explicit list, the `EXCEPT` mismatches. `TODO(SME)`. |
| SEM-02 / FN-LATEST | `MAX` dedup / latest-value trick key width | Yes | **Not mechanically rewritten.** The `SUBSTR(MAX(effective_dt || val), 11, N)` trick needs a fixed-width, lexicographically sortable key; the safe form is `TO_CHAR(effective_dt,'YYYY-MM-DD') || LPAD(val::VARCHAR,n,' ')` before `MAX`. Flagged `TODO(SME)` pending `effective_dt` type + value display-width confirmation. | **SME** — if `effective_dt` is a `DATE`/`TIMESTAMP`, Snowflake's implicit string cast may not be zero-padded, so `MAX` can pick the wrong row. |
| SEM-06 / DTX-10 | Implicit `param_value` string→date cast | Yes | **Not rewritten.** `src.flgt_dt > (SELECT param_value …)` relies on an implicit string→date cast whose format depends on session defaults. Safe form: `TO_DATE(param_value,'YYYY-MM-DD')`. Flagged `TODO(SME)`. | **SME** — strict Snowflake casting may error or mismatch depending on the string format. |
| SEM-06 | `effective_dt || val` implicit date→string cast | Yes | **Not rewritten.** Same root cause as SEM-02: the concatenation relies on an implicit date→string cast. Flagged with the SEM-02 marker. | **SME** — format depends on session defaults. |
| SEM-03 | `CHAR(n)` padding & comparison | Maybe | **Not rewritten.** Join keys (`airline_cd`, `flgt_no`, `company_cd`, `*_stn_cd`, …) may be `CHAR(n)`; Teradata blank-pads and ignores trailing spaces in `=`, Snowflake does not. Cannot confirm without DDL. Flagged `TODO(SME)`. | **SME** — padding drift can change which rows the `EXCEPT`/JOIN match. |
| SEM-04 | Timestamp / timezone | Maybe | **Not rewritten.** `flgt_dt` / `gmt_flgt_dt` / `effective_dt` may be `TIMESTAMP` vs `TIMESTAMP_TZ` vs `DATE`. Cannot confirm without DDL. Flagged `TODO(SME)`. | **SME** — a NTZ/TZ mismatch shifts values. |
| SEM-10 | Lookup join direction | Maybe | **Not rewritten.** The three branches join to marketing/operational/codeshare leg tables; direction is plausible from names but unprovable. Flagged `TODO(SME)`. | **SME** — confirm against Teradata ground truth. |
| SEM-01 | Integer division | No | n/a | n/a |
| SEM-07 | `NULL` ordering feeding `QUALIFY`/`TOP` | No | n/a (no `ORDER BY`/`QUALIFY`) | n/a |
| SEM-08 | Empty string vs NULL | No | n/a | n/a |
| SEM-09 | Aggregate of empty set | No | `MAX` over an empty group returns NULL by design; no downstream division depends on it. | n/a |

---

## 4. Divergences from the original

| # | Divergence | Justification |
|---|---|---|
| 1 | Single `INSERT … UNION … UNION` → three independent `INSERT … EXCEPT SELECT * FROM staging.wrk_target` statements. | SEM-05 (SET confirmed by reviewer). `UNION` deduped *across* branches (wrong axis) and a plain `INSERT` re-inserted existing rows; the per-branch `EXCEPT` reproduces Teradata SET-table per-INSERT dedup. |
| 2 | Explicit 8-column INSERT target list added to each statement. | Part of the SEM-05 fix: makes the `EXCEPT SELECT * FROM staging.wrk_target` positional match unambiguous without target DDL. |
| 3 | `UNION` operators removed entirely. | `UNION` is the wrong dedup axis for a SET table (see §2.7). |

No other SQL logic was changed. Column order, JOIN keys, CASE-branch order,
and the `SUBSTR(MAX(...),11,N)` projection are all preserved exactly. The six
SME-classified risks (SEM-02, SEM-06 ×2, SEM-03, SEM-04, SEM-10, SEM-05-sub)
were **not** mechanically rewritten — they carry forward as `TODO(SME)`
markers pending source DDL / Teradata ground truth.

---

## 5. Open SME questions

1. **SEM-05 (sub) — target column order.** Does the physical column order of
   `staging.wrk_target` match the explicit INSERT list
   `(airline_cd, flgt_no, flgt_dt, company_cd, direction_ind,
   operating_airline_cd, operating_flgt_no, operating_sfx_cd)`? If not, the
   `EXCEPT SELECT * FROM staging.wrk_target` positional match will mismatch.
   Supply the target `CREATE TABLE` DDL to confirm.
2. **SEM-02 / FN-LATEST — latest-value trick key width.** Is `effective_dt` a
   `DATE` or `TIMESTAMP`, and are the concatenated values fixed-width? If not,
   `MAX(effective_dt || val)` can pick the wrong row. Confirm to apply the
   safe form `TO_CHAR(effective_dt,'YYYY-MM-DD') || LPAD(val::VARCHAR,n,' ')`.
3. **SEM-06 / DTXX-10 — `param_value` cast.** What is the string format of
   `synthetic_sys_param.param_value` for `param_id = 'UPDATE_CUTOFF'`? Should
   the comparison be `src.flgt_dt > TO_DATE(param_value,'YYYY-MM-DD')`?
4. **SEM-03 — `CHAR(n)` padding.** Are any of the join/`EXCEPT` keys
   (`airline_cd`, `flgt_no`, `company_cd`, `*_stn_cd`, `operating_*`) declared
   `CHAR(n)`? If so, wrap both sides of each predicate in `RTRIM`/`TRIM` to
   preserve Teradata blank-padding semantics.
5. **SEM-04 — timezone.** Are `flgt_dt` / `gmt_flgt_dt` / `effective_dt`
   `TIMESTAMP_TZ`, `TIMESTAMP_NTZ`, or `DATE`? Pin the session `TIMEZONE` or
   pick NTZ/TZ to match the source.
6. **SEM-10 — join-key direction.** Do the three branches correctly join
   `synthetic_flgt_source` to the marketing / operational / codeshare leg
   tables on the keys shown? Confirm against Teradata ground truth when
   supplied.

---

## 6. Inline anchors

```anchors
INSERT INTO staging.wrk_target :: SEM-05 SET-table dedup: 3 independent INSERT…EXCEPT statements replace the single INSERT…UNION…UNION (reviewer-confirmed SET)
EXCEPT :: SEM-05: EXCEPT SELECT * FROM staging.wrk_target reproduces Teradata SET "drop rows already present" per branch
SUBSTR(MAX(src.effective_dt || leg.company_cd), 11, 99) :: SEM-02/FN-LATEST: latest-value trick needs a fixed-width sortable key (TO_CHAR(effective_dt,'YYYY-MM-DD') || LPAD(val,n,' '))
SUBSTR(MAX(src.effective_dt || leg.operating_airline_cd), 11, 3) :: SEM-03: width 3 vs 99 elsewhere — confirm declared width of operating_airline_cd
synthetic_mkg_flgt_leg :: SEM-10: join-key direction (marketing) — confirm against Teradata ground truth
synthetic_operational_flgt_leg :: SEM-10: join-key direction (operational) — confirm against Teradata ground truth
synthetic_codeshare_flgt_leg cs :: SEM-10: join-key direction (codeshare) — confirm against Teradata ground truth
SELECT param_value :: SEM-06/DTX-10: implicit string→date cast — consider TO_DATE(param_value,'YYYY-MM-DD')
src.flgt_dt > ( :: SEM-06/DTX-10: param_value implicit cast feeds this cutoff comparison
```