# Stage 1 — Analysis: `S_vwxxx_MloadLinksUpdates.snowsql`

**Input:** `00_input/S_vwxxx_MloadLinksUpdates.snowsql`
**Type:** `.snowsql` (SnowSQL client layer applies — `02_rules/07_snowsql_client.md`)
**Teradata ground truth:** **Not supplied.** No `S_vwxxx_MloadLinksUpdates.teradata.sql` exists in `00_input/`. All semantic inferences are flagged `TODO(SME)`.
**Statement shape:** Single `UPDATE … FROM (subquery) … WHERE … AND NOT EXISTS (...)` — no `INSERT … SELECT`, so the column-count check (step 1) is N/A for an INSERT; instead the **subquery-alias vs outer-reference alignment** is audited below.

---

## 0. SnowSQL client-layer inventory (SNZ-*)

Per `02_rules/07_snowsql_client.md`, `.snowsql` constructs are inventoried and classified `KEEP` — they are context to preserve, **not** findings to repair.

| Line | Construct | Rule | Classification |
|---|---|---|---|
| 17 | `<% ctx.env.S_vw6122_CompareLinksRecordsWithTeradata_Current_date %>` template tag inside `TO_DATE(...)` | SNZ-01 | **KEEP** |

- **1 template tag (SNZ-01) detected and preserved verbatim; not remediated.**
- No `PUT`/`GET` (SNZ-02/03) commands present.
- No `COPY INTO @stage` / `REMOVE` / `LIST` (SNZ-04) stage DML present.
- The tag is **never** a syntax defect — do not report it as unparseable. It masks to a bare token for mechanical validation via `snowsql_protect.py`.

---

## 1. Column-count / alias-alignment check

This is an `UPDATE … FROM (subquery) src`, not an `INSERT … SELECT`, so there is no INSERT target list to count. The equivalent audit is **subquery output aliases vs outer `WHERE` references to `src.*`**.

### Subquery (`src`) output aliases (lines 7–19)

| # | Alias (line) | Outer reference (line) | Match? |
|---|---|---|---|
| 1 | `LINK_STATION_CD` (7) | `src.LINK_STATION_CD` (23) | ✅ |
| 2 | `IN_ORIGN_STATION_CD` (8) | `src.IN_ORIGN_STATION_CD` (24) | ✅ |
| 3 | `IN_ALN_CD` (9) | `src.IN_ALN_CD` (25) | ✅ |
| 4 | `IN_FLIGHT_NO` (10) | `src.IN_FLIGHT_NO` (26) | ✅ |
| 5 | `IN_FLIGHT_SFX_CD` (11) | `src.IN_FLIGHT_SFX_CD` (27) | ✅ |
| 6 | **`IN_DEP_GMTFLIGHT_FLIGHT_DT`** (12) | **`src.IN_DEP_FLIGHT_DT`** (28) | ❌ **MISMATCH** |
| 7 | `LINK_EFFECTIVE_DT` (13) | `src.LINK_EFFECTIVE_DT` (29) | ✅ |
| 8 | `LINK_EXPIRY_DT` (18) | `src.LINK_EXPIRY_DT` (3, 40) | ✅ |
| 9 | `CURRENT_REC_IND` (19) | `src.CURRENT_REC_IND` (4, 41) | ✅ |

**Net:** 8 of 9 aliases align; **1 mismatch** — the key finding (DEF-07, below).

---

## 2. Syntax errors / residual-Teradata constructs

| Line | Construct | Rule | Why invalid on Snowflake | Classification |
|---|---|---|---|---|
| — | none | — | — | — |

**No residual-Teradata constructs found.** No `ZEROIFNULL`, `CONTAINS`/`OVERLAPS`, `SEL`, `SET`/`MULTISET`, `PRIMARY INDEX`, `COLLECT STATS`, BTEQ directives, `(+)` joins, `MINUS`, `TOP`, or `CAST(... FORMAT ...)` present. `IFF`, `DATEADD`, `TO_CHAR`, `TO_DATE` are all valid Snowflake functions. The statement is **syntactically parseable** on Snowflake (modulo the SNZ-01 tag, which is masked).

---

## 3. Defects (DEF-*)

