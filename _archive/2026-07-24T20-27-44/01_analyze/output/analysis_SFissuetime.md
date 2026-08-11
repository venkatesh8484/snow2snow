# Stage 1 — Analysis: `SFissuetime.sql`

**Input:** `00_input/SFissuetime.sql`
**Teradata ground truth:** none supplied (no `SFissuetime.teradata.sql`).
**Statement count:** 1 (single `INSERT … SELECT`).
**Target:** `staging.wrk_synthetic_flgt_leg_ins_exp`
**Sources:** `staging.wrk_synthetic_flgt_source1 o`, `staging.wrk_synthetic_flgt_source2 n` (joined `FULL OUTER JOIN`).

---

## 1. Column-count check

| Side | Count | Notes |
|---|---|---|
| INSERT target columns | 60 | No duplicates detected in the INSERT list. |
| SELECT expressions | 60 | One expression (`TO_TIMESTAMP_LTZ(...) AS new_sched_departure_date`, lines 106–109) spans multiple physical lines but is a single expression. |
| Net (after de-dup) | 60 = 60 | Counts align. |

**Position-by-position alignment** (INSERT col → SELECT expr), key positions:

| # | INSERT column | SELECT expr (line) | Match? |
|---|---|---|---|
| 1 | `old_operating_airline_cd` | `o.operating_airline_cd` (65) | ✓ |
| 30 | `old_sched_src_typ` | `o.sched_src_typ` (94) | ✓ |
| 31 | `new_sequence` | `n.sequence` (95) | ✓ (name differs, positional OK — DEF-06) |
| 35 | `new_sched_departure_date` | `TO_TIMESTAMP_LTZ(CONCAT(TO_DATE(o.sched_departure_date),' ',n.sched_departure_time),'YYYY-MM-DD HH24:MI:SS.FF9')` (106–109) | ⚠ **Type mismatch — see DTX-04 / SEM-04 below** |
| 36 | `new_gmt_flgt_dt` | `n.gmt_flgt_dt` (100) | ✓ |
| 42 | `new_sched_departure_time` | `n.sched_arrival_time` (110) | ⚠ **Likely wrong source — see DEF-07 / SEM-10** |
| 60 | `change_ind` | `CASE … END AS change_ind` (124–131) | ✓ |

**Counts match (60 = 60). No DEF-05 count mismatch.** However, two positional slots carry semantic/defect concerns flagged below.

---

## 2. Syntax errors / residual-Teradata constructs (SFX-* / FNX-* / DTX-*)

| # | Line(s) | Construct | Why invalid / risk | Rule | Class |
|---|---|---|---|---|---|
| S1 | 106–109 | `TO_TIMESTAMP_LTZ(CONCAT(TO_DATE(o.sched_departure_date), ' ', n.sched_departure_time), 'YYYY-MM-DD HH24:MI:SS.FF9')` | `TO_TIMESTAMP_LTZ` is a valid Snowflake function, **but** the target column is `new_sched_departure_date` (position 35), whose sibling `old_sched_departure_date` (position 4) is fed a plain `o.sched_departure_date` (a DATE). The new side produces a `TIMESTAMP_LTZ` while the old side produces a DATE, and the target column is named `…_date`. This is a **type drift** (DTX-04 / SEM-04), not a parse error. The expression itself parses. | DTX-04, SEM-04 | SME |
| S2 | 106 | `TO_DATE(o.sched_departure_date)` | `TO_DATE(<date>)` is legal but redundant when the input is already a DATE; if `o.sched_departure_date` is a string it is fine. No rule violation — informational. | — | AUTO (no-op) |

**No residual Teradata constructs found.** Specifically absent: `ZEROIFNULL`, `NULLIFZERO`, `CONTAINS`, `OVERLAPS`, `SEL`, `SET`/`MULTISET`, `PRIMARY INDEX`, `COLLECT STATS`, BTEQ dot-commands, `(+)` joins, `MINUS`, `TOP n`, `FORMAT` casts, `INDEX`, `OREPLACE`, `OTRANSLATE`, `STRTOK`, `**`, `MOD`. The file is clean Teradata-dialect-wise.

