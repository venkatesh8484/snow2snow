# Stage 1 — Analysis: `S_vwxxx_MloadLinksInserts.snowsql`

**Input:** `00_input/S_vwxxx_MloadLinksInserts.snowsql` (109 lines)
**Type:** `.snowsql` (SnowSQL client layer — SNZ-* rules apply)
**Teradata ground truth:** none supplied (`00_input/S_vwxxx_MloadLinksInserts.teradata.sql` not present). All semantic inferences are flagged `TODO(SME)`.
**Reviewer guidance:** `07_review/output/review_S_vwxxx_MloadLinksInserts.md` not present.
**Archive step:** no-op — no prior `analysis_S_vwxxx_MloadLinksInserts.md` existed (only `SFIssueSET` / `SFissuetime` outputs present).

**Statement shape:** a single `INSERT INTO BASE.FLT_FOLDER_LINKS (33 cols) SELECT … FROM STAGING.ExpFinalyseInserts S WHERE … AND NOT EXISTS (SELECT 1 FROM BASE.FLT_FOLDER_LINKS T WHERE <all 33 columns equated>)`. It is a full-row anti-dup INSERT: a staging row is inserted only if no identical row already exists in the base target.

---

## 1. Column-count check (INSERT target vs SELECT expressions)

| Side | Count | Duplicates | Net |
|---|---|---|---|
| INSERT target columns (lines 2–34) | 33 | 0 | 33 |
| SELECT expressions (lines 37–69) | 33 | 0 | 33 |

**Verdict: 33 = 33 — PASS. No DEF-05 mismatch, no DEF-01 duplicates on either side.**

Position-by-position alias audit (INSERT…SELECT is positional; aliases are cosmetic per DEF-06):

| # | INSERT target (line) | SELECT expr (line) | Alias aligns to target? |
|---|---|---|---|
| 1 | LINK_STATION_CD (2) | NEW_LINK_STATION_CD (37) | yes (NEW_ prefix) |
| 2 | IN_ORIGN_STATION_CD (3) | NEW_IN_ORIGN_STATION_CD (38) | yes |
| 3 | IN_ALN_CD (4) | NEW_IN_ALN_CD (39) | yes |
| 4 | IN_FLT_NO (5) | NEW_IN_FLT_NO_SMALLINT (40) | suffix drift (`_SMALLINT`) — see SEM-06 |
| 5 | IN_FLT_SFX_CD (6) | NEW_IN_FLT_SFX_CD (41) | yes |
| 6 | IN_DEP_FLTDT (7) | NEW_IN_DEP_FLTDT_DATE (42) | suffix drift (`_DATE`) — see SEM-06 |
| 7 | IN_ARR_FLTDT (8) | NEW_IN_ARR_FLTDT_DATE (43) | suffix drift (`_DATE`) — see SEM-06 |
| 8 | IN_ARR_FLTTM (9) | NEW_IN_ARR_FLTTM_DATE (44) | suffix drift (`_DATE` on a `_TTM` slot) — see SEM-06 |
| 9 | IN_PAX_TML_CD (10) | NEW_IN_PAX_TML_CD (45) | yes |
| 10 | IN_GROUND_ACY_CD (11) | NEW_IN_GROUND_ACY_CD (46) | yes |
| 11 | IN_SERVICE_TYP (12) | NEW_IN_SERVICE_TYP (47) | yes |
| 12 | IN_FLT_LEG_SEQ_NO (13) | NEW_IN_FLT_LEG_SEQ_NO (48) | yes |
| 13 | OUT_DESTATION_STATION_CD (14) | NEW_OUT_DESTATION_STATION_CD (49) | yes |
| 14 | OUT_ALN_CD (15) | NEW_OUT_ALN_CD (50) | yes |
| 15 | OUT_FLT_NO (16) | NEW_OUT_FLT_NO_SMALLINT (51) | suffix drift (`_SMALLINT`) — see SEM-06 |
| 16 | OUT_FLT_SFX_CD (17) | NEW_OUT_FLT_SFX_CD (52) | yes |
| 17 | OUT_DEP_FLTDT (18) | NEW_OUT_DEP_FLTDT_DATE (53) | suffix drift (`_DATE`) — see SEM-06 |
| 18 | OUT_DEP_FLTTM (19) | NEW_OUT_DEP_FLTTM_DATE (54) | suffix drift (`_DATE` on a `_TTM` slot) — see SEM-06 |
| 19 | OUT_ARR_FLTDT (20) | NEW_OUT_ARR_FLTDT_DATE (55) | suffix drift (`_DATE`) — see SEM-06 |
| 20 | OUT_PAX_TML_CD (21) | NEW_OUT_PAX_TML_CD (56) | yes |
| 21 | OUT_GROUND_ACY_CD (22) | NEW_OUT_GROUND_ACY_CD (57) | yes |
| 22 | OUT_SERVICE_TYP (23) | NEW_OUT_SERVICE_TYP (58) | yes |
| 23 | OUT_FLT_LEG_SEQ_NO (24) | NEW_OUT_FLT_LEG_SEQ_NO (59) | yes |
| 24 | AIRCRAFT_OWNER_CD (25) | NEW_AIRCRAFT_OWNER_CD (60) | yes |
| 25 | CARRIER_AC_TYP (26) | NEW_CARRIER_AC_TYP (61) | yes |
| 26 | MIDNIGHT_QTY (27) | NEW_MIDNIGHT_QTY_SMALLINT (62) | suffix drift (`_SMALLINT`) — see SEM-06 |
| 27 | BUFFER_DUR (28) | NEW_BUFFER_DUR_SMALLINT (63) | suffix drift (`_SMALLINT`) — see SEM-06 |
| 28 | STD_WORKING_DUR (29) | NEW_STD_WORKING_DUR_SMALLINT (64) | suffix drift (`_SMALLINT`) — see SEM-06 |
| 29 | TOW_TIME_DUR (30) | NEW_TOW_TIME_DUR_SMALLINT (65) | suffix drift (`_SMALLINT`) — see SEM-06 |
| 30 | FIXED_LINK_RSN_TXT (31) | NEW_FIXED_LINK_RSN_TXT (66) | yes |
| 31 | LINK_EFFECTIVE_DT (32) | NEW_LINK_EFFECTIVE_DT (67) | yes |
| 32 | LINK_EXPIRY_DT (33) | NEW_LINK_EXPIRY_DT (68) | yes |
| 33 | CURRENT_REC_IND (34) | NEW_CURRENT_REC_IND (69) | yes |

