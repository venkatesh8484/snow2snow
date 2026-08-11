# Stage 6 — Semantic Explanation: `SFissuetime.sql`

**Fixed SQL:** `03_fix/output/SFissuetime_fixed.sql`
**Teradata ground truth:** none — no `SFissuetime.teradata.sql` in `00_input/`.
Semantic intent is inferred from the SQL itself plus sibling-column / naming
conventions. **Every inference is flagged `TODO(SME)`** and must be confirmed by
a subject-matter expert before sign-off.

---

## 1. Purpose

This statement is a **before/after (old/new) diff of flight-leg records** that
produces an insertion-expiration tracking table. It `INSERT`s into
`staging.wrk_synthetic_flgt_leg_ins_exp` the result of a `FULL OUTER JOIN`
between two synthetic flight-leg sources: `staging.wrk_synthetic_flgt_source1`
(the "old" side, alias `o`) and `staging.wrk_synthetic_flgt_source2` (the "new"
side, alias `n`). The FULL OUTER JOIN captures every flight leg that exists in
*either* source — legs present only on the old side, only on the new side, or on
both. A trailing `change_ind` CASE classifies each output row as **A (add)** when
the old side is NULL, **E (expire)** when the new side is NULL, or **U (update)**
when both sides are present — a standard slowly-changing-dimension diff pattern.
The grain of one output row is **one matching flight leg**: operating airline
code + flight number + suffix + scheduled departure date + departure station +
arrival station. The 60-column target holds 30 `old_*` attributes from `o`,
29 `new_*` attributes from `n`, and the single `change_ind` classifier.

---

## 2. Clause-by-clause walk-through

### 2.1 INSERT target list (60 columns)

The `INSERT INTO staging.wrk_synthetic_flgt_leg_ins_exp ( ... )` column list has
60 slots, in this order:

- **30 `old_*` columns** (positions 1–30): `old_operating_airline_cd`,
  `old_operating_flgt_no`, `old_operating_sfx_cd`, `old_sched_departure_date`,
  `old_gmt_flgt_dt`, `old_departure_station`, `old_arrival_station`,
  `old_service_typ`, `old_sched_arrival_date`, `old_gmt_flgt_arrival_date`,
  `old_sched_departure_time`, `old_sched_arrival_time`,
  `old_gmt_sched_departure_time`, `old_gmt_sched_arrival_time`,
  `old_accounting_year_no`, `old_accounting_month_no`, `old_accounting_week_no`,
  `old_local_flgt_dt`, `old_iata_ac_typ`, `old_pax_departure_timel_cd`,
  `old_pax_arrival_timel_cd`, `old_leg_sequence`, `old_effective_dt`,
  `old_expiry_dt`, `old_opg_flgt_leg_id`, `old_current_rec_ind`,
  `old_carrier_ac_typ`, `old_dep_utc_variation_txt`, `old_arr_utc_variation_txt`,
  `old_sched_src_typ`.
- **29 `new_*` columns** (positions 31–59): `new_sequence`,
  `new_operating_airline_cd`, `new_operating_flgt_no`, `new_operating_sfx_cd`,
  `new_sched_departure_date`, `new_gmt_flgt_dt`, `itinerary_variation_id`,
  `new_act_departure_station`, `new_act_arrival_station`, `new_service_typ`,
  `new_sched_arrival_date`, `new_sched_departure_time`, `new_sched_arrival_time`,
  `new_gmt_sched_departure_time`, `new_gmt_sched_arrival_time`,
  `marketing_airline_cd`, `marketing_flgt_no`, `new_iata_ac_typ`,
  `new_pax_departure_timel_cd`, `new_pax_arrival_timel_cd`, `new_leg_sequence`,
  `new_effective_dt`, `new_expiry_dt`, `new_current_rec_ind`,
  `new_carrier_ac_typ`, `new_dep_utc_variation_txt`, `new_arr_utc_variation_txt`,
  `new_codeshare_ind`, `new_sched_src_typ`.
- **1 classifier** (position 60): `change_ind`.

Because `INSERT…SELECT` is **positional**, the alias names in the SELECT are
cosmetic — each expression lands in the slot dictated by its ordinal position.
The positional alignment audit (Stage 1) confirmed all 60 slots line up; the
only issue was a misleading alias on the constructed timestamp expression
(see §4).

