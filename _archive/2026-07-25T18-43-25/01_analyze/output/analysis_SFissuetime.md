# Stage 1 — Analysis: `SFissuetime.sql`

**Input:** `00_input/SFissuetime.sql` (139 lines)
**Teradata ground truth:** none — no `SFissuetime.teradata.sql` in `00_input/`.
Semantic intent is therefore inferred from sibling columns / naming conventions
and every inference is flagged `TODO(SME)`.
**Archive step:** `01_analyze/output/` was empty for this unit; no prior
artifacts to archive (`python3 05_report/archive_outputs.py SFissuetime` is a
no-op here).

---

## 1. Column-count check (INSERT target vs SELECT expressions)

| Side | Count | Duplicates | Net |
|---|---|---|---|
| INSERT target columns (lines 3–62) | 60 | none | 60 |
| SELECT expressions (lines 65–131) | 60 | none | 60 |

**Result: 60 = 60 — counts match. No DEF-05 (count mismatch).**

Counting notes:
- The `TO_TIMESTAMP_LTZ( CONCAT(...) , '...' )` block (lines 106–109) is **one**
  expression aliased `AS new_sched_departure_date`.
- The `CASE WHEN ... END` block (lines 127–131) is **one** expression aliased
  `AS change_ind` (the last SELECT item, position 60).

### Positional alignment audit (critical)

INSERT…SELECT is **positional**, so the alias name is cosmetic — the expression
lands in whatever target slot its ordinal position dictates. The one constructed
expression is mis-aliased:

| Pos | INSERT target (line) | SELECT expression (line) | Aligned? |
|---|---|---|---|
| 35 | `new_sched_departure_date` (37) | `n.sched_departure_date` (99) | ✅ |
| 41 | `new_sched_arrival_date` (43) | `n.sched_arrival_date` (105) | ✅ |
| **42** | **`new_sched_departure_time`** (44) | **`TO_TIMESTAMP_LTZ(...) AS new_sched_departure_date`** (106–109) | ⚠️ alias lies |
| 43 | `new_sched_arrival_time` (45) | `n.sched_arrival_time` (110) | ✅ |
| 60 | `change_ind` (62) | `CASE ... END AS change_ind` (127–131) | ✅ |

The expression at SELECT position 42 is aliased `new_sched_departure_date`, but
position 42 of the INSERT list is `new_sched_departure_time`. The alias name
matches INSERT position 35 (`new_sched_departure_date`), which is already
populated by `n.sched_departure_date` (line 99).

**Interpretation:** The expression
`TO_TIMESTAMP_LTZ(CONCAT(TO_DATE(o.sched_departure_date), ' ', n.sched_departure_time), 'YYYY-MM-DD HH24:MI:SS.FF9')`
combines a **date** and a **time** into a **timestamp**. Logically this is a
"departure **time** (as a timestamp)" value, which belongs in
`new_sched_departure_time` (pos 42) — **not** in `new_sched_departure_date`
(pos 35, already a plain date). The positional placement is therefore correct;
only the **alias is a copy-paste error** (DEF-06). This is the most likely
reading, but with no Teradata ground truth the intent cannot be proven — see
SME-Q1.

---

## 2. Syntax errors / residual-Teradata constructs

The file is **clean Snowflake** — it parses and resolves without any SFX/FNX/DTX
fix. No residual Teradata constructs found.

| # | Line(s) | Construct | Rule | Verdict |
|---|---|---|---|---|
| — | — | (none) | — | No `ZEROIFNULL`/`NULLIFZERO`, no `CONTAINS`/`OVERLAPS`, no `SEL`, no `SET`/`MULTISET`, no `PRIMARY INDEX`, no `COLLECT STATS`, no BTEQ, no `LOCKING`, no `(+)`, no `MINUS`, no `TOP`, no `CAST ... FORMAT`. |

Valid Snowflake constructs present (confirmed legal):
- `TO_TIMESTAMP_LTZ(...)` (line 106) — native Snowflake function.
- `TO_DATE(...)` (line 107) — native.
- `CONCAT(...)` (line 107) — native.
- `FULL OUTER JOIN ... ON` (lines 132–139) — ANSI join, valid.
- `CASE WHEN ... IS NULL ...` (lines 127–131) — valid.