No DEF-06 alias-normalization defect: every alias is the target name with a `NEW_` prefix (the `_SMALLINT`/`_DATE` suffixes describe the staging cast, not a wrong-name alias). Positional binding is correct.

---

## 2. SnowSQL client layer (SNZ-*) — KEEP inventory

| ID | Line | Construct | Classification |
|---|---|---|---|
| — | — | none | — |

**SNZ inventory is empty.** No `<% ctx.env.X %>` template tags (SNZ-01), no `PUT` (SNZ-02), no `GET` (SNZ-03), and no stage DML / `COPY INTO @stage` / `REMOVE` / `LIST` (SNZ-04) appear in the file. The body is plain Snowflake DML.

> Per `02_rules/07_snowsql_client.md` and the 2026-07-24 lesson: the `.snowsql` extension is **retained** on the fixed output even when the client layer is empty, so the validator's `is_snowsql()` check and `snowsql_protect.py` masking path apply consistently. Dropping the extension would silently change which validation branch runs.

---

## 3. Syntax errors / residual-Teradata constructs (SFX-* / FNX-* / DTX-*)

| ID | Line | Construct | Why invalid on Snowflake | Class |
|---|---|---|---|---|
| — | — | none found | — | — |

**The file is parse-clean Snowflake.** Scanned for and found none of: `CONTAINS`/`OVERLAPS` (SFX-01/02), `SEL` (SFX-04), `SET`/`MULTISET` (SFX-05), `PRIMARY INDEX` (SFX-06), `COLLECT STATS` (SFX-07), BTEQ dot-commands (SFX-08), `LOCKING` (SFX-09), `(+)` outer joins (SFX-10), unbalanced parens (SFX-11), trailing/missing commas (SFX-12), `TOP n` (SFX-13), `MINUS` (SFX-14), `CAST(... FORMAT ...)` (SFX-15/FNX-08), `ZEROIFNULL`/`NULLIFZERO` (FNX-01/02), `INDEX`/`OREPLACE`/`OTRANSLATE`/`STRTOK` (FNX-04/05/06/07), `**`/`MOD` (FNX-09/10), `LIKE ANY` (FNX-11), `HASHROW` (FNX-12), `TITLE`/`FORMAT` phrases (FNX-13), `BYTEINT`/`CHARACTER SET`/`PERIOD`/`BYTE`/`CLOB`/`INTERVAL` types (DTX-01/02/05/06/07/08). No `QUALIFY` present (SFX-03 n/a). No division present (FNX-16/SEM-01 n/a).

---

## 4. Defects (DEF-*)

