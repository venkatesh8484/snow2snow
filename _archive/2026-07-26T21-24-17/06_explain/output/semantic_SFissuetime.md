# Semantic explanation — `SFissuetime`

**Fixed SQL:** `03_fix/output/SFissuetime_fixed.sql`
**Analysis:** `01_analyze/output/analysis_SFissuetime.md`
**Teradata ground truth:** none supplied (no `00_input/SFissuetime.teradata.sql`).
Every semantic inference below is therefore flagged `TODO(SME)`.

---

## 1. Purpose

This statement is a single `INSERT … SELECT` that builds a before/after
("old vs. new") flight-leg comparison table. It reads two staging sources —
`staging.wrk_synthetic_flgt_source1` (alias `o`, the **old** leg snapshot) and
`staging.wrk_synthetic_flgt_source2` (alias `n`, the **new** leg snapshot) —
joins them on the flight-leg identity keys (airline code, flight number, suffix
code, scheduled departure date, departure station, arrival station) using a
**FULL OUTER JOIN**, and writes 60 columns into the target
`staging.wrk_synthetic_flgt_leg_ins_exp`.

The grain of one output row is **one flight-leg identity, old-or-new**: a row
appears when the leg exists on either side. The first 29 columns carry the
**old** snapshot (`old_*`), the next 30 carry the **new** snapshot (`new_*` /
`marketing_*`), and the final column `change_ind` encodes whether the leg was
**A**dded (old side NULL), **E**xpired/removed (new side NULL), or **U**pdated
(both sides present). This is the classic add/edit/update ("A/E/U") change-data
pattern produced by a full-outer-join diff.

---

## 2. Clause-by-clause walk-through

### 2.1 `INSERT INTO staging.wrk_synthetic_flgt_leg_ins_exp ( … 60 columns … )`

The target column list is explicit and 60 names long. Binding to the `SELECT`
is **positional** (by ordinal slot), not by alias — so a wrong alias is
cosmetic, not a runtime error. The list is split into three logical bands:

- **Positions 1–29 (`old_*`):** the old snapshot, sourced from alias `o`.
- **Positions 30–59 (`new_*` / `marketing_*` / `itinerary_variation_id`):** the
  new snapshot, sourced from alias `n`, plus one computed timestamp at
  position 42.
- **Position 60 (`change_ind`):** the computed A/E/U flag.

### 2.2 `SELECT` list (positions 1–41, 43–59)

Positions 1–29 are plain `o.<col>` references carrying the old snapshot through
verbatim (airline code, flight number, suffix, scheduled/GMT dates and times,
accounting year/month/week, local flight date, aircraft types, station codes,
UTC variation text, leg sequence, effective/expiry dates, opg flgt leg id,
current-rec indicator, sched source type).

Positions 30–41 and 43–59 carry the new snapshot from `n`: `n.sequence`,
`n.operating_airline_cd`, `n.operating_flgt_no`, `n.operating_sfx_cd`,
`n.sched_departure_date`, `n.gmt_flgt_dt`, `n.itinerary_variation_id`,
`n.act_departure_station`, `n.act_arrival_station`, `n.service_typ`,
`n.sched_arrival_date`, then (skipping the computed slot 42) `n.sched_arrival_time`,
`n.gmt_sched_departure_time`, `n.gmt_sched_arrival_time`, `n.marketing_airline_cd`,
`n.marketing_flgt_no`, `n.iata_ac_typ`, `n.pax_departure_timel_cd`,
`n.pax_arrival_timel_cd`, `n.leg_sequence`, `n.effective_dt`, `n.expiry_dt`,
`n.current_rec_ind`, `n.carrier_ac_typ`, `n.dep_utc_variation_txt`,
`n.arr_utc_variation_txt`, `n.codeshare_ind`, `n.sched_src_typ`.

### 2.3 Position 42 — computed `new_sched_departure_time` (the only expression)