**No syntax fixes required.**

---

## 3. Defects (DEF-*)

| # | Line(s) | Defect | Rule | Class | Notes |
|---|---|---|---|---|---|
| D1 | 106–109 | Alias `AS new_sched_departure_date` does not match the INSERT target at its position (`new_sched_departure_time`, line 44). | DEF-06 (alias ≠ target — **not a defect**) | **AUTO** | INSERT…SELECT is positional; the alias is cosmetic. Normalize the alias to `AS new_sched_departure_time` for readability so a reader is not misled into thinking this populates `new_sched_departure_date`. No data change. |

No DEF-01 (duplicate column), DEF-02 (whitespace typo), DEF-03 (unbalanced
parens — the `TO_TIMESTAMP_LTZ`/`CONCAT` nesting is balanced), DEF-04
(malformed call), DEF-05 (count mismatch — counts are equal), or DEF-07
(wrong column ref — cannot disprove without ground truth; see SME-Q2).

---

## 4. Semantic risks (SEM-*)

| # | Line(s) | Risk | Rule | Present? | Class | Detail |
|---|---|---|---|---|---|---|
| S1 | 106–109 | `TO_TIMESTAMP_LTZ` returns a timestamp **with local session time zone**. The sibling "old" columns are `old_gmt_sched_departure_time` / `old_gmt_sched_arrival_time` (GMT/UTC), and the "new" side has both `new_sched_departure_time` (this slot) and `new_gmt_sched_departure_time` (pos 44, line 111). Using **LTZ** for the local-time slot is plausibly intended, but the session `TIMEZONE` must be pinned or the stored value drifts. | SEM-04 | Yes | **SME** | Confirm the target column `new_sched_departure_time` is meant to hold a **local-time** timestamp (LTZ) and not NTZ/TZ. Pin session `TIMEZONE`. No ground truth → `TODO(SME)`. |
| S2 | 107 | `CONCAT(TO_DATE(o.sched_departure_date), ' ', n.sched_departure_time)` performs **implicit casts**: `TO_DATE(...)` → string for CONCAT, and `n.sched_departure_time` (likely TIME) → string. If `o.sched_departure_date` is already a DATE, `TO_DATE` is a harmless no-op; if it is a string, `TO_DATE` with no format relies on session defaults. | SEM-06 | Yes | **SME** | Make casts explicit (`TO_CHAR(TO_DATE(...),'YYYY-MM-DD')`) to remove default-format dependence. Confirm source column types. `TODO(SME)`. |
| S3 | 106–109 | Format mask `'YYYY-MM-DD HH24:MI:SS.FF9'` expects 9-digit fractional seconds (`FF9`). If `n.sched_departure_time` carries no fractional seconds, Snowflake parses leniently, but if it carries a different precision the value may truncate/pad. | SEM-06 | Yes | **SME** | Confirm the precision of `n.sched_departure_time` matches `FF9`, or relax the mask. `TODO(SME)`. |
| S4 | 127–131 | `change_ind` CASE uses `IS NULL` (not empty-string) — correct for NULL detection. | SEM-08 | No | — | `IS NULL` is the right test; no empty-string-vs-NULL hazard. The A/E/U logic (o NULL→'A' add, n NULL→'E' expire, else 'U' update) is a standard SCD-2 diff pattern. |
| S5 | 132–139 | FULL OUTER JOIN keys include `n.act_departure_station = o.departure_station` and `n.act_arrival_station = o.arrival_station`. The "new" side uses `act_*_station` (actual) while the "old" side uses `departure_station`/`arrival_station` (which maps to `old_departure_station`/`old_arrival_station`). Whether `o.departure_station` is the **scheduled** or **actual** station on the old side is not provable without DDL/ground truth. | SEM-10 (join direction / alias) | Yes | **SME** | Confirm the station columns are semantically the same grain on both sides (actual-vs-actual). A scheduled-vs-actual mismatch would silently change the join. `TODO(SME)`. |
| S6 | — | SET-table dedup (multiple INSERTs / UNION into one target). | SEM-05 | No | — | Single `INSERT … SELECT` with a `FULL OUTER JOIN` (no `UNION`/`UNION ALL`, no second INSERT). No SET-table signal. No DDL supplied, but none needed — SEM-05 is not triggered. |
| S7 | — | Integer division. | SEM-01 | No | — | No `/` division in the script. |
| S8 | — | `QUALIFY` / dedup ties. | SEM-02 | No | — | No `QUALIFY` or `ROW_NUMBER`. |
| S9 | — | `CHAR(n)` padding. | SEM-03 | No | — | No `CHAR(n)` comparisons visible (no DDL). |
| S10 | — | `NULL` ordering feeding `QUALIFY`/`TOP`. | SEM-07 | No | — | No `ORDER BY` / `QUALIFY`. |
| S11 | — | Aggregate of empty set. | SEM-09 | No | — | No aggregates. |

