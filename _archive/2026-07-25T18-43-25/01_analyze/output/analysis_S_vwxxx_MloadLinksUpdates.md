# Stage 1 — Analysis: `S_vwxxx_MloadLinksUpdates.snowsql`

**Input:** `00_input/S_vwxxx_MloadLinksUpdates.snowsql`
**Teradata ground truth:** Not supplied (no `S_vwxxx_MloadLinksUpdates.teradata.sql` in `00_input/`).
**File type:** `.snowsql` — SnowSQL client layer rules (`SNZ-*`) apply.
**Statement type:** Single `UPDATE … FROM (SELECT …) …` — no `INSERT … SELECT`, so the column-count check is N/A (see §1).

---

## 1. Column-count check

This file contains **no `INSERT … SELECT`** statement. It is a single
`UPDATE … SET … FROM (subquery) src WHERE …` statement. The column-count check
(INSERT target cols vs SELECT expressions) is therefore **not applicable**.

For completeness, the `UPDATE … SET` clause sets **2 target columns**:

| # | Target column | Source expression |
|---|---|---|
| 1 | `LINK_EXPIRY_DT`  | `src.LINK_EXPIRY_DT`  (line 4) |
| 2 | `CURRENT_REC_IND` | `src.CURRENT_REC_IND` (line 5) |

Both are produced by the `src` subquery (lines 19–20), so the SET ↔ source
mapping is balanced (2 = 2). No duplicate columns on either side.

**Verdict:** ✅ Balanced — no column-count defect.

---

## 2. Syntax errors / residual-Teradata constructs

| # | Line | Construct | Rule | Why invalid / action | Class |
|---|---|---|---|---|---|
| 2.1 | 18 | `DATEADD(DAY,-1,TO_DATE('<% ctx.env.…Current_date %>','DDMONYY'))` — the **date format mask** `'DDMONYY'` | **DTX-09 / FNX-08** (candidate) | `TO_DATE(x, 'DDMONYY')` is *valid Snowflake syntax* (it parses), but the mask `'DDMONYY'` is a **Teradata-style format**. Snowflake date-format tokens differ: Snowflake uses `'DDMONYY'` → actually Snowflake *does* accept `DD`, `MON`, `YY` tokens, so this may parse. However, the template tag `<% ctx.env.…Current_date %>` (SNZ-01) is the *value* — the format mask applies to whatever string the orchestrator injects. The mask must match the injected string's actual format. **Flag as SME**: confirm the injected `Current_date` value is in `DDMONYY` form (e.g. `24JUL26`). If the orchestrator emits a different format (e.g. `YYYY-MM-DD`), this will silently return NULL or wrong dates. | **SME** |
| 2.2 | 16 | `TO_CHAR(OLD_LINK_EXPIRY_DT,'YYYYMMDD')` | — | Valid Snowflake. No residual-Teradata construct. The `'YYYYMMDD'` mask is standard Snowflake. No action. | — |
| 2.3 | 15, 20 | `IFF(...)` | — | `IFF` is valid Snowflake (inline conditional). Not a Teradata leftover. No action. | — |
| 2.4 | 17 | `DATEADD(DAY,-1,…)` | FNX-03 (candidate) | `DATEADD(DAY,-1,…)` is already the recommended Snowflake form per FNX-03. No change needed. | — |

**No residual Teradata keywords found.** Scanned for: `ZEROIFNULL`,
`NULLIFZERO`, `CONTAINS`, `OVERLAPS`, `SEL`, `SET`/`MULTISET` (as DDL),
`PRIMARY INDEX`, `COLLECT STATS`, BTEQ dot-commands, `(+)`, `MINUS`, `TOP`,
`CAST(... FORMAT ...)`, `INDEX(`, `OREPLACE`, `OTRANSLATE`, `STRTOK`, `MOD` as
infix, `**` — **none present.**

---

## 3. Defects (DEF-*)