```sql
TO_TIMESTAMP_LTZ(
    CONCAT(TO_DATE(o.sched_departure_date), ' ', n.sched_departure_time),
    'YYYY-MM-DD HH24:MI:SS.FF9'
) AS new_sched_departure_time
```

This is the only non-trivial expression in the `SELECT`. It reconstructs a
**local timestamp** for the new leg's scheduled departure by concatenating the
**old** leg's scheduled departure *date* (`o.sched_departure_date`) with the
**new** leg's scheduled departure *time* (`n.sched_departure_time`), then parsing
the resulting string with `TO_TIMESTAMP_LTZ` using a `YYYY-MM-DD HH24:MI:SS.FF9`
mask. The use of `o.` for the date and `n.` for the time is intentional: the
date is treated as stable across the change while only the time is being
updated. `TO_TIMESTAMP_LTZ` returns a timestamp **with local session timezone**,
which is the sibling of the GMT timestamp stored at position 44
(`new_gmt_sched_departure_time`).

**Buggy input behavior:** the alias on this expression was
`AS new_sched_departure_date`, which does not match the INSERT target at slot 42
(`new_sched_departure_time`). Because binding is positional this did not break
execution, but the alias was misleading. The fix (DEF-06) normalized the alias
to `new_sched_departure_time`; the expression and its slot are unchanged.

### 2.4 Position 60 — `change_ind` CASE

```sql
CASE
    WHEN o.operating_airline_cd IS NULL THEN 'A'
    WHEN n.operating_airline_cd IS NULL THEN 'E'
    ELSE 'U'
END AS change_ind
```

This encodes the A/E/U change flag using the NULL semantics of the FULL OUTER
JOIN:

- `o.operating_airline_cd IS NULL` → the leg exists only on the new side → **A**dd.
- `n.operating_airline_cd IS NULL` → the leg exists only on the old side → **E**xpire/remove.
- both present → **U**pdate.

`operating_airline_cd` is used as the existence probe because it is a non-null
identity column on each source. The only semantic risk is the `''` (empty
string) vs `NULL` distinction (SEM-08): if a source can store `''` rather than
`NULL`, the `IS NULL` test would not fire and the branch would be wrong.

### 2.5 `FROM … FULL OUTER JOIN … ON`

```sql
FROM   staging.wrk_synthetic_flgt_source1 o
FULL OUTER JOIN staging.wrk_synthetic_flgt_source2 n
       ON n.operating_airline_cd = o.operating_airline_cd
      AND n.operating_flgt_no    = o.operating_flgt_no
      AND n.operating_sfx_cd     = o.operating_sfx_cd
      AND n.sched_departure_date  = o.sched_departure_date
      AND n.act_departure_station = o.departure_station
      AND n.act_arrival_station   = o.arrival_station;
```

A FULL OUTER JOIN over six identity keys. The first four keys
(airline code, flight number, suffix code, scheduled departure date) are
symmetric old↔new. The last two keys are **asymmetrically named**:
`n.act_departure_station = o.departure_station` and
`n.act_arrival_station = o.arrival_station` — the new side uses `act_*`
("actual") names while the old side uses the bare station names. This is the
SEM-10 join-key grain risk: without DDL or ground truth we cannot prove
`act_departure_station` and `departure_station` are the same grain (scheduled
vs. actual station). The join is left unchanged; the risk is flagged for SME.

---

## 3. Semantic checks table

