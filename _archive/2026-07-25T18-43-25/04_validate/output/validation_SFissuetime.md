# Validation Report — SFissuetime

- **Fixed file:** `03_fix/output/SFissuetime_fixed.sql`
- **Control (buggy input):** `00_input/SFissuetime.sql`
- **Date:** 2026-07-24
- **Validator:** `04_validate/validate.py` (sqlglot + Snowflake EXPLAIN backend)
- **Stage:** 4 — Validate

---

## 1. Fixed-file validation

Command: `python3 04_validate/validate.py 03_fix/output/SFissuetime_fixed.sql`

```
PASS  snowflake connection: probe returned 1
PASS  parse: 1 statement(s) parsed as snowflake using snowflake
PASS  snowflake EXPLAIN stmt 1: compiled OK
PASS  stmt 1: INSERT columns (60) == SELECT expressions (60)
PASS  stmt 1: no duplicate INSERT columns
PASS  no residual Teradata constructs
INFO  TODO(SME) markers outstanding: 5
------------------------------------------------------------
RESULT: PASS
```

**Mechanical verdict: PASS.** The fixed file parses, compiles against a live
Snowflake backend (EXPLAIN OK), has matching INSERT/SELECT column counts (60 =
60), no duplicate INSERT columns, and no residual Teradata constructs.

---

## 2. Control validation (buggy input)

Command: `python3 04_validate/validate.py 00_input/SFissuetime.sql`

```
PASS  snowflake connection: probe returned 1
PASS  parse: 1 statement(s) parsed as snowflake using snowflake
PASS  snowflake EXPLAIN stmt 1: compiled OK
PASS  stmt 1: INSERT columns (60) == SELECT expressions (60)
PASS  stmt 1: no duplicate INSERT columns
PASS  no residual Teradata constructs
INFO  TODO(SME) markers outstanding: 0
------------------------------------------------------------
RESULT: PASS
```

**Control PASS — expected and not a re-fix trigger.** The only defect in
`SFissuetime.sql` is a **cosmetic alias mismatch** (DEF-06): the SELECT alias
`AS new_sched_departure_date` should be `AS new_sched_departure_time` to match
the INSERT column name. Because `INSERT … SELECT` is **positional**, the alias
name has no effect on parse, compile, or execution — so the mechanical validator
correctly PASSes the buggy input. This is the documented behavior for
cosmetic-only / semantic-only defects; the decisive evidence is the manual
spot-check below (check 5), not the control result. No re-fix is warranted.

---

## 3. Manual spot-checks

| # | Check | Result | Evidence |
|---|-------|--------|----------|
| 1 | JOIN keys intact (FULL OUTER JOIN on airline_cd, flgt_no, sfx_cd, sched_departure_date, departure/arrival stations) | **PASS** | `FULL OUTER JOIN staging.wrk_synthetic_flgt_source2 n ON n.operating_airline_cd = o.operating_airline_cd AND n.operating_flgt_no = o.operating_flgt_no AND n.operating_sfx_cd = o.operating_sfx_cd AND n.sched_departure_date = o.sched_departure_date AND n.act_departure_station = o.departure_station AND n.act_arrival_station = o.arrival_station` — all 6 keys preserved. |
| 2 | CASE branches in order (change_ind: A/E/U logic preserved) | **PASS** | `CASE WHEN o.operating_airline_cd IS NULL THEN 'A' WHEN n.operating_airline_cd IS NULL THEN 'E' ELSE 'U' END AS change_ind` — A→E→U order intact. |
| 3 | No dropped columns (60 INSERT = 60 SELECT) | **PASS** | Validator confirms `INSERT columns (60) == SELECT expressions (60)`. |
| 4 | No residual Teradata function/operator | **PASS** | Validator confirms `no residual Teradata constructs`; grep for `ZEROIFNULL\|CONTAINS\|MULTISET\|(+)\|MINUS\|SEL ` returns no matches. |
| 5 | Alias fix applied: `AS new_sched_departure_time` (was `AS new_sched_departure_date`) | **PASS** | Line 120: `) AS new_sched_departure_time,`; FIX LOG line 2 cites DEF-06. |
| 6 | TODO(SME) markers present (SEM-04, SEM-06×2, SEM-10) | **PASS** | 5 `TODO(SME)` markers found: SEM-04 (TO_TIMESTAMP_LTZ TZ), SEM-06 ×2 (implicit casts in CONCAT/TO_DATE; FF9 precision), SEM-10 (station grain). |

---

## 4. TODO(SME) markers outstanding

5 markers carried forward for SME review (no mechanical fix possible):

1. **SEM-04** — `TO_TIMESTAMP_LTZ` returns local-session-TZ timestamp; confirm `new_sched_departure_time` should hold local time (not NTZ/TZ); pin session `TIMEZONE`.
2. **SEM-06** — Implicit casts in `CONCAT`/`TO_DATE`; consider `TO_CHAR(TO_DATE(o.sched_departure_date),'YYYY-MM-DD')` for explicitness; confirm source column types.
3. **SEM-06** — `FF9` expects 9-digit fractional seconds; confirm `n.sched_departure_time` precision matches.
4. **SEM-10** — Join keys `n.act_departure_station = o.departure_station` and `n.act_arrival_station = o.arrival_station`; confirm both sides are actual (not scheduled) station grain.

(One SEM-06 rule ID covers two distinct inline markers, giving 5 total lines.)

---

## 5. Overall verdict

# ✅ PASS

`SFissuetime_fixed.sql` is mechanically valid (parse, EXPLAIN, column count,
no residual Teradata) and passes all six manual spot-checks. The single defect
(DEF-06 alias mismatch) is corrected. The control PASS is expected for a
cosmetic-only issue and does not indicate a re-fix need. 5 `TODO(SME)` markers
are outstanding for human review (semantic confirmations only — no SQL defect).

**No hand-back to s2s-fix.** Stage 4 complete; proceed to Stage 5 (report) and
Stage 6 (explain).