# Stage 6 — Semantic explanation: `SFissuetime.sql`

**Fixed SQL:** `03_fix/output/SFissuetime_fixed.sql`
**Analysis:** `01_analyze/output/analysis_SFissuetime.md`
**Validation:** `04_validate/output/validation_SFissuetime.md` (PASS — 1 stmt, 60=60 cols, no residual Teradata, 10 TODO(SME))
**Teradata ground truth:** **none supplied** (no `00_input/SFissuetime.teradata.sql`).
Every semantic inference below is flagged `TODO(SME)`; intent is inferred from
`02_rules/` and the Snowflake input alone. No reviewer guidance file exists.

---

## 1. Purpose

`SFissuetime.sql` builds an SCD-2-style "old vs new" comparison table,
`staging.wrk_synthetic_flgt_leg_ins_exp`, by FULL OUTER JOINing two flight-leg
sources — `staging.wrk_synthetic_flgt_source1` (the "old" side, alias `o`) and
`staging.wrk_synthetic_flgt_source2` (the "new" side, alias `n`) — on the
flight identity keys (airline code, flight no, suffix, scheduled departure
date, and departure/arrival stations). For each matched pair it projects 60
columns: 30 "old_*" attributes from `o`, then 29 "new_*" attributes from `n`
(including a derived `new_sched_departure_time` timestamp built by combining
`o.sched_departure_date` with `n.sched_departure_time` via
`TO_TIMESTAMP_LTZ`), and a final `change_ind` flag computed as `'A'` (add —
old side NULL), `'E'` (expire — new side NULL), or `'U'` (update — both
present). The grain of one output row is one flight-leg identity.

---

## 2. Statement-by-statement walk-through

### 2.1 INSERT target list (60 columns, lines 3–62)

The 60-column target list is split into three logical groups:
- **Positions 1–30** (`old_*`): the "old" side attributes, sourced from `o.*`.
- **Positions 31–59** (`new_*` / `marketing_*` / `itinerary_variation_id`):
  the "new" side attributes, sourced from `n.*`, plus one **derived** column
  at position 42.
- **Position 60** (`change_ind`): the SCD-2 diff flag.

### 2.2 SELECT projection (60 expressions)

- **Positions 1–30** are straight `o.<col>` references — the old side carried
  verbatim.
- **Positions 31–41, 43–59** are straight `n.<col>` references — the new side
  carried verbatim.
- **Position 42** is the derived timestamp:
  ```
  TO_TIMESTAMP_LTZ(
      CONCAT(TO_DATE(o.sched_departure_date), ' ', n.sched_departure_time),
      'YYYY-MM-DD HH24:MI:SS.FF9'
  ) AS new_sched_departure_time
  ```
  This combines the **date** from the old side with the **time** from the new
  side into a single `TIMESTAMP_LTZ`. The alias was corrected by the DEF-06
  fix (see §3). The `LTZ` form introduces a session-timezone dependency
  (SEM-04); the `CONCAT` relies on implicit date/time→string casts (SEM-06);
  the `FF9` mask assumes 9-digit fractional seconds (SEM-06).
- **Position 60** is the `change_ind` CASE:
  ```
  CASE
      WHEN o.operating_airline_cd IS NULL THEN 'A'
      WHEN n.operating_airline_cd IS NULL THEN 'E'
      ELSE 'U'
  END AS change_ind
  ```
  Standard SCD-2 diff: `A` = add (old side absent), `E` = expire (new side
  absent), `U` = update (both present). Uses `IS NULL` (not empty-string),
  which is the correct NULL test (SEM-08 — no empty-string hazard, but flagged
  for confirmation that the source does not use `''` as a sentinel).

### 2.3 FROM / FULL OUTER JOIN

```
FROM   staging.wrk_synthetic_flgt_source1 o
FULL OUTER JOIN staging.wrk_synthetic_flgt_source2 n
       ON n.operating_airline_cd = o.operating_airline_cd
      AND n.operating_flgt_no    = o.operating_flgt_no
      AND n.operating_sfx_cd     = o.operating_sfx_cd
      AND n.sched_departure_date = o.sched_departure_date
      AND n.act_departure_station = o.departure_station
      AND n.act_arrival_station   = o.arrival_station
```