### 2.2 SELECT mapping (old side from `o`, new side from `n`)

The SELECT maps the 30 `old_*` target columns directly from the `o` source
(`o.operating_airline_cd`, `o.operating_flgt_no`, … `o.sched_src_typ`) and 28 of
the 29 `new_*` target columns directly from the `n` source
(`n.sequence`, `n.operating_airline_cd`, … `n.sched_src_typ`). The one
**constructed** expression — `new_sched_departure_time` (position 42) — is built
from *both* sides and is described in §2.3. The final expression (position 60)
is the `change_ind` CASE (§2.4).

### 2.3 Constructed timestamp: `TO_TIMESTAMP_LTZ(CONCAT(TO_DATE(o.sched_departure_date), ' ', n.sched_departure_time), 'YYYY-MM-DD HH24:MI:SS.FF9')`

This is the only expression in the SELECT that is not a plain column copy. It
**combines a date and a time into a single timestamp**:

- `TO_DATE(o.sched_departure_date)` — normalizes the old-side scheduled
  departure **date** to a DATE value (a no-op if it is already a DATE; a
  default-format parse if it is a string).
- `CONCAT( <date>, ' ', n.sched_departure_time )` — concatenates that date, a
  literal space, and the new-side scheduled departure **time** into a single
  string like `2026-07-24 14:35:00.000000000`. This relies on **implicit casts**
  of both the DATE and the TIME to string (SEM-06).
- `TO_TIMESTAMP_LTZ( <string>, 'YYYY-MM-DD HH24:MI:SS.FF9' )` — parses the
  concatenated string into a `TIMESTAMP_LTZ` (timestamp **with local session
  time zone**). The `FF9` element expects **9-digit fractional seconds**.
- The result is aliased `AS new_sched_departure_time` and lands in INSERT
  position 42, which is the `new_sched_departure_time` target column — the
  correct slot for a "departure time expressed as a timestamp" value.

**Why LTZ?** The sibling columns include `old_gmt_sched_departure_time` /
`old_gmt_sched_arrival_time` (GMT/UTC) on the old side and
`new_gmt_sched_departure_time` / `new_gmt_sched_arrival_time` (GMT/UTC) on the
new side. The *non*-GMT slots (`old_sched_departure_time`, `new_sched_departure_time`)
are therefore the **local-time** counterparts. Using `TIMESTAMP_LTZ` for the
local-time slot is plausibly intended, but the session `TIMEZONE` must be pinned
or the stored instant drifts between runs (SEM-04). With no Teradata ground
truth this is an inference — flagged `TODO(SME)`.

**Why `FF9`?** The format mask hard-codes 9 fractional-second digits. If
`n.sched_departure_time` carries fewer digits Snowflake parses leniently
(zero-padding), but if it carries a different precision the value may truncate
or pad unexpectedly (SEM-06). Confirm the source precision — `TODO(SME)`.

### 2.4 `change_ind` CASE — the A/E/U SCD pattern

```sql
CASE
    WHEN o.operating_airline_cd IS NULL THEN 'A'
    WHEN n.operating_airline_cd IS NULL THEN 'E'
    ELSE 'U'
END AS change_ind
```

This is a classic before/after diff classifier:

- **`o.operating_airline_cd IS NULL`** → the row exists only on the new side
  (the FULL OUTER JOIN produced NULLs for all `o` columns) → **'A' (add)**.
- **`n.operating_airline_cd IS NULL`** → the row exists only on the old side
  → **'E' (expire)**.
- **else** → the row exists on both sides → **'U' (update)**.

The test uses `IS NULL` (not an empty-string comparison), which is the correct
way to detect the absent side of a FULL OUTER JOIN. There is no
empty-string-vs-NULL hazard (SEM-08 not present). The choice of
`operating_airline_cd` as the presence probe is safe because it is a join key
and is therefore NULL iff its side is absent.

### 2.5 FULL OUTER JOIN keys — the act-vs-scheduled station question

```sql
FROM   staging.wrk_synthetic_flgt_source1 o
FULL OUTER JOIN staging.wrk_synthetic_flgt_source2 n
       ON n.operating_airline_cd = o.operating_airline_cd
      AND n.operating_flgt_no    = o.operating_flgt_no
      AND n.operating_sfx_cd     = o.operating_sfx_cd
      AND n.sched_departure_date = o.sched_departure_date
      AND n.act_departure_station = o.departure_station
      AND n.act_arrival_station   = o.arrival_station
```

