# Stage 1 — Analysis: `S_vwxxx_MloadLinksUpdates.snowsql`

**Input:** `00_input/S_vwxxx_MloadLinksUpdates.snowsql` (43 lines, single `UPDATE … FROM (subquery)` statement)
**Teradata ground truth:** none supplied (`00_input/S_vwxxx_MloadLinksUpdates.teradata.sql` does not exist).
**Reviewer guidance:** `07_review/output/review_S_vwxxx_MloadLinksUpdates.md` does not exist.
**Mode:** audit only — no fixes applied in this stage.

---

## 0. SNZ client-layer inventory (`.snowsql`)

This is a `.snowsql` input, so `SNZ-*` rules apply. Per `02_rules/07_snowsql_client.md`,
every `SNZ-*` construct is classified **KEEP** (preserve-as-is context), never
`AUTO`/`FIX`/`SME`, and is **never** a syntax defect.

| ID | Line | Construct | Class |
|---|---|---|---|
| SNZ-01 | 18 | `<% ctx.env.S_vw6122_CompareLinksRecordsWithTeradata_Current_date %>` — template tag embedded inside `TO_DATE(...,'DDMONYY')` | **KEEP** |

**Notes:**
- Exactly **1** template tag (SNZ-01). It sits inside the `IFF(...)` fallback
  branch of the `LINK_EXPIRY_DT` expression (line 18). Per SNZ-01 it must be
  preserved **verbatim** — never inlined, renamed, or requoted. The validator
  masks it via `snowsql_protect.py` (token `__TPL_n__`) before parsing.
- **No** `PUT` (SNZ-02) or `GET` (SNZ-03) commands present.
- **No** `SNZ-04` stage DML (`COPY INTO`, `REMOVE`, `LIST`) present.
- The `.snowsql` extension must be retained on the fixed output so the
  validator's masking path applies (lesson: 2026-07-24 / 2026-07-25).

---

## 1. Column-count / projection check

This is an `UPDATE … FROM (subquery) src`, not an `INSERT … SELECT`, so there is
no INSERT-vs-SELECT positional count to reconcile. Instead the relevant audit is
**subquery projection vs outer references** (SET list, outer WHERE, NOT EXISTS guard).

### Subquery `src` projection (lines 8–20)

| Pos | Expression | Alias (as written) |
|---|---|---|
| 1 | `OLD_LINK_STATION_CD` | `LINK_STATION_CD` |
| 2 | `OLD_IN_ORIGN_STATION_CD` | `IN_ORIGN_STATION_CD` |
| 3 | `OLD_IN_ALN_CD` | `IN_ALN_CD` |
| 4 | `OLD_IN_FLIGHT_NO` | `IN_FLIGHT_NO` |
| 5 | `OLD_IN_FLIGHT_SFX_CD` | `IN_FLIGHT_SFX_CD` |
| 6 | `OLD_IN_DEP_FLIGHT_DT` | **`IN_DEP_GMTFLIGHT_FLIGHT_DT`** ← mismatch |
| 7 | `OLD_LINK_EFFECTIVE_DT` | `LINK_EFFECTIVE_DT` |
| 8 | `IFF(TO_CHAR(OLD_LINK_EXPIRY_DT,'YYYYMMDD') <> '20501231', OLD_LINK_EXPIRY_DT, DATEADD(DAY,-1,TO_DATE('<% … %>','DDMONYY')))` | `LINK_EXPIRY_DT` |
| 9 | `IFF(ACTION_CODE = 'U','Y','N')` | `CURRENT_REC_IND` |

### Outer references to `src.*`

| Line | Reference | Resolves to alias? |
|---|---|---|
| 4 | `src.LINK_EXPIRY_DT` (SET) | ✅ pos 8 |
| 5 | `src.CURRENT_REC_IND` (SET) | ✅ pos 9 |
| 26 | `src.LINK_STATION_CD` | ✅ pos 1 |
| 27 | `src.IN_ORIGN_STATION_CD` | ✅ pos 2 |
| 28 | `src.IN_ALN_CD` | ✅ pos 3 |
| 29 | `src.IN_FLIGHT_NO` | ✅ pos 4 |
| 30 | `src.IN_FLIGHT_SFX_CD` | ✅ pos 5 |
| 31 | **`src.IN_DEP_FLIGHT_DT`** | ❌ alias is `IN_DEP_GMTFLIGHT_FLIGHT_DT` (pos 6) |
| 32 | `src.LINK_EFFECTIVE_DT` | ✅ pos 7 |
| 40 | `src.LINK_EXPIRY_DT` (NOT EXISTS) | ✅ pos 8 |
| 41 | `src.CURRENT_REC_IND` (NOT EXISTS) | ✅ pos 9 |

