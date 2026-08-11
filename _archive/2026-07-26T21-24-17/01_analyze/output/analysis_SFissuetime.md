# Stage 1 — Analysis: `SFissuetime.sql`

**Input:** `00_input/SFissuetime.sql`
**Teradata ground truth:** none supplied (no `00_input/SFissuetime.teradata.sql`).
**Reviewer feedback:** `07_review/output/review_SFissuetime.md` is empty.
**Archive:** prior outputs for this unit were already archived (output dir held no `analysis_SFissuetime.md`); slate is clean.

---

## 1. Column-count check (INSERT target cols vs SELECT expressions)

| Side | Count | Duplicates | Net (after dedupe) |
|---|---|---|---|
| INSERT target columns | 60 | none | 60 |
| SELECT expressions | 60 | none | 60 |

**Verdict: counts match (60 = 60).** No duplicate columns on either side. No
DEF-05 (count mismatch). Binding is positional; aliases are cosmetic.

### Position-by-position alias alignment audit

INSERT…SELECT binds by ordinal position, not by alias, so a wrong alias does
**not** fail the mechanical validator. Audited every position; one mismatch:

| Pos | INSERT target col | SELECT expression / alias | Aligned? |
|---|---|---|---|
| 35 | `new_sched_departure_date` | `n.sched_departure_date` | ✅ |
| 42 | `new_sched_departure_time` | `TO_TIMESTAMP_LTZ(CONCAT(TO_DATE(o.sched_departure_date), ' ', n.sched_departure_time), 'YYYY-MM-DD HH24:MI:SS.FF9') AS new_sched_departure_date` | ⚠️ alias ≠ target name |
| 43 | `new_sched_arrival_time` | `n.sched_arrival_time` | ✅ |

The alias `AS new_sched_departure_date` on the position-42 expression is
**cosmetically wrong** — that slot is `new_sched_departure_time`. This is a
DEF-06 (alias ≠ target name), not a count defect. The expression itself
(date+time → timestamp) is plausibly intended for this slot, but the alias is
misleading. See §3 DEF-06 and §4 SEM-04/SEM-06.

---

## 2. Syntax errors / residual-Teradata constructs

Scanned for `CONTAINS`/`OVERLAPS`, `ZEROIFNULL`/`NULLIFZERO`, `SEL`,
`SET`/`MULTISET`, `PRIMARY INDEX`, `COLLECT STATS`, BTEQ directives, `(+)`,
`MINUS`, `TOP`, `FORMAT` casts, `TITLE`/`FORMAT` phrases, `INDEX()`,
`OREPLACE`, `OTRANSLATE`, `STRTOK`, `HASHROW`, `MOD` infix, `**` power,
`LIKE ANY`, `SUBSTRING … FROM … FOR`.

| # | Line | Construct | Rule | Why invalid on Snowflake | Class |
|---|---|---|---|---|---|
| — | — | none found | — | — | — |

**No residual-Teradata constructs and no syntax errors.** The file is parse-clean
Snowflake. No `SFX-*`, `FNX-*`, or `DTX-*` rules fire. (This is a re-run of a
unit whose prior lessons already established parse-cleanliness; confirmed again.)

---

## 3. Defects (DEF-*)

| # | Line | Defect | Rule | Notes | Class |
|---|---|---|---|---|---|
| D1 | 103 (SELECT pos 42) | Alias `AS new_sched_departure_date` does not match the INSERT target column at that position (`new_sched_departure_time`) | DEF-06 | INSERT…SELECT is positional, so this is cosmetic, not a runtime error. Normalize the alias to `new_sched_departure_time` for readability. Do **not** move the expression — its slot is correct. | FIX |

No DEF-01 (dup columns), DEF-02 (keyword typo), DEF-03 (unbalanced parens),
DEF-04 (malformed call), DEF-05 (count mismatch), or DEF-07 (wrong column ref)
found.

---

## 4. Semantic risks (SEM-*)

No Teradata ground truth supplied; every inference below is flagged `TODO(SME)`.