The join matches flight legs on **operating airline code, flight number, suffix,
scheduled departure date, and the two stations**. The first four keys are
identically named on both sides. The two station keys, however, are **not**
identically named: the new side uses `n.act_departure_station` /
`n.act_arrival_station` (the `act_` prefix suggests **actual** stations), while
the old side uses `o.departure_station` / `o.arrival_station` (no prefix —
ambiguous between scheduled and actual). The old-side columns map to the
`old_departure_station` / `old_arrival_station` target slots.

If `o.departure_station` / `o.arrival_station` are **actual** stations, the join
is a clean actual-vs-actual match and the grain is "one actual flight leg". If
they are **scheduled** stations, the join silently compares actual (new) to
scheduled (old) stations, which would change which rows pair up and therefore
change every `change_ind` value (SEM-10). Without DDL or a Teradata original this
cannot be proven — flagged `TODO(SME)`.

---

## 3. Semantic checks table

| SEM ID | Risk | Present? | Corrected how? | Equivalent to Teradata? |
|---|---|---|---|---|
| **SEM-04** | Timestamp / timezone (`TO_TIMESTAMP_LTZ` returns a local-session-TZ timestamp; session `TIMEZONE` must be pinned) | **Yes** (the `TO_TIMESTAMP_LTZ(...)` expression for `new_sched_departure_time`) | **Not corrected — SME.** No ground truth; LTZ is plausible given the local-vs-GMT sibling columns but unconfirmed. `TODO(SME)`: confirm LTZ intent and pin session `TIMEZONE`. | **SME** — pending confirmation. |
| **SEM-06** | Implicit cast / NULL in comparison (implicit DATE→string and TIME→string casts inside `CONCAT`; `FF9` precision assumption) | **Yes** (`CONCAT(TO_DATE(o.sched_departure_date), ' ', n.sched_departure_time)` and the `'YYYY-MM-DD HH24:MI:SS.FF9'` mask) | **Not corrected — SME.** Suggested explicit form `TO_CHAR(TO_DATE(o.sched_departure_date),'YYYY-MM-DD')` not applied (minimal-diff policy; no ground truth). `TODO(SME)`: confirm source column types and `n.sched_departure_time` fractional-second precision. | **SME** — pending confirmation. |
| **SEM-10** | Join-key direction / alias grain (`n.act_*_station` vs `o.departure_station`/`o.arrival_station`) | **Yes** (the two station join keys) | **Not corrected — SME.** The alias difference is preserved as-is; renaming would hide a potential real bug. `TODO(SME)`: confirm both sides are actual-station grain. | **SME** — pending confirmation. |
| **SEM-08** | Empty string vs NULL (`change_ind` uses `IS NULL`) | **No** — the CASE tests `IS NULL`, which is the correct absent-side probe for a FULL OUTER JOIN. No empty-string comparison. | N/A | N/A (correct as written). |
| **SEM-01** | Integer division | **No** — there is no `/` division anywhere in the script. | N/A | N/A. |
| **SEM-02** | `QUALIFY` / dedup ordering | **No** — no `QUALIFY`, `ROW_NUMBER`, or `ORDER BY`. | N/A | N/A. |
| **SEM-03** | `CHAR(n)` padding & comparison | **No** — no DDL supplied; no visible `CHAR(n)` comparison. The join keys are equality on airline/flight/suffix/date/station columns whose pad behavior cannot be assessed without DDL. | N/A | N/A (raise if DDL is later supplied). |
| **SEM-05** | SET-table dedup | **No** — a single `INSERT … SELECT` with one `FULL OUTER JOIN`; no `UNION`/`UNION ALL`, no second INSERT into the same target. No SET-dedup signal. | N/A | N/A. |
| **SEM-07** | `NULL` ordering feeding `QUALIFY`/`TOP` | **No** — no `ORDER BY`, `QUALIFY`, or `TOP`. | N/A | N/A. |
| **SEM-09** | Aggregate of empty set / `SUM` NULL | **No** — no aggregate functions in the script. | N/A | N/A. |