| SEM ID | Risk | Present? | Corrected how? | Equivalent to Teradata? |
|---|---|---|---|---|
| SEM-01 | Integer division | No | n/a — no `/` in the script | n/a |
| SEM-02 | `QUALIFY` / dedup ordering | No | n/a — no `QUALIFY`/`ROW_NUMBER` | n/a |
| SEM-03 | `CHAR(n)` padding & comparison | Possible (join keys) | Not mechanically changed — no DDL to confirm types. Flagged `TODO(SME)`: if any join key (`operating_airline_cd`, `operating_sfx_cd`, `service_typ`, `*_cd`, `*_typ`) is `CHAR(n)`, Teradata blank-pads and ignores trailing spaces in `=`; Snowflake does not pad, so `'AA' <> 'AA '`. `TRIM`/`RTRIM` may be required. | SME |
| SEM-04 | Timestamp / timezone | Yes (pos 42) | Not mechanically changed. `TO_TIMESTAMP_LTZ` introduces a session-`TIMEZONE` dependency; the stored LTZ value shifts with the session timezone unless pinned. The target has a GMT sibling at pos 44 (`new_gmt_sched_departure_time`), so the LTZ slot is plausibly the *local* time. Flagged `TODO(SME)`: confirm intent and whether to pin session `TIMEZONE` or use `TIMESTAMP_NTZ`/`TIMESTAMP_TZ` explicitly. | SME |
| SEM-05 | SET-table dedup | No | n/a — single `INSERT`, no `UNION`/`UNION ALL` into one target. SET/MULTISET cannot be inferred from an INSERT-only script. | n/a |
| SEM-06 | Implicit cast / NULL in comparison | Yes (pos 42) | Not mechanically changed. `CONCAT(TO_DATE(o.sched_departure_date), ' ', n.sched_departure_time)` relies on implicit date→string and time→string casts whose format depends on session defaults; the `'YYYY-MM-DD HH24:MI:SS.FF9'` parse mask assumes a specific string shape. Flagged `TODO(SME)`: prefer explicit `TO_CHAR(TO_DATE(o.sched_departure_date),'YYYY-MM-DD')` and an explicit time-to-char; confirm the `FF9` mask matches source `sched_departure_time` precision (nanoseconds vs seconds). | SME |
| SEM-07 | `NULL` ordering feeding `QUALIFY`/`TOP` | No | n/a — no `ORDER BY` feeding a `QUALIFY`/`TOP` | n/a |
| SEM-08 | Empty string vs NULL | Yes (pos 60, low) | Not mechanically changed. The `change_ind` CASE uses `IS NULL` on `operating_airline_cd` as the existence probe. Flagged `TODO(SME)`: confirm `operating_airline_cd` cannot be an empty string `''` (which is not NULL in Snowflake and would change the branch). | SME |
| SEM-09 | Aggregate of empty set / `SUM` NULL | No | n/a — no aggregates | n/a |
| SEM-10 | Exchange-rate / lookup join direction | Yes (join ON) | Not mechanically changed. `n.act_departure_station = o.departure_station` and `n.act_arrival_station = o.arrival_station` mix `act_*` (actual) names on the new side with non-`act_` names on the old side. Flagged `TODO(SME)`: confirm same grain (scheduled vs actual). Join left unchanged. | SME |

---

## 4. Divergences from the original

Only one mechanical change was made; everything else is flagged, not rewritten.

- **DEF-06 alias normalization (pos 42):** the buggy input aliased the computed
  timestamp expression as `AS new_sched_departure_date`; the fix renames the
  alias to `AS new_sched_departure_time` to match the INSERT target column at
  that slot. Because INSERT…SELECT binds positionally, this is **cosmetic only**
  — the expression stays in slot 42 and runtime behavior is identical. This is
  the only intentional divergence from the buggy input.
- **No other mechanical changes.** All five SEM-* risks (SEM-03, SEM-04,
  SEM-06, SEM-08, SEM-10) are flagged as `TODO(SME)` and left for human
  confirmation; no rewrite was applied without ground truth.
- **No Teradata ground truth** was supplied, so there is no bit-identical
  equivalence claim. Equivalence is *inferred* from sibling-column naming
  (`new_gmt_sched_departure_time` as the GMT sibling of the LTZ slot) and the
  standard A/E/U full-outer-join pattern; every such inference is flagged.

---

## 5. Open SME questions

Each is a decision for a human reviewer (DDL or business knowledge required):

