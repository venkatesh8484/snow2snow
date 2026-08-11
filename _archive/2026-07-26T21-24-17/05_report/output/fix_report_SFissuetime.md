# Stage 5 — Fix Report: `SFissuetime.sql`

**Unit:** `SFissuetime`
**Input:** `00_input/SFissuetime.sql`
**Fixed SQL:** `03_fix/output/SFissuetime_fixed.sql`
**Analysis:** `01_analyze/output/analysis_SFissuetime.md`
**Validation:** `04_validate/output/validation_SFissuetime.md`
**Semantic doc:** `06_explain/output/semantic_SFissuetime.md` (archived copy:
`_archive/2026-07-25T18-43-25/06_explain/output/semantic_SFissuetime.md`)
**Teradata ground truth:** none supplied (no `00_input/SFissuetime.teradata.sql`).
Every semantic inference is flagged `TODO(SME)`.

---

## 1. Executive summary

`SFissuetime.sql` is a parse-clean Snowflake `INSERT … SELECT` over a `FULL
OUTER JOIN` of two synthetic flight-leg sources (`staging.wrk_synthetic_flgt_source1`
"old" side `o`, `staging.wrk_synthetic_flgt_source2` "new" side `n`) into the
60-column target `staging.wrk_synthetic_flgt_leg_ins_exp`. The statement is a
before/after (old/new) diff producing an insertion-expiration tracking table,
with a trailing `change_ind` CASE classifying each row as **A** (add, old side
NULL), **E** (expire, new side NULL), or **U** (update, both present).

- **Column count:** 60 INSERT target columns = 60 SELECT expressions. No
  duplicates on either side. No DEF-05 (count mismatch).
- **Mechanical fixes:** 1 — a cosmetic DEF-06 alias normalization at SELECT
  position 42.
- **Semantic risks:** 5 SME-classified risks (SEM-04, SEM-06/DTX-10, SEM-10,
  SEM-08, SEM-03), all flagged inline as `TODO(SME)`; no mechanical change.
- **Validation:** ✅ PASS (mechanical). Control (buggy input) also PASSes —
  expected for a cosmetic-only DEF-06 defect; not a re-fix trigger.
- **Outstanding `TODO(SME)`:** 11 markers (reviewer prompts, not defects).

A reviewer can sign off from this document plus the Stage-6 semantic doc.

---

## 2. Rules applied

### 2.1 Syntax / function / datatype rules (SFX-* / FNX-* / DTX-*)

None fired. The input is parse-clean Snowflake with no residual Teradata
constructs (no `ZEROIFNULL`, `CONTAINS`, `MULTISET`, `(+)`, BTEQ dot-commands,
`MINUS`, `SEL`, `INDEX()`, `OREPLACE`, `OTRANSLATE`, `STRTOK`, `HASHROW`,
`LIKE ANY`, `SUBSTRING … FROM … FOR`, `FORMAT`/`TITLE` phrases, `**` power,
infix `MOD`, `TOP`, `OVERLAPS`). No `SFX-*`, `FNX-*`, or `DTX-*` rules applied.

### 2.2 Defect rules (DEF-*)

| Rule | Location | Defect | Action |
|---|---|---|---|
| **DEF-06** | SELECT pos 42 (line 103) | SELECT-side alias `AS new_sched_departure_date` did not match the INSERT target column at that position (`new_sched_departure_time`). `INSERT … SELECT` is positional, so this is cosmetic, not a runtime error. | Alias normalized to `AS new_sched_departure_time`. The expression (date+time → `TO_TIMESTAMP_LTZ`) stays in its slot — only the alias label changed. |

No DEF-01 (duplicate columns), DEF-02 (keyword typo), DEF-03 (unbalanced
parens), DEF-04 (malformed call), DEF-05 (count mismatch), or DEF-07 (wrong
column ref) found.

### 2.3 Semantic rules (SEM-*)

No mechanical changes were made for semantic risks; each is flagged inline as
`TODO(SME)` for SME/DDL confirmation. (No Teradata ground truth supplied.)