The FULL OUTER JOIN preserves rows present on only one side (so adds and
expires are captured). The join keys mix `act_*_station` on the new side with
non-`act_` `departure_station`/`arrival_station` on the old side — a
scheduled-vs-actual grain question (SEM-10).

---

## 3. Semantic checks table

| SEM ID | Risk | Present? | Corrected how? | Equivalent to Teradata? |
|---|---|---|---|---|
| **DEF-06** (alias) | Alias ≠ target name at SELECT pos 42 | **Yes** | Alias normalized `AS new_sched_departure_date` → `AS new_sched_departure_time` to match the INSERT target at position 42. `INSERT…SELECT` is positional, so only the label changed; the `TO_TIMESTAMP_LTZ(...)` expression stays in its slot. Minimal diff = 1 token. | **Yes** — positional binding means no data change; the alias was cosmetic/misleading. |
| SEM-04 | `TO_TIMESTAMP_LTZ` session-TZ | Yes | **Not rewritten.** `TO_TIMESTAMP_LTZ` returns a timestamp with local session time zone; the stored value shifts with the session `TIMEZONE` unless pinned. The sibling `new_gmt_sched_departure_time` (pos 44) is the GMT counterpart, so the LTZ slot is plausibly the *local* time. Flagged `TODO(SME)`. | **SME** — confirm `new_sched_departure_time` is meant to hold a local-time (LTZ) timestamp; pin session `TIMEZONE` or use `TIMESTAMP_NTZ`/`TIMESTAMP_TZ`. |
| SEM-06 / DTX-10 | Implicit casts in `CONCAT`/`TO_DATE` | Yes | **Not rewritten.** `CONCAT(TO_DATE(o.sched_departure_date), ' ', n.sched_departure_time)` relies on implicit date→string and time→string casts whose format depends on session defaults. Safe form: `TO_CHAR(TO_DATE(o.sched_departure_date),'YYYY-MM-DD')` and an explicit time-to-char. Flagged `TODO(SME)`. | **SME** — confirm source types of `o.sched_departure_date` and `n.sched_departure_time`. |
| SEM-06 | `FF9` mask precision | Yes | **Not rewritten.** The `'YYYY-MM-DD HH24:MI:SS.FF9'` mask expects 9-digit fractional seconds. If `n.sched_departure_time` carries a different precision, the value may truncate/pad. Flagged `TODO(SME)`. | **SME** — confirm precision of `n.sched_departure_time` matches `FF9`. |
| SEM-10 | Join-key grain (`act_*` vs non-`act_`) | Yes | **Not rewritten.** `n.act_departure_station = o.departure_station` and `n.act_arrival_station = o.arrival_station` mix an `act_*` (actual) column with a non-`act_` name on the old side. A scheduled-vs-actual mismatch would silently change the join. Flagged `TODO(SME)`. | **SME** — confirm both sides are the same (actual) grain. |
| SEM-08 | Empty string vs NULL | No (but flagged) | The `change_ind` CASE uses `IS NULL` (correct). No `NULLIF(x,'')` present. Flagged `TODO(SME)` only to confirm the source does not use `''` as a sentinel that should be treated as NULL. | **SME** — confirm `IS NULL` is the intended test. |
| SEM-03 | `CHAR(n)` padding | Maybe | **Not rewritten.** Join keys may be `CHAR(n)`; Teradata blank-pads, Snowflake does not. No DDL supplied. Flagged `TODO(SME)`. | **SME** — confirm no `CHAR(n)` comparison drift. |
| SEM-05 | SET-table dedup | No | Single `INSERT … SELECT` with a FULL OUTER JOIN; no `UNION`/second INSERT. SEM-05 not triggered. | n/a |
| SEM-01 | Integer division | No | n/a | n/a |
| SEM-02 | `QUALIFY`/dedup ties | No | n/a | n/a |
| SEM-07 | `NULL` ordering | No | n/a | n/a |
| SEM-09 | Aggregate of empty set | No | n/a | n/a |

---

## 4. Divergences from the original