**Verdict:** 8 of 9 `src.*` references resolve. **One** — `src.IN_DEP_FLIGHT_DT`
(line 31) — does **not** match the subquery alias `IN_DEP_GMTFLIGHT_FLIGHT_DT`
(line 13). This is a **DEF-07** alias/reference mismatch (find/replace drift:
note the doubled `FLIGHT` and `GMT` infix in the alias). See §3.

---

## 2. Syntax errors / residual-Teradata constructs

Scan against `02_rules/01_syntax_fixes.md` (SFX-*) and `02_rules/03_function_fixes.md` (FNX-*):

| Rule | Line | Construct | Present? | Notes |
|---|---|---|---|---|
| SFX-01/02 | — | `CONTAINS` / `OVERLAPS` PERIOD | No | — |
| SFX-03 | — | `QUALIFY` | No | — |
| SFX-04 | — | `SEL` | No | — |
| SFX-05/06/07 | — | `SET`/`MULTISET`/`PRIMARY INDEX`/`COLLECT STATS` | No | No DDL in this file |
| SFX-08 | — | BTEQ dot-commands | No | — |
| SFX-09 | — | `LOCKING … FOR ACCESS` | No | — |
| SFX-10 | — | `(+)` outer join | No | — |
| SFX-11 | — | Unbalanced parens | No | Parens balance |
| SFX-12 | — | Trailing/missing comma | No | — |
| SFX-13 | — | `TOP n` | No | — |
| SFX-14 | — | `MINUS` | No | — |
| SFX-15 | — | `CAST(... FORMAT ...)` | No | — |
| FNX-01/02 | — | `ZEROIFNULL`/`NULLIFZERO` | No | — |
| FNX-03 | 18 | `DATEADD(DAY,-1,...)` | No fix needed | Already Snowflake form (valid) |
| FNX-08 | — | `CAST AS DATE FORMAT` | No | — |
| FNX-13 | 16 | `TO_CHAR(...)` | No fix needed | Valid Snowflake display fn |
| — | 15,20 | `IFF(...)` | No fix needed | Valid Snowflake conditional |

**Procedural-block check (lesson: S_vwxxx_CompareLinksRecordsWithTeradata.snowsql):**
No `LET`/`IF`/`RAISE`/`COMMIT`/`BEGIN … END` Snowflake Scripting block present.
This file is a single declarative `UPDATE` — no SFX-16 trigger.

**Residual-Teradata verdict:** **None.** The SQL body is parse-clean Snowflake.
The only non-SQL token is the SNZ-01 template tag (line 18), which is **not** a
defect (masked by `snowsql_protect.py`).

---

## 3. Defects (`DEF-*`)

| ID | Line | Defect | Class | Notes |
|---|---|---|---|---|
| **DEF-07** | 13 vs 31 | Subquery alias `OLD_IN_DEP_FLIGHT_DT AS IN_DEP_GMTFLIGHT_FLIGHT_DT` (line 13) does not match the outer `WHERE` reference `src.IN_DEP_FLIGHT_DT` (line 31). Classic find/replace drift (doubled `FLIGHT`, `GMT` infix). At runtime Snowflake raises `invalid identifier 'SRC.IN_DEP_FLIGHT_DT'`. | **FIX** | Per the prior lesson (2026-07-24 / 2026-07-25 re-run), the established repair is to **rename the alias** `IN_DEP_GMTFLIGHT_FLIGHT_DT` → `IN_DEP_FLIGHT_DT` (line 13) so it aligns with the outer `WHERE` reference and the `NOT EXISTS` guard `tgt.IN_DEP_FLIGHT_DT` (line 38). Minimal diff: alias only; outer `WHERE` and guard left untouched. DEF-07 normally says "only fix if the Teradata original disproves the reference; otherwise flag → SME," but here the mismatch is an internal inconsistency (the outer scope already uses `IN_DEP_FLIGHT_DT` consistently at lines 31 and 38), so the alias is the outlier — the repair is unambiguous and does not require ground truth. Classify **FIX** with a `TODO(SME)` noting the alias rename. |
| **DEF-07** | 2 vs 33 | `UPDATE` target `BASE.FLT_FOLDERLINKS` (line 2) vs `NOT EXISTS` guard table `BASE.FLIGHT_FOLDERLINKS` (line 33) — different names (`FLT_FOLDERLINKS` vs `FLIGHT_FOLDERLINKS`). | **SME** | Per DEF-07 no-guess policy: do **not** rename either table without ground truth. No `.teradata.sql` and no DDL supplied. Carry forward as `TODO(SME)`: "Is `BASE.FLIGHT_FOLDERLINKS` (line 33) the same table as the `UPDATE` target `BASE.FLT_FOLDERLINKS` (line 2)? If not, is the guard intended to protect a *different* table?" |