---

## 3. Defects (DEF-*)

| # | Line(s) | Defect | Rule | Class |
|---|---|---|---|---|
| D1 | 110 | **Wrong source column for `new_sched_departure_time`.** INSERT position 42 is `new_sched_departure_time`, but the SELECT feeds it `n.sched_arrival_time` (line 110). The very next INSERT column (43, `new_sched_arrival_time`) is also fed `n.sched_arrival_time`-style data — actually position 43 = `new_sched_arrival_time` ← `n.gmt_sched_departure_time` (line 111)? Recheck: line 110 = `n.sched_arrival_time`, line 111 = `n.gmt_sched_departure_time`. So position 42 (`new_sched_departure_time`) gets `n.sched_arrival_time` — almost certainly a copy-paste error; it should be `n.sched_departure_time`. Without a Teradata ground truth this is an inference → flag SME. | DEF-07 | SME |
| D2 | 106–109 | `AS new_sched_departure_date` alias has correct spacing (no `ASalias` typo). No DEF-02 here. | — | — |
| D3 | — | No duplicate INSERT columns (DEF-01): all 60 names unique. | — | — |
| D4 | — | No unbalanced parentheses (DEF-03): the `TO_TIMESTAMP_LTZ(...)` and `CASE…END` are balanced. | — | — |
| D5 | — | No malformed function calls (DEF-04). | — | — |
| D6 | — | No INSERT/SELECT count mismatch (DEF-05): 60 = 60. | — | — |

**Only one real defect candidate: D1 (position 42 wrong source column).** It requires SME confirmation because no Teradata original is available to disprove the reference (per DEF-07: "Only fix if the Teradata original disproves the reference; otherwise flag → SME").

---

## 4. Semantic risks (SEM-*)

| # | Line(s) | Risk | Present? | Detail | Rule | Class |
|---|---|---|---|---|---|---|
| M1 | 106–109 | **Timestamp / timezone (TIMESTAMP_LTZ vs DATE).** The `new_sched_departure_date` slot receives a `TIMESTAMP_LTZ` while the `old_sched_departure_date` slot receives a plain DATE. If the target column is declared `DATE`, Snowflake will implicitly cast TIMESTAMP→DATE (dropping the time + shifting by session TZ), which is almost certainly **not** the intent. If the target is `TIMESTAMP*`, the old side is being widened. Either way the two sides are asymmetric and the session `TIMEZONE` affects the LTZ value. No DDL is supplied, so this cannot be resolved here. | SEM-04, DTX-04 | SME |
| M2 | 110 | **Wrong-column / join-direction risk.** `new_sched_departure_time` ← `n.sched_arrival_time` looks like a copy-paste from the arrival slot. Semantic correctness of the "new schedule departure time" depends on the true source column. | SEM-10, DEF-07 | SME |
| M3 | 124–131 | **`change_ind` CASE logic on FULL OUTER JOIN.** `WHEN o.operating_airline_cd IS NULL THEN 'A'` (added), `WHEN n.operating_airline_cd IS NULL THEN 'E'` (expired/removed), `ELSE 'U'` (updated). This is a standard SCD-style change flag and is internally consistent. No semantic risk by itself, but the join keys (lines 134–139) include `n.sched_departure_date = o.sched_departure_date` — if `sched_departure_date` is a DATE on one side and a TIMESTAMP on the other (see M1), the join key comparison may silently mismatch (SEM-03/SEM-06). | SEM-06 | SME (linked to M1) |
| M4 | 134–139 | **Join key type alignment.** `n.sched_departure_date = o.sched_departure_date` — if the two source columns differ in type (DATE vs TIMESTAMP/string), Snowflake implicit cast may cause missed matches. Verify both source columns are the same type. | SEM-06 | SME |
| M5 | — | **SET-table dedup (SEM-05).** Single INSERT into `staging.wrk_synthetic_flgt_leg_ins_exp`. No `CREATE TABLE` DDL supplied, no `UNION`/`UNION ALL`, no multiple INSERTs into the same target. **No SET-table signal.** Not applicable. | SEM-05 | N/A |
| M6 | — | **Integer division (SEM-01).** No division present. | SEM-01 | N/A |
| M7 | — | **CHAR padding (SEM-03).** Join keys include string columns (`operating_airline_cd`, `operating_sfx_cd`, `departure_station`, `arrival_station`). If any are `CHAR(n)` (blank-padded in Teradata, not in Snowflake), equality joins may miss matches on trailing-space differences. Cannot confirm without DDL. | SEM-03 | SME |
| M8 | — | **NULL ordering (SEM-07).** No `ORDER BY` / `QUALIFY`/`TOP` present. | SEM-07 | N/A |
| M9 | — | **Empty string vs NULL (SEM-08).** No `NULLIF(x,'')` or empty-string logic present. | SEM-08 | N/A |

