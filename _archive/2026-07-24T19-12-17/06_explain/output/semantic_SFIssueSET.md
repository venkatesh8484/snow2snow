# Semantic explanation — `SFIssueSET`

## 1. Purpose
Load `staging.wrk_target` with one row per (airline, flight, date) from three
flight-leg sources — marketing, operational, and codeshare legs — keeping, for
each key, the attribute values from the row with the latest `effective_dt`. In
Teradata this was three independent `INSERT`s into a **SET** table, so a row
already present in the target is silently dropped on insert.

## 2. Clause-by-clause walk-through
- **Three branches.** Each branch joins `synthetic_flgt_source` to one leg table
  (marketing / operational / codeshare) and groups by (airline_cd, flgt_no,
  flgt_dt). The delivered file glued them together with `UNION`; the correct form
  is three separate `INSERT`s.
- **"Latest value" projection.** `SUBSTR(MAX(effective_dt || value), 11, …)`
  concatenates the effective date (positions 1–10) with the attribute, takes the
  `MAX`, then strips the date back off from position 11 — i.e. "the value from the
  latest effective_dt". For `operating_flgt_no` this only works if the key is
  fixed-width, so it is wrapped as
  `TO_CHAR(effective_dt,'YYYY-MM-DD') || LPAD(operating_flgt_no::VARCHAR,5,' ')`.
- **SET-table guard.** Each `INSERT` ends with `EXCEPT SELECT * FROM
  staging.wrk_target`, reproducing the Teradata SET-table rule "do not insert a
  row that already exists in the target."

## 3. Semantic checks
| Rule | Risk | Present in delivered file? | Corrected how? | Equivalent to Teradata? |
|---|---|---|---|---|
| SEM-05 | SET-table dedup | **Yes — broken.** `UNION` dropped the per-insert "skip existing" guarantee and added cross-branch dedup | 3 separate `INSERT`s, each `… EXCEPT SELECT * FROM staging.wrk_target` | ✅ Yes |
| FN-LATEST | `MAX(concat)` latest-value ordering | Yes — width-unstable | fixed-width `TO_CHAR`/`LPAD` before `MAX` | ✅ Yes |
| SEM-10 | join direction | No | keys preserved | ✅ Yes |

## 4. Divergences from the original
Target is the redesigned 8-column `staging.wrk_target` (no `dc_cpn_id` /
`bkkg_reference`); confirmed intentional against `SFFixedSET.sql`, not a defect.

## 5. Open SME questions
- Confirm `staging.wrk_target` has exactly the 8 projected columns in this order
  (so `EXCEPT SELECT *` aligns).

## 6. Inline anchors
```anchors
INSERT INTO staging.wrk_target :: One of THREE independent inserts (SET-table append; was wrongly a single UNION).
EXCEPT :: SET-table guard — skip rows already present in the target (the fix for SEM-05).
LPAD(leg.operating_flgt_no :: Fixed-width key so MAX() picks the latest effective_dt row correctly (FN-LATEST).
GROUP BY src.airline_cd, src.flgt_no, src.flgt_dt :: One output row per (airline, flight, date).
```