No DEF-01 (dup columns), DEF-02 (keyword typo), DEF-03 (unbalanced parens),
DEF-04 (malformed fn), DEF-05 (count mismatch), or DEF-06 (cosmetic alias)
findings.

---

## 4. Semantic risks (`SEM-*`)

| ID | Line(s) | Risk | Present? | Class | Notes |
|---|---|---|---|---|---|
| SEM-01 | — | Integer division truncation | No | — | No `/` on integer columns. |
| SEM-02 | — | `QUALIFY`/dedup tie-break | No | — | No `QUALIFY`/`ROW_NUMBER`. |
| **SEM-03** | 26–32, 34–41 | `CHAR(n)` padding drift on multi-key join + anti-join | Yes (suspected) | **SME** | The outer `WHERE` (lines 26–32) joins `tgt` to `src` on 7 keys; the `NOT EXISTS` (lines 34–41) anti-joins `BASE.FLIGHT_FOLDERLINKS x` against `tgt` on the same 7 keys plus `LINK_EXPIRY_DT`/`CURRENT_REC_IND`. Several keys are plausibly `CHAR(n)` (`LINK_STATION_CD`, `IN_ORIGN_STATION_CD`, `IN_ALN_CD`, `IN_FLIGHT_SFX_CD`, `CURRENT_REC_IND`). Teradata blank-pads `CHAR(n)` and ignores trailing spaces in `=`; Snowflake does **not** pad → padding differences silently change which rows match/join. No DDL supplied → cannot confirm types. Flag `TODO(SME)`: "Are any of the 9 join/anti-join keys `CHAR(n)`? If so, wrap both sides in `RTRIM()`." |
| **SEM-04** | — | Timestamp / timezone | No | — | No `TIMESTAMP`/`TIMESTAMP_LTZ`/`CURRENT_TIMESTAMP` usage. `TO_DATE(...)` returns `DATE`. |
| **SEM-05** | — | SET-table dedup | No | — | This is a single `UPDATE`, not an `INSERT`/`UNION` into one target. SEM-05 does not fire. (The `NOT EXISTS` is an explicit anti-join guard in the SQL itself, not an implicit SET-table dedup.) |
| **SEM-06** | 18 | Implicit cast / locale-dependent date mask | Yes | **SME** | `TO_DATE('<% … %>','DDMONYY')` — the `'DDMONYY'` mask is locale-dependent (`MON` resolves against the session locale). With no Teradata ground truth, the source date format and session locale cannot be verified. Also the template value's actual format is unknown until orchestrator resolution. Flag `TODO(SME)`: "Confirm the orchestrator-supplied date matches `'DDMONYY'` and the session locale matches the source." (Cross-ref DTX-09 / proposed OBS-01 locale-dependent mask.) |
| SEM-07 | — | `NULL` ordering in `ORDER BY` feeding `QUALIFY`/`TOP` | No | — | No `ORDER BY`/`QUALIFY`. |
| **SEM-08** | 16, 20 | Empty-string vs NULL handling | Yes (suspected) | **SME** | `IFF(TO_CHAR(OLD_LINK_EXPIRY_DT,'YYYYMMDD') <> '20501231', …)` — if `OLD_LINK_EXPIRY_DT` is NULL, `TO_CHAR(NULL)` returns NULL, and `NULL <> '20501231'` evaluates to NULL (not TRUE), so the `IFF` falls to the false-branch (`DATEADD(...)`). Confirm this NULL path matches Teradata intent. Likewise `IFF(ACTION_CODE = 'U','Y','N')` (line 20): if `ACTION_CODE` is NULL, `= 'U'` is NULL → false-branch `'N'`. Flag `TODO(SME)` on both `IFF` NULL-handling paths. |
| SEM-09 | — | Aggregate of empty set / `SUM` NULL | No | — | No aggregates. |
| **SEM-10** | 26–32 | Join-key grain / direction | Yes (suspected) | **SME`** | The outer `WHERE` joins `tgt`↔`src` on 7 keys. Without DDL/ground truth, cannot prove the `src` staging aliases (`OLD_*`) are the same grain as the `tgt` BASE columns. The `OLD_IN_DEP_FLIGHT_DT` alias drift (DEF-07) is itself a grain-direction signal. Flag `TODO(SME)`: "Confirm the 7 `OLD_*` staging columns map 1:1 to the `tgt` BASE columns by grain." |

**SEM-05 note:** No `CREATE TABLE` DDL is supplied for `BASE.FLT_FOLDERLINKS`,
but SEM-05 does not apply to a single `UPDATE` (it is an INSERT/UNION-into-one-
target signal). No SME question raised for SET vs MULTISET here.

---

## 5. Classification summary

| Class | Count | Items |
|---|---|---|
| **KEEP** | 1 | SNZ-01 template tag (line 18) |
| **AUTO** | 0 | — |
| **FIX** | 1 | DEF-07 alias rename `IN_DEP_GMTFLIGHT_FLIGHT_DT` → `IN_DEP_FLIGHT_DT` (line 13) |
| **SME** | 5 | DEF-07 table-name mismatch (line 2 vs 33); SEM-03 CHAR padding; SEM-06 locale mask; SEM-08 NULL/empty-string in `IFF`; SEM-10 join-key grain |

**Residual-Teradata constructs:** 0 (parse-clean Snowflake body).
**Mechanical fixes required:** 1 (the DEF-07 alias rename).
**Open SME gate items:** 5 (await DDL / Teradata ground truth / reviewer).

---

## 6. Table dependency inventory

| Role | Table | Schema | Lines |
|---|---|---|---|
| UPDATE target | `FLT_FOLDERLINKS` | `BASE` | 2 |
| Source (subquery `src`) | `Rtr_DirectFlowOfLinksRecords` | `STAGING` | 22 |
| NOT EXISTS guard | `FLIGHT_FOLDERLINKS` | `BASE` | 33 |

**One-line verdict:** Single `UPDATE … FROM (subquery)` with a `NOT EXISTS`
anti-join guard. Parse-clean Snowflake body; one internal alias/reference
mismatch (DEF-07, FIX) and one table-name inconsistency in the guard (DEF-07,
SME). Five semantic risks (SEM-03/06/08/10 + the table-name SME) await DDL /
ground-truth confirmation. The SNZ-01 template tag is preserved verbatim.

---

## 7. Notes for Stage 3 (fix)

1. **DEF-07 alias (FIX):** Rename line 13 alias
   `IN_DEP_GMTFLIGHT_FLIGHT_DT` → `IN_DEP_FLIGHT_DT`. Do **not** touch the outer
   `WHERE` (line 31) or the `NOT EXISTS` guard (line 38) — they already use
   `IN_DEP_FLIGHT_DT`. Minimal diff = 1 token. Add `TODO(SME)` noting the rename.
2. **DEF-07 table name (SME):** Do **not** rename `BASE.FLIGHT_FOLDERLINKS`
   (line 33) or `BASE.FLT_FOLDERLINKS` (line 2). Add `TODO(SME)` asking whether
   they are the same table.
3. **SNZ-01 (KEEP):** Leave the `<% ctx.env.S_vw6122_…_Current_date %>` tag
   verbatim on line 18. Add a `[KEEP] SNZ-01` line to the FIX LOG.
4. **SEM markers:** Add inline `TODO(SME)` markers at SEM-03 (join/anti-join
   keys), SEM-06 (line 18 mask), SEM-08 (lines 16, 20 `IFF` NULL paths), and
   SEM-10 (join-key grain).
5. **Extension:** Fixed output must be `S_vwxxx_MloadLinksUpdates.snowsql`
   (preserve `.snowsql` for validator masking).
6. **No procedural blocks:** No SFX-16 commenting needed.