---

## 4. Divergences from the original

There is exactly **one** change from the buggy input, and it is cosmetic:

| Change | Rule | Lines | Data impact |
|---|---|---|---|
| Alias `AS new_sched_departure_date` → `AS new_sched_departure_time` on the constructed `TO_TIMESTAMP_LTZ(...)` expression | **DEF-06** (alias ≠ target — cosmetic) | 106–109 | **None.** `INSERT…SELECT` is positional; the expression already landed in slot 42 (`new_sched_departure_time`) by virtue of its ordinal position. The alias was a copy-paste error that matched INSERT slot 35 (`new_sched_departure_date`, already populated by `n.sched_departure_date`). Normalizing the alias only improves readability — no row, column, or type changes. |

No other SQL changes were made. No syntax, function, or datatype fix was
required (the input was already clean Snowflake). All four semantic risks
(SEM-04, SEM-06, SEM-10) are **preserved as-is** with `TODO(SME)` markers rather
than mechanically "corrected", because none can be proven without ground truth or
DDL, and the minimal-diff policy forbids speculative rewrites.

---

## 5. Open SME questions

Each is phrased as a decision the reviewer must make. All stem from the absence
of a Teradata ground truth and/or DDL.

- **SME-Q1 (SEM-04):** Is `new_sched_departure_time` intended to store a
  **local-time** timestamp (`TIMESTAMP_LTZ`), as opposed to `TIMESTAMP_NTZ` or
  `TIMESTAMP_TZ`? If LTZ is correct, should the session `TIMEZONE` be pinned
  (e.g. `ALTER SESSION SET TIMEZONE = 'America/Chicago'`) so the stored instant
  does not drift between runs?
- **SME-Q2 (SEM-06):** What are the source column types of
  `o.sched_departure_date` and `n.sched_departure_time`? Should the implicit
  casts inside `CONCAT(TO_DATE(...), ' ', n.sched_departure_time)` be made
  explicit (e.g. `TO_CHAR(TO_DATE(o.sched_departure_date),'YYYY-MM-DD')`) to
  remove dependence on session default formats?
- **SME-Q3 (SEM-06):** Does `n.sched_departure_time` carry **9-digit fractional
  seconds**, matching the `FF9` element in the format mask? If its precision
  differs, should the mask be relaxed (e.g. `FF6`) or the value pre-formatted?
- **SME-Q4 (SEM-10):** Are `n.act_departure_station` / `n.act_arrival_station`
  semantically the **same (actual) grain** as `o.departure_station` /
  `o.arrival_station`? A scheduled-vs-actual mismatch on either station key
  would silently change which rows pair up and therefore every `change_ind`
  value.
- **SME-Q5 (DEF-06):** Confirm the `TO_TIMESTAMP_LTZ(...)` expression is
  positionally correct in INSERT slot 42 (`new_sched_departure_time`) and that
  only the **alias** was wrong (not the position). The logical shape
  (date + time → timestamp) supports this, but without ground truth it remains
  an inference.

---

## 6. Inline anchors

```anchors
INSERT INTO staging.wrk_synthetic_flgt_leg_ins_exp :: Purpose: before/after diff of flight leg records into an insertion-expiration tracking table (FULL OUTER JOIN of old source1 vs new source2; change_ind = A/E/U).
TO_TIMESTAMP_LTZ( :: SEM-04: Returns a local-session-TZ timestamp. Confirm LTZ intent for new_sched_departure_time and pin session TIMEZONE.
CONCAT(TO_DATE(o.sched_departure_date) :: SEM-06: Implicit casts in CONCAT/TO_DATE — consider explicit TO_CHAR(TO_DATE(...),'YYYY-MM-DD'). Confirm source column types.
'YYYY-MM-DD HH24:MI:SS.FF9' :: SEM-06: FF9 expects 9-digit fractional seconds — confirm n.sched_departure_time precision matches.
WHEN o.operating_airline_cd IS NULL THEN 'A' :: change_ind SCD pattern: A=add (old side absent), E=expire (new side absent), U=update (both present).
FULL OUTER JOIN staging.wrk_synthetic_flgt_source2 n :: SEM-10: Join keys use n.act_*_station vs o.departure_station/arrival_station — confirm both sides are actual-station grain.
```