| # | Line | Defect | Rule | Notes | Class |
|---|---|---|---|---|---|
| 3.1 | 13 | `OLD_IN_DEP_FLIGHT_DT AS IN_DEP_GMTFLIGHT_FLIGHT_DT` — alias name looks malformed / inconsistent with the join key used in the outer `WHERE` | **DEF-07** (candidate) | The subquery aliases `OLD_IN_DEP_FLIGHT_DT` as `IN_DEP_GMTFLIGHT_FLIGHT_DT` (note the doubled `FLIGHT` and the `GMT` infix). But the outer `WHERE` (line 29) joins on `tgt.IN_DEP_FLIGHT_DT = src.IN_DEP_FLIGHT_DT` — yet the subquery **does not produce** a column named `IN_DEP_FLIGHT_DT`; it produces `IN_DEP_GMTFLIGHT_FLIGHT_DT`. This means `src.IN_DEP_FLIGHT_DT` on line 29 will **fail to resolve** (Snowflake error: `invalid identifier 'SRC.IN_DEP_FLIGHT_DT'`). This is a genuine defect — either the alias on line 13 should be `IN_DEP_FLIGHT_DT` (matching the target join key), or the outer `WHERE` should reference `src.IN_DEP_GMTFLIGHT_FLIGHT_DT`. Without the Teradata ground truth we cannot decide which side is correct. | **SME** |
| 3.2 | 13 | Same line — alias `IN_DEP_GMTFLIGHT_FLIGHT_DT` vs target column `tgt.IN_DEP_FLIGHT_DT` (line 29) | **DEF-07** | The target table `BASE.FLT_FOLDERLINKS` join column is `IN_DEP_FLIGHT_DT` (line 29, `tgt.IN_DEP_FLIGHT_DT`). The source alias does not match. This is the same defect as 3.1 viewed from the join-key alignment angle. | **SME** |
| 3.3 | 39 | `x.IN_DEP_FLIGHT_DT = tgt.IN_DEP_FLIGHT_DT` (inside NOT EXISTS) | — | The NOT EXISTS subquery references `tgt.IN_DEP_FLIGHT_DT`, which is a real target column — this is fine *if* the target table has that column. The issue is only on the `src` side (line 29). No separate defect here. | — |

**No DEF-01 (duplicate columns), DEF-02 (typo keyword), DEF-03 (unbalanced
parens), DEF-04 (malformed function call), DEF-05 (INSERT/SELECT count
mismatch), or DEF-06 (alias ≠ target name in INSERT) found.**

---

## 4. Semantic risks (SEM-*)

| # | Line(s) | Risk | Rule | Present? | Notes | Class |
|---|---|---|---|---|---|---|
| 4.1 | 16 | `TO_CHAR(OLD_LINK_EXPIRY_DT,'YYYYMMDD') <> '20501231'` — string comparison of formatted date | **SEM-03** (CHAR padding) / **SEM-06** (implicit cast) | Possibly | The comparison is `VARCHAR <> VARCHAR` literal — no CHAR padding issue (both sides are `TO_CHAR` output / literal). `20501231` is a fixed 8-char string; `TO_CHAR(...,'YYYYMMDD')` is also 8 chars. Low risk. No action needed beyond noting it. | — |
| 4.2 | 18 | `TO_DATE('<% ctx.env.…Current_date %>','DDMONYY')` — date construction from a template-injected string | **SEM-06** (implicit/explicit cast) / **SEM-04** (TZ, if timestamp) | Present | The injected value's format must match `'DDMONYY'`. If the orchestrator emits e.g. `2026-07-24` or `07/24/2026`, `TO_DATE` returns NULL (Snowflake returns NULL on format mismatch, not an error). This silently produces wrong `LINK_EXPIRY_DT` values. **Must confirm the injected date format with the orchestrator/owner.** | **SME** |
| 4.3 | 18 | `DATEADD(DAY,-1, TO_DATE(...))` — "one day before the run date" semantics | — | Present | Business logic: if the old expiry was the sentinel `20501231`, set the new expiry to `run_date - 1`. This is the standard "close out the old row" pattern. Semantically clear; the only risk is the date-format mismatch (4.2). | — |
| 4.4 | 24–30, 34–40 | Join keys: `LINK_STATION_CD`, `IN_ORIGN_STATION_CD`, `IN_ALN_CD`, `IN_FLIGHT_NO`, `IN_FLIGHT_SFX_CD`, `IN_DEP_FLIGHT_DT`, `LINK_EFFECTIVE_DT` | **SEM-03** (CHAR padding) | Possibly | If any of these key columns are `CHAR(n)` (not `VARCHAR`) in either `BASE.FLT_FOLDERLINKS` or `STAGING.Rtr_DirectFlowOfLinksRecords`, Teradata would blank-pad and ignore trailing spaces in `=`, while Snowflake does not pad. Without DDL we cannot confirm. Flag for SME to verify column types; if any are `CHAR(n)`, wrap joins in `RTRIM`. | **SME** |
| 4.5 | 31–42 | `NOT EXISTS` anti-join against `BASE.FLIGHT_FOLDERLINKS` | **SEM-10** (join direction) | Low | The NOT EXISTS checks that no row in `FLIGHT_FOLDERLINKS` already has the *new* expiry/indicator values — i.e. prevents creating a duplicate future row. Join direction is clear (all predicates reference `tgt.*` and `src.*`). No direction ambiguity. | — |
| 4.6 | — | **SEM-05 (SET-table dedup)** | — | **Not applicable** | This is an `UPDATE`, not an `INSERT`. SET-table dedup semantics only apply to INSERT targets. No SEM-05 risk. | — |
| 4.7 | — | **SEM-01 (integer division)** | — | Not present | No division in the script. | — |
| 4.8 | — | **SEM-02 (QUALIFY ties)** | — | Not present | No `QUALIFY` / `ROW_NUMBER`. | — |
| 4.9 | — | **SEM-04 (timestamp TZ)** | — | Not present | All date columns are `DATE` (not `TIMESTAMP`). No TZ risk. | — |
| 4.10 | — | **SEM-07 (NULL ordering)** | — | Not present | No `ORDER BY` feeding `QUALIFY`/`TOP`. | — |
| 4.11 | — | **SEM-08 (empty string vs NULL)** | — | Not present | No `''` comparisons. | — |
| 4.12 | — | **SEM-09 (aggregate of empty set)** | — | Not present | No aggregates. | — |