| # | Line(s) | Defect | Rule | Classification | Notes |
|---|---|---|---|---|---|
| D1 | 12 vs 28 | **Subquery alias `IN_DEP_GMTFLIGHT_FLIGHT_DT` does not match the outer reference `src.IN_DEP_FLIGHT_DT`.** The subquery projects `OLD_IN_DEP_FLIGHT_DT AS IN_DEP_GMTFLIGHT_FLIGHT_DT`, but the outer `WHERE` joins on `tgt.IN_DEP_FLIGHT_DT = src.IN_DEP_FLIGHT_DT`. `src.IN_DEP_FLIGHT_DT` does not exist in `src`'s output → **runtime resolution error** (`invalid identifier`). | DEF-07 | **SME** | Per DEF-07: only fix if the Teradata original disproves the reference; otherwise flag → SME. **Never guess a column swap.** Two plausible repairs exist and they are *not* equivalent: (a) rename the alias to `IN_DEP_FLIGHT_DT` to match the outer reference and the target column `tgt.IN_DEP_FLIGHT_DT`; or (b) the alias `IN_DEP_GMTFLIGHT_FLIGHT_DT` may be intentional and the *outer reference* is the typo. Without ground truth this cannot be decided mechanically. **SME question:** "Should the subquery alias be `IN_DEP_FLIGHT_DT` (matching `tgt.IN_DEP_FLIGHT_DT`), or is `IN_DEP_GMTFLIGHT_FLIGHT_DT` the intended name and the outer `WHERE` reference on line 28 is the typo?" |
| D2 | 1 vs 32 | **Target table name mismatch.** The `UPDATE` target is `BASE.FLT_FOLDERLINKS` (line 1), but the `NOT EXISTS` anti-join probes `BASE.FLIGHT_FOLDERLINKS` (line 32) — a different table name. | DEF-07 | **SME** | This may be intentional (the anti-join checks a *different* table for pre-existing rows) or a copy-paste typo from a sibling script. Per DEF-07, do not guess a rename. **SME question:** "Is `BASE.FLIGHT_FOLDERLINKS` (line 32) a distinct table from the `UPDATE` target `BASE.FLT_FOLDERLINKS` (line 1), or should both reference the same table?" |

---

## 4. Semantic risks (SEM-*)

| # | Line(s) | Risk | Rule | Present? | Classification | Notes |
|---|---|---|---|---|---|---|
| S1 | 17 | **`TO_DATE('<% ctx.env.…Current_date %>','DDMONYY')` format mask is locale-dependent.** `MON` is case-sensitive and locale-dependent in Snowflake `TO_DATE`. With no Teradata ground truth, the source date format and session locale cannot be verified. | SEM-06 / proposed OBS-01 | Yes | **SME** | Flag `TODO(SME)`. Mirrors the lesson from `S_vwxxx_MapLinksRecordsToOracle.snowsql` (`'DDMONYYHH24MI'` locale dependency). Confirm the orchestrator's `Current_date` value format and the session locale. |
| S2 | 17 | **Template-tag date arithmetic depends on the orchestrator-supplied value type.** `DATEADD(DAY,-1,TO_DATE('<% … %>','DDMONYY'))` assumes the env var resolves to a string in `DDMONYY` form. If it resolves to a different format (e.g. `YYYY-MM-DD`), `TO_DATE` will error or silently mis-parse. | SEM-06 | Yes | **SME** | Flag `TODO(SME)`. The mask must match the orchestrator's emitted format exactly. |
| S3 | 15 | **`TO_CHAR(OLD_LINK_EXPIRY_DT,'YYYYMMDD') <> '20501231'` string comparison of a date.** Relies on `TO_CHAR` producing exactly 8 chars with no sign/spaces. Safe for valid dates, but if `OLD_LINK_EXPIRY_DT` is NULL, `TO_CHAR` returns NULL and the `<>` evaluates to NULL (not TRUE) → the `IFF` falls to the else-branch (`DATEADD(...)`), which may not be the intended NULL handling. | SEM-06 / SEM-08 | Yes | **SME** | Flag `TODO(SME)`. Confirm intended NULL handling for `OLD_LINK_EXPIRY_DT`. |
| S4 | 23–29, 33–41 | **CHAR(n) padding drift in the multi-key join / anti-join.** The join keys (`*_CD`, `*_SFX_CD`) and anti-join keys are plausibly `CHAR(n)`. Teradata blank-pads `CHAR(n)` and ignores trailing spaces in `=`; Snowflake does not pad and `'A' <> 'A '`. | SEM-03 | Yes (plausible) | **SME** | Flag `TODO(SME)`. If any join/anti-join key is `CHAR(n)`, wrap with `TRIM`/`RTRIM` to preserve Teradata semantics. Requires target/source DDL to confirm column types. |
| S5 | 1, 32 | **SET vs MULTISET not decidable.** This is an `UPDATE`, not an `INSERT`, so SEM-05 (SET-table dedup) does **not** apply. | SEM-05 | N/A | — | No SET-table signal. No `CREATE TABLE` DDL supplied, but SEM-05 is an INSERT-only concern; not raised here. |
| S6 | 17 | **Timezone / timestamp.** `TO_DATE(...)` yields a `DATE` (no TZ), and `DATEADD(DAY,-1,...)` is date arithmetic — no TZ risk. `OLD_LINK_EXPIRY_DT` is compared as a date. | SEM-04 | No | — | No `TIMESTAMP`/`TIMESTAMP_TZ` involved; SEM-04 does not fire. |
| S7 | — | **Integer division.** No `/` division present. | SEM-01 | No | — | — |
| S8 | — | **`QUALIFY` / dedup ordering.** No `QUALIFY`/`ROW_NUMBER` present. | SEM-02 | No | — | — |
| S9 | — | **`NULL` ordering feeding TOP/QUALIFY.** No `ORDER BY` feeding a row-limit. | SEM-07 | No | — | — |