---

## 5. Classification summary

| Finding | Rule | Class | Action for Stage 3 |
|---|---|---|---|
| `TO_TIMESTAMP_LTZ(...)` into `new_sched_departure_date` (DATE-named slot) | DTX-04, SEM-04 | SME | Do **not** auto-change. Emit `TODO(SME)`: "Is `new_sched_departure_date` a DATE or TIMESTAMP? Old side feeds a DATE; new side feeds TIMESTAMP_LTZ — confirm intended type and whether session TIMEZONE should be pinned." |
| `new_sched_departure_time` ← `n.sched_arrival_time` (likely copy-paste) | DEF-07, SEM-10 | SME | Do **not** auto-swap (no Teradata ground truth). Emit `TODO(SME)`: "Position 42 (`new_sched_departure_time`) selects `n.sched_arrival_time` — should this be `n.sched_departure_time`?" |
| Join key type alignment (`sched_departure_date` both sides) | SEM-06 | SME | `TODO(SME)`: confirm both source columns are the same type. |
| CHAR-padding risk on string join keys | SEM-03 | SME | `TODO(SME)`: if any join key is `CHAR(n)`, wrap with `RTRIM`. |
| No residual Teradata constructs | SFX/FNX | — | None to fix. |
| No column-count mismatch | DEF-05 | — | None to fix. |
| No duplicate columns | DEF-01 | — | None to fix. |
| No SET-table signal | SEM-05 | N/A | None. |

**No AUTO or FIX items.** Every actionable finding is **SME** — the file parses cleanly on Snowflake; all concerns are semantic/defect-inference and require human confirmation (no Teradata ground truth available).

---

## 6. Table dependency inventory

| Role | Table | Alias | Notes |
|---|---|---|---|
| Target | `staging.wrk_synthetic_flgt_leg_ins_exp` | — | 60-column INSERT target. DDL not supplied. |
| Source (old) | `staging.wrk_synthetic_flgt_source1` | `o` | "Old" snapshot side of the FULL OUTER JOIN. |
| Source (new) | `staging.wrk_synthetic_flgt_source2` | `n` | "New" snapshot side. |

**Join:** `FULL OUTER JOIN` on `operating_airline_cd`, `operating_flgt_no`, `operating_sfx_cd`, `sched_departure_date`, `act_departure_station = departure_station`, `act_arrival_station = arrival_station` (6 keys, lines 134–139).

---

## 7. Verdict

**One statement; parses clean on Snowflake; 60 = 60 columns aligned.** No residual Teradata dialect, no structural defects, no count mismatch. **Two SME-level concerns** dominate:

1. **Type drift (DTX-04 / SEM-04):** the `new_sched_departure_date` slot receives a `TIMESTAMP_LTZ` while its `old_` counterpart receives a plain DATE — asymmetric and session-TZ-sensitive. Needs DDL confirmation.
2. **Likely wrong-column (DEF-07 / SEM-10):** `new_sched_departure_time` is fed `n.sched_arrival_time` — almost certainly a copy-paste defect, but without a Teradata original it must be flagged, not silently swapped.

Stage 3 should make **no SQL change** beyond optionally adding `TODO(SME)` comments; the file already runs. All real work is semantic confirmation in Stage 6.