| # | Line | Risk | Rule | Present? | Notes | Class |
|---|---|---|---|---|---|---|
| S1 | 103 (pos 42) | `TO_TIMESTAMP_LTZ(...)` introduces a session-timezone dependency | SEM-04 | Yes | The stored LTZ value shifts with the session `TIMEZONE` unless pinned. The target has a `gmt_*` sibling (`new_gmt_sched_departure_time`, pos 44), so the LTZ slot is plausibly the *local* time — but without DDL/ground truth this is an inference. Prefer pinning `TIMEZONE` in the session or using `TIMESTAMP_NTZ`/`TIMESTAMP_TZ` explicitly. Flag `TODO(SME)`. | SME |
| S2 | 103 (pos 42) | `CONCAT(TO_DATE(o.sched_departure_date), ' ', n.sched_departure_time)` relies on implicit date→string and time→string casts | SEM-06 / DTX-10 | Yes | The format of the implicit casts depends on session defaults; the `'YYYY-MM-DD HH24:MI:SS.FF9'` parse mask assumes a specific string shape. Emit `TO_CHAR(TO_DATE(o.sched_departure_date),'YYYY-MM-DD')` and an explicit time-to-char before `CONCAT`. Also confirm the `FF9` mask matches the source time precision (nanoseconds vs. seconds). Flag `TODO(SME)`. | SME |
| S3 | 122-127 (FULL OUTER JOIN ON) | Join-key grain mismatch: `n.act_departure_station = o.departure_station` and `n.act_arrival_station = o.arrival_station` mix `act_*` (actual) columns on the new side with non-`act_` names on the old side | SEM-10 | Yes | Without DDL/ground truth you cannot prove `act_departure_station` and `departure_station` are the same grain (scheduled vs. actual). A "fixed" alias can hide a real bug. Flag `TODO(SME)`; do not rewrite the join. | SME |
| S4 | 128-132 (CASE change_ind) | `change_ind` CASE branches on NULL presence of `o.operating_airline_cd` / `n.operating_airline_cd` to emit `'A'`/`'E'`/`'U'` | SEM-06 | Yes (low) | Relies on NULL semantics of the FULL OUTER JOIN. This is the intended add/edit/update pattern and parses fine; the only risk is if `operating_airline_cd` can be an empty string `''` vs NULL (SEM-08). No DDL to confirm. Flag `TODO(SME)` for the `''` vs NULL distinction. | SME |
| S5 | whole statement | SET-table dedup (single INSERT, no UNION, no second INSERT into same target) | SEM-05 | No | Only one `INSERT` into `staging.wrk_synthetic_flgt_leg_ins_exp`; no `UNION`/`UNION ALL` branches writing to one target. SEM-05 SET-table signal is **not** present. No SME question raised. | n/a |
| S6 | join keys | `CHAR(n)` padding / comparison drift on join keys (`operating_airline_cd`, `operating_sfx_cd`, `service_typ`, `*_cd`, `*_typ`) | SEM-03 | Possible | If any join key is `CHAR(n)`, Teradata blank-pads and ignores trailing spaces in `=`; Snowflake does not pad, so `'AA' <> 'AA '`. No DDL supplied → cannot confirm types. Flag `TODO(SME)`. | SME |
| S7 | — | Integer division | SEM-01 | No | No `/` division in the script. | n/a |
| S8 | — | `QUALIFY` / dedup ordering | SEM-02 | No | No `QUALIFY` or `ROW_NUMBER` dedup. | n/a |
| S9 | — | `NULL` ordering feeding `QUALIFY`/`TOP` | SEM-07 | No | No `ORDER BY` feeding a `QUALIFY`/`TOP`. | n/a |
| S10 | — | Empty string vs NULL in `NULLIF(x,'')` | SEM-08 | No | No `NULLIF(x,'')`. (See S4 for the related `''` vs NULL question on `change_ind` inputs.) | n/a |
| S11 | — | Aggregate of empty set / `SUM` NULL | SEM-09 | No | No aggregates. | n/a |

---

## 5. Classification summary

| Class | Count | Findings |
|---|---|---|
| AUTO | 0 | — |
| FIX | 1 | D1 (DEF-06 alias normalization, line 103) |
| SME | 5 | S1 (SEM-04 TZ), S2 (SEM-06/DTX-10 implicit cast), S3 (SEM-10 join-key grain), S4 (SEM-06/SEM-08 `''` vs NULL), S6 (SEM-03 CHAR padding) |
| KEEP | 0 | (not a `.snowsql` input; no SNZ constructs) |

**Open SME questions (to be embedded as `TODO(SME)` in Stage 3):**
1. Is the position-42 `TO_TIMESTAMP_LTZ` slot intended to store *local* time (with `new_gmt_sched_departure_time` as the GMT sibling)? Should the session `TIMEZONE` be pinned, or should `TIMESTAMP_NTZ`/`TIMESTAMP_TZ` be used explicitly? (SEM-04)
2. Should the date+time concatenation use explicit `TO_CHAR` casts, and does the `FF9` mask match the source `sched_departure_time` precision? (SEM-06/DTX-10)
3. Are `n.act_departure_station`/`n.act_arrival_station` the same grain as `o.departure_station`/`o.arrival_station` (scheduled vs. actual)? (SEM-10)
4. Can `operating_airline_cd` be an empty string `''` rather than NULL, which would change the `change_ind` CASE result? (SEM-08)
5. Are any join keys `CHAR(n)` (which would require `TRIM`/`RTRIM` to preserve Teradata blank-padding semantics)? (SEM-03)

---

## 6. Table dependency inventory

| Role | Table | Schema | Notes |
|---|---|---|---|
| TARGET (INSERT) | `wrk_synthetic_flgt_leg_ins_exp` | `staging` | 60-column target. No DDL supplied → SET/MULTISET unknown, but SEM-05 not triggered (single INSERT, no UNION). |
| SOURCE (old side, alias `o`) | `wrk_synthetic_flgt_source1` | `staging` | FULL OUTER JOIN left side. |
| SOURCE (new side, alias `n`) | `wrk_synthetic_flgt_source2` | `staging` | FULL OUTER JOIN right side. |

**Join:** `staging.wrk_synthetic_flgt_source1 o` FULL OUTER JOIN `staging.wrk_synthetic_flgt_source2 n` on airline_cd, flgt_no, sfx_cd, sched_departure_date, act_departure_station↔departure_station, act_arrival_station↔arrival_station.

---

## 7. One-line verdict

Parse-clean Snowflake with a 60=60 column count and one cosmetic DEF-06 alias
mismatch (FIX); the real work is five SME-classified semantic risks —
session-TZ on `TO_TIMESTAMP_LTZ` (SEM-04), implicit date/time casts (SEM-06),
join-key grain mismatch on `act_*` vs non-`act_` columns (SEM-10), `''` vs NULL
on `change_ind` (SEM-08), and possible `CHAR(n)` padding drift on join keys
(SEM-03) — all requiring DDL/ground-truth confirmation before any mechanical
change beyond the alias normalization.