---

## 5. Classification summary

| Classification | Count | Findings |
|---|---|---|
| **AUTO** | 0 | — |
| **FIX** | 0 | — |
| **SME** | 6 | D1 (DEF-07 alias mismatch), D2 (DEF-07 table-name mismatch), S1 (locale-dependent date mask), S2 (template-tag date format), S3 (NULL handling in `IFF`), S4 (CHAR padding drift) |
| **KEEP** | 1 | SNZ-01 template tag (line 17) |

**No mechanical (`AUTO`) fixes are available.** Every actionable finding requires a human/SME decision because (a) no Teradata ground truth was supplied and (b) the two DEF-07 findings are name-reference mismatches that DEF-07 explicitly forbids guessing at.

---

## 6. Open SME questions (carry into Stage 3 as `TODO(SME)`)

1. **D1 — alias vs outer reference (line 12 vs 28).** Should the subquery alias be `IN_DEP_FLIGHT_DT` (matching `tgt.IN_DEP_FLIGHT_DT`), or is `IN_DEP_GMTFLIGHT_FLIGHT_DT` the intended name and the outer `WHERE` reference on line 28 is the typo? **This is the critical gate item** — the statement will not run until resolved.
2. **D2 — target vs anti-join table (line 1 vs 32).** Is `BASE.FLIGHT_FOLDERLINKS` (line 32) a distinct table from the `UPDATE` target `BASE.FLT_FOLDERLINKS` (line 1), or should both reference the same table?
3. **S1 — date mask locale.** Confirm the orchestrator's `S_vw6122_CompareLinksRecordsWithTeradata_Current_date` value format and the session locale for `'DDMONYY'`.
4. **S2 — template-tag value type.** Confirm the env var resolves to a `DDMONYY`-formatted string (not a `DATE` or `YYYY-MM-DD` string).
5. **S3 — NULL handling.** Confirm intended behaviour when `OLD_LINK_EXPIRY_DT` is NULL (the `IFF` currently routes NULL to the `DATEADD` else-branch).
6. **S4 — CHAR padding.** Confirm whether any join/anti-join key (`*_CD`, `*_SFX_CD`) is `CHAR(n)` and whether `TRIM`/`RTRIM` is needed to preserve Teradata `=` semantics.

---

## 7. Table dependency inventory

| Role | Table | Line(s) | Notes |
|---|---|---|---|
| UPDATE target | `BASE.FLT_FOLDERLINKS` (alias `tgt`) | 1 | The table being updated. |
| Source (subquery) | `STAGING.Rtr_DirectFlowOfLinksRecords` | 20 | Drives the `SET` values and the join keys. |
| Anti-join probe | `BASE.FLIGHT_FOLDERLINKS` (alias `x`) | 32 | Probed by `NOT EXISTS`. **Different name from the UPDATE target — see D2.** |

---

## 8. Verdict

**One-line verdict:** The statement is syntactically parseable Snowflake (no residual Teradata, no SFX/FNX/DTX findings) but **will not execute** because of a DEF-07 subquery-alias / outer-reference mismatch (`IN_DEP_GMTFLIGHT_FLIGHT_DT` vs `src.IN_DEP_FLIGHT_DT`, line 12 vs 28); a second DEF-07 table-name mismatch (`FLT_FOLDERLINKS` vs `FLIGHT_FOLDERLINKS`, line 1 vs 32) needs SME confirmation; plus four SEM-06/03 semantic risks flagged `TODO(SME)`. **0 AUTO fixes; 0 FIX fixes; 6 SME findings; 1 KEEP.** No Teradata ground truth was supplied, so no finding can be resolved mechanically — all require SME sign-off.