| ID | Line | Defect | Class |
|---|---|---|---|
| — | — | none found | — |

No DEF-01 (duplicate columns), DEF-02 (keyword typo), DEF-03 (unbalanced parens), DEF-04 (malformed function), DEF-05 (count mismatch — confirmed 33=33 above), DEF-06 (wrong alias — all aliases align positionally), DEF-07 (wrong column reference). The `NOT EXISTS` subquery (lines 73–109) is balanced and its 33 predicates mirror the 33 INSERT/SELECT columns one-for-one.

---

## 5. Semantic risks (SEM-*)

| ID | Line(s) | Risk present | Detail | Class |
|---|---|---|---|---|
| SEM-03 | 76–108 (all 33 `T.col = S.NEW_col` predicates) | **Yes — CHAR(n) padding drift in the full-row anti-join.** | The `NOT EXISTS` equates every column. Several keys are plausibly `CHAR(n)` by naming convention: `*_CD` (LINK_STATION_CD, IN_ALN_CD, IN_FLT_SFX_CD, IN_PAX_TML_CD, IN_GROUND_ACY_CD, OUT_*_CD, AIRCRAFT_OWNER_CD), `*_TYP` (IN_SERVICE_TYP, OUT_SERVICE_TYP, CARRIER_AC_TYP), `*_TXT` (FIXED_LINK_RSN_TXT), `*_IND` (CURRENT_REC_IND). Teradata blank-pads `CHAR(n)` and ignores trailing spaces in `=`; Snowflake does **not** pad, so padding differences silently change which rows the anti-join suppresses — either inserting duplicates (a matching row with trailing-space drift is treated as non-matching) or suppressing valid rows. The mechanical validator cannot detect this without DDL for both `BASE.FLT_FOLDER_LINKS` and `STAGING.ExpFinalyseInserts`. **Requires DDL to confirm which columns are `CHAR(n)` vs `VARCHAR`; if any are `CHAR(n)`, wrap both sides of each such predicate in `RTRIM`/`TRIM`.** | SME |
| SEM-06 / DTX-10 | 40, 42, 43, 44, 51, 53, 54, 55, 62, 63, 64, 65 (SELECT) and 79, 81, 82, 83, 90, 92, 93, 94, 101, 102, 103, 104 (NOT EXISTS predicates) | **Yes — type-suffixed staging aliases compared against unknown BASE column types.** | 12 SELECT aliases carry a `_SMALLINT` or `_DATE` suffix (e.g. `NEW_IN_FLT_NO_SMALLINT`, `NEW_IN_DEP_FLTDT_DATE`, `NEW_IN_ARR_FLTTM_DATE`, `NEW_MIDNIGHT_QTY_SMALLINT`). The suffix describes the *staging* cast, not the target column type. The `NOT EXISTS` predicates then compare these against `BASE.FLT_FOLDER_LINKS` columns whose types are unknown (no DDL supplied). A type mismatch (e.g. `DATE` vs `TIMESTAMP`, `VARCHAR` vs `NUMBER`, `TIME` vs `TIMESTAMP`) could silently change which rows the anti-join suppresses, or raise a strict-cast error at runtime. Note `IN_ARR_FLTTM`/`OUT_DEP_FLTTM`/`OUT_ARR_FLTDT` are time/date slots whose staging alias is `_DATE` — a `TIME`/`TIMESTAMP` vs `DATE` mismatch is plausible. **Requires DDL for both sides to confirm type compatibility. Do not assume the suffix is authoritative.** | SME |
| SEM-04 | 44, 54 (`NEW_IN_ARR_FLTTM_DATE`, `NEW_OUT_DEP_FLTTM_DATE`); target cols `IN_ARR_FLTTM` (9), `OUT_DEP_FLTTM` (19) | **Possible — timezone on time columns.** | The `_TTM` (time) slots are loaded from `_DATE`-suffixed staging values. If the staging cast produced a `TIMESTAMP`/`TIMESTAMP_TZ` and the target is `TIME` or `TIMESTAMP_NTZ`, a session-`TIMEZONE` shift could move values. No explicit `TIMESTAMP_LTZ`/`TIMESTAMP_TZ` function is used, so the risk is indirect and depends on the staging view's cast. **Confirm the staging cast and target type for the `_TTM` columns; pin session `TIMEZONE` or use `TIMESTAMP_NTZ` explicitly if needed.** | SME |
| SEM-05 | 1 (target `BASE.FLT_FOLDER_LINKS`); 73–108 (the `NOT EXISTS` full-row anti-join) | **Considered — SET-table dedup.** | This is a **single** `INSERT` into `BASE.FLT_FOLDER_LINKS` (not multiple INSERTs, not a `UNION`/`UNION ALL` whose branches all write to one target), so the strict SEM-05 trigger does **not** fire. However, the `NOT EXISTS` subquery equates **all 33 columns** — i.e. it is an explicit full-row dedup that emulates Teradata `SET TABLE` "drop rows already present" semantics in Snowflake-native form. The open question is whether `BASE.FLT_FOLDER_LINKS` is itself a SET table: if it is, the `NOT EXISTS` is a belt-and-suspenders duplicate of SET-table dedup (harmless); if it is MULTISET, the `NOT EXISTS` is the **only** dedup mechanism and is load-bearing. No `CREATE TABLE` DDL for the target is supplied, so SET vs MULTISET cannot be decided from the SQL alone. **SME question: "Is `BASE.FLT_FOLDER_LINKS` a SET table?"** If SET, the current `NOT EXISTS` is consistent and no change is needed; if MULTISET, confirm the `NOT EXISTS` is the intended dedup (it appears to be). Either way the SQL is self-consistent — flag for confirmation, do not rewrite. | SME |
| SEM-01 | — | No | No division present. | — |
| SEM-02 | — | No | No `QUALIFY` / `ROW_NUMBER` dedup. | — |
| SEM-07 | — | No | No `ORDER BY` feeding `QUALIFY`/`TOP`. | — |
| SEM-08 | — | No | No `NULLIF(x,'')` / empty-string-vs-NULL logic. | — |
| SEM-09 | — | No | No aggregates / `SUM` of empty set. | — |
| SEM-10 | — | No | The `NOT EXISTS` is an anti-join, not a directional lookup join; no exchange-rate/lookup join direction to verify. | — |