| # | Divergence | Justification |
|---|---|---|
| 1 | Alias at SELECT position 42: `AS new_sched_departure_date` → `AS new_sched_departure_time`. | DEF-06. The expression is a date+time→timestamp construction that logically populates `new_sched_departure_time` (pos 42), not `new_sched_departure_date` (pos 35, already populated by `n.sched_departure_date`). `INSERT…SELECT` is positional, so the alias is cosmetic — the label change removes a misleading name without moving data. |

No other SQL logic was changed. Column order, JOIN keys, CASE-branch order,
and the `TO_TIMESTAMP_LTZ`/`CONCAT` construction are all preserved exactly.
The five SEM-* risks (SEM-04, SEM-06 ×2, SEM-10, SEM-08, SEM-03) were **not**
mechanically rewritten — they carry forward as `TODO(SME)` markers pending
source DDL / Teradata ground truth.

---

## 5. Open SME questions

1. **SEM-04 — LTZ intent.** Is `new_sched_departure_time` intended to store a
   **local-time** timestamp (`TIMESTAMP_LTZ`)? Should the session `TIMEZONE` be
   pinned, or should this be `TIMESTAMP_NTZ`/`TIMESTAMP_TZ`? (The sibling
   `new_gmt_sched_departure_time` suggests the LTZ slot is the local time.)
2. **SEM-06/DTX-10 — source types.** What are the source types of
   `o.sched_departure_date` and `n.sched_departure_time`? Should the casts in
   `CONCAT`/`TO_DATE` be made explicit (`TO_CHAR(TO_DATE(...),'YYYY-MM-DD')`)
   to avoid session-default formatting?
3. **SEM-06 — `FF9` precision.** Does `n.sched_departure_time` carry 9-digit
   fractional seconds, or should the `FF9` mask be relaxed (e.g. `FF6`/`FF3`)?
4. **SEM-10 — join-key grain.** Are `n.act_departure_station`/
   `n.act_arrival_station` semantically the same (actual) grain as
   `o.departure_station`/`o.arrival_station`? A scheduled-vs-actual mismatch
   would change the join.
5. **SEM-08 — `''` vs NULL.** Does the source ever use `''` (empty string) as
   a sentinel that should be treated as NULL in the `change_ind` CASE? If so,
   add `NULLIF(col,'')` before the `IS NULL` test.
6. **SEM-03 — `CHAR(n)` padding.** Are any join keys `CHAR(n)`? If so, wrap
   both sides in `RTRIM`/`TRIM` to preserve Teradata blank-padding semantics.
7. **DEF-06 (confirmation) — position 42.** Confirm the
   `TO_TIMESTAMP_LTZ(...)` expression is positionally correct in slot 42
   (`new_sched_departure_time`) and only the alias was wrong. The logical
   shape (date + time → timestamp) supports this, but without ground truth it
   is an inference.

---

## 6. Inline anchors

```anchors
TO_TIMESTAMP_LTZ( :: SEM-04: TO_TIMESTAMP_LTZ returns a timestamp with local session TZ; confirm new_sched_departure_time is local-time and pin session TIMEZONE
CONCAT(TO_DATE(o.sched_departure_date), ' ', n.sched_departure_time) :: SEM-06/DTX-10: implicit date/time casts in CONCAT; make explicit with TO_CHAR(...,'YYYY-MM-DD')
'YYYY-MM-DD HH24:MI:SS.FF9' :: SEM-06: FF9 mask expects 9-digit fractional seconds; confirm n.sched_departure_time precision
AS new_sched_departure_time :: DEF-06: alias normalized from new_sched_departure_date to match INSERT target at position 42 (positional binding, no data change)
WHEN o.operating_airline_cd IS NULL THEN 'A' :: SEM-08: change_ind SCD-2 diff uses IS NULL (A=add/E=expire/U=update); confirm '' is not a sentinel
WHEN n.operating_airline_cd IS NULL THEN 'E' :: SEM-08: expire branch of the SCD-2 change_ind CASE
FULL OUTER JOIN staging.wrk_synthetic_flgt_source2 n :: SEM-10: FULL OUTER JOIN preserves adds/expires; join-key grain (act_* vs non-act_) flagged
n.act_departure_station       = o.departure_station :: SEM-10: act_* (actual) vs non-act_ join-key grain; confirm both sides are the same grain
```