---

## 5. SnowSQL client layer (SNZ-*)

| # | Line | Construct | Rule | Policy | Class |
|---|---|---|---|---|---|
| 5.1 | 18 | `<% ctx.env.S_vw6122_CompareLinksRecordsWithTeradata_Current_date %>` — template placeholder inside `TO_DATE(...)` | **SNZ-01** | **Preserve verbatim.** Resolved by the orchestrator at run time. Never inline a value, rename, or requote. Masks to `__TPL_n__` for parsing. | **KEEP** |

**No `PUT` (SNZ-02), `GET` (SNZ-03), `COPY INTO @stage`, `REMOVE`, or `LIST`
(SNZ-04) commands present.**

The single template tag is the only SnowSQL client-layer construct. It is
context to respect, not a finding to repair.

---

## 6. Finding classification summary

| # | Line(s) | Finding | Rule | Class |
|---|---|---|---|---|
| 2.1 | 18 | `TO_DATE(..., 'DDMONYY')` format mask must match the injected `Current_date` value | DTX-09 / FNX-08 / SEM-06 | **SME** |
| 3.1 | 13, 29 | Subquery alias `IN_DEP_GMTFLIGHT_FLIGHT_DT` does not match outer join key `src.IN_DEP_FLIGHT_DT` → `invalid identifier` resolution error | DEF-07 | **SME** |
| 3.2 | 13, 29 | Same defect — alias vs target join-key name mismatch | DEF-07 | **SME** |
| 4.2 | 18 | Injected date format must match `'DDMONYY'` or `TO_DATE` returns NULL silently | SEM-06 | **SME** |
| 4.4 | 24–30, 34–40 | CHAR(n) padding risk on join keys if any key column is CHAR-typed | SEM-03 | **SME** |
| 5.1 | 18 | `<% ctx.env.…Current_date %>` template tag | SNZ-01 | **KEEP** |

**Counts:** 0 AUTO · 0 FIX · 4 SME · 1 KEEP

---

## 7. Table dependency inventory

| Role | Table / view | Schema | Lines | Notes |
|---|---|---|---|---|
| **Target (UPDATE)** | `FLT_FOLDERLINKS` | `BASE` | 2 | The table being updated. |
| **Source (subquery)** | `Rtr_DirectFlowOfLinksRecords` | `STAGING` | 21 | Driving source for the update; filtered by `ACTION_CODE IN ('U','B')`. |
| **Anti-join (NOT EXISTS)** | `FLIGHT_FOLDERLINKS` | `BASE` | 33 | Guards against inserting a row that already has the new expiry/indicator. |

**Note:** `BASE.FLT_FOLDERLINKS` (the UPDATE target, line 2) and
`BASE.FLIGHT_FOLDERLINKS` (the NOT EXISTS table, line 33) are **two different
tables** — note the `FLT_` vs `FLIGHT_` prefix. This is likely intentional
(folder-links table vs a flight-level folder-links table), but worth confirming
with the SME that the anti-join should reference a *different* table from the
update target.

---

## 8. Verdict

**One blocking defect (DEF-07): the subquery alias `IN_DEP_GMTFLIGHT_FLIGHT_DT`
(line 13) does not match the outer join key `src.IN_DEP_FLIGHT_DT` (line 29),
which will cause a Snowflake `invalid identifier` resolution error. The fix is
either renaming the alias to `IN_DEP_FLIGHT_DT` or updating the outer WHERE to
reference `src.IN_DEP_GMTFLIGHT_FLIGHT_DT` — but the correct choice requires the
Teradata ground truth or DDL, so it is classified SME. Beyond that, the script
is mechanically clean (no residual Teradata, no column-count issue, no
unbalanced parens); the remaining SME items are the injected-date format mask
(`DDMONYY`) and a possible CHAR-padding risk on join keys. The single `<% %>`
template tag (SNZ-01) is preserved verbatim.**