**NULL-guard note (lines 71–72):** `WHERE S.IN_FLT_LEG_SEQ_NO IS NOT NULL AND S.OUT_FLT_LEG_SEQ_NO IS NOT NULL` filters out staging rows with NULL leg-sequence numbers before the anti-join. This is a deliberate guard (NULLs would never match in the `=` predicates anyway, so it primarily prevents inserting rows with NULL keys). Not a defect; no SEM-06 NULL-in-comparison issue arises from these two columns because they are excluded upstream. The remaining 31 columns are **not** NULL-guarded — if any staging value is NULL, the corresponding `T.col = S.NEW_col` predicate evaluates to NULL (not TRUE), so the `NOT EXISTS` treats the row as non-matching and the staging row **is inserted**. This matches standard anti-join NULL semantics and is consistent with full-row dedup only when NULLs are not expected. Flag for SME confirmation that no other key column should be NULL-guarded.

---

## 6. Classification summary

| Class | Count | Findings |
|---|---|---|
| AUTO | 0 | — |
| FIX | 0 | — |
| SME | 4 | SEM-03 (CHAR padding in full-row anti-join), SEM-06/DTX-10 (type-suffixed aliases vs unknown BASE types), SEM-04 (TZ on `_TTM` time columns), SEM-05 (SET vs MULTISET on `BASE.FLT_FOLDER_LINKS`) |
| KEEP | 0 | SNZ inventory empty (`.snowsql` extension retained) |

**No mechanical (AUTO/FIX) fixes are required.** The file parses cleanly on Snowflake with no residual Teradata constructs and no defects. All findings are **semantic** and require DDL for `BASE.FLT_FOLDER_LINKS` and `STAGING.ExpFinalyseInserts` (and/or SME confirmation) to resolve. This is the expected profile for a semantic-only unit — a parse PASS is not correctness (standing lesson).

---

## 7. Table dependency inventory

| Role | Table | Schema | Notes |
|---|---|---|---|
| Target (INSERT) | `FLT_FOLDER_LINKS` | `BASE` | Full-row anti-dup target. SET vs MULTISET unknown (no DDL) → SEM-05 SME. |
| Source (SELECT) | `ExpFinalyseInserts` | `STAGING` | Staging view/table supplying `NEW_*` pre-cast values (`_SMALLINT`/`_DATE` suffixes). Type contract unknown → SEM-06 SME. |
| Anti-join probe | `FLT_FOLDER_LINKS` | `BASE` | Same target, self-referenced as `T` inside `NOT EXISTS`. |

**One-line verdict:** Parse-clean, 33=33 column-aligned full-row anti-dup INSERT; 0 mechanical fixes; 4 open SME semantic risks (CHAR padding, type compatibility, TZ on time columns, SET-vs-MULTISET) all blocked on missing DDL for the base target and staging source.