| Rule | Location | Risk | Action |
|---|---|---|---|
| **SEM-04** | SELECT pos 42 (line 103) | `TO_TIMESTAMP_LTZ(...)` introduces a session-`TIMEZONE` dependency; the stored LTZ value shifts with the session TZ unless pinned. Target has a `gmt_*` sibling (`new_gmt_sched_departure_time`, pos 44), so the LTZ slot is plausibly *local* time. | `TODO(SME)` — confirm intent (local vs GMT), whether to pin session `TIMEZONE`, or use `TIMESTAMP_NTZ`/`TIMESTAMP_TZ` explicitly. No change. |
| **SEM-06 / DTX-10** | SELECT pos 42 (line 103) | `CONCAT(TO_DATE(o.sched_departure_date), ' ', n.sched_departure_time)` relies on implicit date→string and time→string casts whose format depends on session defaults; the `'YYYY-MM-DD HH24:MI:SS.FF9'` parse mask assumes a specific string shape. | `TODO(SME)` — confirm explicit `TO_CHAR` casts and that the `FF9` mask matches source `sched_departure_time` precision (nanoseconds vs seconds). No change. |
| **SEM-10** | FULL OUTER JOIN ON (lines 122–127) | Join-key grain mismatch: `n.act_departure_station = o.departure_station` and `n.act_arrival_station = o.arrival_station` mix `act_*` (actual) columns on the new side with non-`act_` names on the old side. Without DDL/ground truth the grains (scheduled vs actual) cannot be proven equal. | `TODO(SME)` — confirm same grain. Join left unchanged. |
| **SEM-08** | `change_ind` CASE (lines 128–132) | CASE branches on NULL presence of `o.operating_airline_cd` / `n.operating_airline_cd` to emit `'A'`/`'E'`/`'U'`. Risk if `operating_airline_cd` can be an empty string `''` (not NULL), which would change the branch result. | `TODO(SME)` — confirm `operating_airline_cd` cannot be `''`. No change. |
| **SEM-03** | Join keys | Possible `CHAR(n)` padding/comparison drift on join keys (`operating_airline_cd`, `operating_sfx_cd`, `service_typ`, `*_cd`, `*_typ`). Teradata blank-pads and ignores trailing spaces in `=`; Snowflake does not pad, so `'AA' <> 'AA '`. | `TODO(SME)` — confirm whether any `CHAR(n)` keys require `TRIM`/`RTRIM`. No change. |

SEM-01 (integer division), SEM-02 (`QUALIFY`/dedup ordering), SEM-05 (SET-table
dedup — single INSERT, no UNION), SEM-07 (NULL ordering feeding `QUALIFY`/`TOP`),
SEM-09 (aggregate of empty set) were all assessed and **not present**.

### 2.4 SnowSQL client rules (SNZ-*)

Not applicable — `SFissuetime.sql` is not a `.snowsql` input; no `<% %>`
template tags or `PUT`/`GET` commands.

---

## 3. Defects repaired

| # | Defect | Rule | Fix |
|---|---|---|---|
| 1 | SELECT pos 42 alias `AS new_sched_departure_date` ≠ INSERT target `new_sched_departure_time` | DEF-06 | Renamed alias to `AS new_sched_departure_time`. Expression and slot unchanged (positional binding preserved). |

**Minimal diff:** exactly one alias token changed. No expression moved, no JOIN
rewritten, no CASE reordered, no columns added/removed.

---

## 4. Open `TODO(SME)` items

11 outstanding `TODO(SME)` markers in `03_fix/output/SFissuetime_fixed.sql`,
all reviewer prompts (INFO-level, not defects):

1. **SEM-04** (pos 42) — `TO_TIMESTAMP_LTZ` session-TZ dependency: is this slot
   intended as local time (with `new_gmt_sched_departure_time` as GMT sibling)?
   Pin session `TIMEZONE` or use `TIMESTAMP_NTZ`/`TIMESTAMP_TZ`?
2. **SEM-06** (pos 42) — date+time concatenation: use explicit `TO_CHAR` casts?
   Does `FF9` mask match source `sched_departure_time` precision?
3. **SEM-10** (JOIN ON) — are `n.act_departure_station`/`n.act_arrival_station`
   the same grain as `o.departure_station`/`o.arrival_station` (scheduled vs
   actual)?
4. **SEM-08** (`change_ind` CASE) — can `operating_airline_cd` be an empty
   string `''` rather than NULL (which would change the CASE branch)?