1. **SEM-04 — timezone intent (pos 42):** Is the `TO_TIMESTAMP_LTZ` slot intended
   to store *local* time, with `new_gmt_sched_departure_time` (pos 44) as its GMT
   sibling? Should the session `TIMEZONE` be pinned (e.g. `ALTER SESSION SET
   TIMEZONE = '…'`) before this INSERT, or should the expression use
   `TIMESTAMP_NTZ`/`TIMESTAMP_TZ` explicitly to remove the session dependency?

2. **SEM-06 — implicit casts & precision (pos 42):** Should the date+time
   concatenation use explicit `TO_CHAR(TO_DATE(o.sched_departure_date),
   'YYYY-MM-DD')` and an explicit time-to-char cast instead of relying on
   implicit date/time→string casts? Does the `FF9` (nanosecond) parse mask match
   the actual precision of `n.sched_departure_time`, or should it be `FF6`/`FF3`/
   seconds?

3. **SEM-10 — join-key grain (join ON):** Are `n.act_departure_station` /
   `n.act_arrival_station` the same grain as `o.departure_station` /
   `o.arrival_station` (i.e. scheduled station on both sides, despite the
   `act_` naming on the new side)? If they are different grains (actual vs.
   scheduled), the join is wrong and must be re-keyed.

4. **SEM-08 — empty string vs NULL (pos 60):** Can `operating_airline_cd` ever be
   an empty string `''` rather than `NULL` on either source? If yes, the
   `IS NULL` probe in the `change_ind` CASE will not fire for those rows and the
   A/E/U classification will be wrong; a `NULLIF(operating_airline_cd,'')` guard
   would be needed.

5. **SEM-03 — CHAR(n) padding (join keys):** Are any of the join keys
   (`operating_airline_cd`, `operating_sfx_cd`, `service_typ`, and any other
   `*_cd`/`*_typ` columns) declared `CHAR(n)` rather than `VARCHAR`? If yes,
   Teradata blank-pads and ignores trailing spaces in `=`, while Snowflake does
   not pad — `TRIM`/`RTRIM` on both sides of each `CHAR(n)` key is required to
   preserve the original join semantics.

---

## 6. Inline anchors

```anchors
TO_TIMESTAMP_LTZ( :: SEM-04 ▸ TO_TIMESTAMP_LTZ introduces a session-TIMEZONE dependency; confirm this slot is local time (GMT sibling at pos 44) and whether to pin session TIMEZONE or use TIMESTAMP_NTZ/TZ explicitly.
CONCAT(TO_DATE(o.sched_departure_date), ' ', n.sched_departure_time) :: SEM-06 ▸ CONCAT relies on implicit date/time→string casts; prefer explicit TO_CHAR and confirm the FF9 mask matches source sched_departure_time precision.
AS new_sched_departure_time :: DEF-06 ▸ alias normalized from new_sched_departure_date to match the INSERT target at slot 42 (positional binding; expression unchanged).
CASE :: SEM-08 ▸ change_ind CASE probes operating_airline_cd IS NULL; confirm operating_airline_cd cannot be '' (empty string is not NULL in Snowflake and would change the branch).
WHEN o.operating_airline_cd IS NULL THEN 'A' :: A = leg exists only on the new side (add).
WHEN n.operating_airline_cd IS NULL THEN 'E' :: E = leg exists only on the old side (expire/remove).
ELSE 'U' :: U = leg exists on both sides (update).
FULL OUTER JOIN staging.wrk_synthetic_flgt_source2 n :: SEM-10 ▸ FULL OUTER JOIN over six identity keys; act_* station names on the new side vs bare station names on the old side — confirm same grain (scheduled vs actual).
n.act_departure_station = o.departure_station :: SEM-10 ▸ asymmetric join key: new-side act_departure_station vs old-side departure_station; confirm same grain.
n.act_arrival_station = o.arrival_station :: SEM-10 ▸ asymmetric join key: new-side act_arrival_station vs old-side arrival_station; confirm same grain.
n.operating_airline_cd = o.operating_airline_cd :: SEM-03 ▸ if this or any join key is CHAR(n), Teradata blank-pads and ignores trailing spaces; Snowflake does not — TRIM/RTRIM may be required.
```