---

## 5. Classification summary

| ID | Finding | Rule | Class |
|---|---|---|---|
| D1 | Misleading alias `AS new_sched_departure_date` → normalize to `AS new_sched_departure_time` | DEF-06 | **AUTO** |
| S1 | `TO_TIMESTAMP_LTZ` timezone intent (LTZ vs NTZ/TZ); pin session `TIMEZONE` | SEM-04 | **SME** |
| S2 | Implicit casts in `CONCAT`/`TO_DATE` (make explicit) | SEM-06 | **SME** |
| S3 | `FF9` format precision vs `n.sched_departure_time` precision | SEM-06 | **SME** |
| S5 | Join key `act_*_station` vs `departure_station`/`arrival_station` semantic grain | SEM-10 | **SME** |

**AUTO:** 1 (cosmetic alias normalize).
**FIX:** 0 (no mechanical defect repair beyond the AUTO alias).
**SME:** 4 (all semantic-intent questions; no ground truth available).

---

## 6. Table dependency inventory

| Role | Table | Alias | Lines |
|---|---|---|---|
| Target (INSERT) | `staging.wrk_synthetic_flgt_leg_ins_exp` | — | 1 |
| Source (old side) | `staging.wrk_synthetic_flgt_source1` | `o` | 132 |
| Source (new side) | `staging.wrk_synthetic_flgt_source2` | `n` | 133 |

Join: `o` FULL OUTER JOIN `n` on airline code, flight no, suffix, scheduled
departure date, and departure/arrival stations (lines 134–139).

---

## 7. Open SME questions (for Stage 3 / Stage 6)

- **SME-Q1 (S1, SEM-04):** Is `new_sched_departure_time` intended to store a
  **local-time** timestamp (`TIMESTAMP_LTZ`)? Should the session `TIMEZONE` be
  pinned? (No ground truth.)
- **SME-Q2 (S2, SEM-06):** What are the source types of
  `o.sched_departure_date` and `n.sched_departure_time`? Should the casts in
  `CONCAT`/`TO_DATE` be made explicit to avoid session-default formatting?
- **SME-Q3 (S3, SEM-06):** Does `n.sched_departure_time` carry 9-digit
  fractional seconds, or should the `FF9` mask be relaxed?
- **SME-Q4 (S5, SEM-10):** Are `n.act_departure_station`/`n.act_arrival_station`
  semantically the same (actual) grain as `o.departure_station`/
  `o.arrival_station`? A scheduled-vs-actual mismatch would change the join.
- **SME-Q5 (D1, DEF-06):** Confirm the `TO_TIMESTAMP_LTZ(...)` expression is
  positionally correct in slot 42 (`new_sched_departure_time`) and only the
  **alias** is wrong (not the position). The logical shape (date + time →
  timestamp) supports this, but without ground truth it is an inference.

---

## 8. Verdict

**PARSE-CLEAN, count-balanced (60=60); 1 cosmetic alias defect (AUTO) + 4
semantic SME questions (timezone, implicit casts, format precision, join-key
grain) — no syntax fix needed.**