5. **SEM-03** (join keys) — are any join keys `CHAR(n)` requiring `TRIM`/`RTRIM`
   to preserve Teradata blank-padding semantics?

(Markers 6–11 are duplicate inline restatements of the above at their
respective anchor points in the fixed SQL.)

---

## 5. Validation result

**Source:** `04_validate/output/validation_SFissuetime.md`

### 5.1 Fixed file — mechanical checks

`python3 04_validate/validate.py 03_fix/output/SFissuetime_fixed.sql`

| # | Check | Result |
|---|-------|--------|
| 1 | Parse (sqlglot, snowflake dialect) | ✅ PASS — 1 statement parsed |
| 2 | INSERT columns (60) == SELECT expressions (60) | ✅ PASS |
| 3 | No duplicate INSERT columns | ✅ PASS |
| 4 | No residual Teradata constructs | ✅ PASS |
| 5 | TODO(SME) markers outstanding | INFO — 11 (assumptions flagged, not defects) |

**Mechanical verdict: PASS.**

### 5.2 Manual spot-check

- **JOIN keys:** preserved exactly — no JOIN added/removed/reordered; join
  predicates unchanged.
- **CASE branch order:** all `WHEN` branches retain original ordering.
- **Column count / order:** 60 = 60, positional alignment preserved.
- **No dropped columns:** all 60 source columns present.
- **No residual Teradata:** confirmed by mechanical check and manual scan.
- **Snowflake idioms:** conforms to target dialect; `QUALIFY` retained where
  present (none here).

**Manual verdict: PASS.**

### 5.3 Buggy input control

`python3 04_validate/validate.py 00_input/SFissuetime.sql`

```
PASS  parse: 1 statement(s) parsed as snowflake using sqlglot
PASS  stmt 1: INSERT columns (60) == SELECT expressions (60)
PASS  stmt 1: no duplicate INSERT columns
PASS  no residual Teradata constructs
RESULT: PASS
```

**Control PASSES — expected and not a re-fix trigger.** The sole defect is a
cosmetic DEF-06 alias mismatch that is positionally inert: `INSERT … SELECT`
binds by ordinal position, not by alias, so the wrong alias has no runtime
effect. The mechanical validator is structural (parse, count, duplicates,
residual Teradata) and correctly reports PASS for both files. The decisive
evidence is the manual spot-check above, not the control result. Per
s2s-validate policy, a passing control on a semantic-only / DEF-06 defect is
expected; do not hand back to s2s-fix.

### 5.4 Overall verdict

| Aspect | Status |
|--------|--------|
| Mechanical validation (fixed file) | ✅ PASS |
| Control validation (buggy input) | ✅ PASS (expected — cosmetic DEF-06) |
| Manual spot-check | ✅ PASS |
| Residual Teradata | None |
| Column count / order | 60 = 60, preserved |
| JOIN keys / CASE order | Preserved |
| Outstanding TODO(SME) | 11 (reviewer prompts, not defects) |

**Overall: PASS.** `03_fix/output/SFissuetime_fixed.sql` is syntactically valid
Snowflake, structurally faithful to the input, and free of residual Teradata
constructs. The only remediation was a cosmetic DEF-06 alias normalization;
the 5 SEM-* risks are documented for SME review.

---

## 6. Sign-off checklist

- [x] Column count 60 = 60; no DEF-05.
- [x] No residual Teradata constructs.
- [x] JOIN keys and CASE branch order preserved.
- [x] Column order / positional alignment preserved.
- [x] Minimal diff (1 alias token changed).
- [x] Mechanical validation PASS.
- [x] Control PASS explained (cosmetic DEF-06, expected).
- [x] All semantic inferences flagged `TODO(SME)` (no ground truth).
- [ ] **SME:** resolve the 5 open `TODO(SME)` questions (SEM-04, SEM-06/DTX-10,
      SEM-10, SEM-08, SEM-03) before production sign-off.
- [ ] **Optional:** supply `00_input/SFissuetime.teradata.sql` ground truth and
      re-run Stage 1 to diff statement count, set operators, and column list.

**Semantic account:** see `06_explain/output/semantic_SFissuetime.md` for the
clause-by-clause walk-through and the SEM-04 / SEM-06 / SEM-10 correction
patterns that await SME confirmation. This report does not duplicate it.