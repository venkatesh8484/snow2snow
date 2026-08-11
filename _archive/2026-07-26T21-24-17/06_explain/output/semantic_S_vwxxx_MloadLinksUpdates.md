# Stage 6 — Semantic explanation: `S_vwxxx_MloadLinksUpdates`

**Fixed SQL:** `03_fix/output/S_vwxxx_MloadLinksUpdates_fixed.snowsql`
**Analysis:** `01_analyze/output/analysis_S_vwxxx_MloadLinksUpdates.md`
**Teradata ground truth:** **Not supplied.** No `S_vwxxx_MloadLinksUpdates.teradata.sql` exists in `00_input/`. Every semantic inference below is therefore flagged `TODO(SME)` — no finding can be resolved mechanically without ground truth.

---

## 1. Purpose

This is a **multi-key `UPDATE … FROM (subquery)` with a `NOT EXISTS` anti-join guard** — the "Updates" leg of a Teradata-style MultiLoad link-records pipeline. It refreshes existing rows in the target link table `BASE.FLT_FOLDERLINKS` (alias `tgt`) from a staging stream `STAGING.Rtr_DirectFlowOfLinksRecords` (alias `src`), but only for staging rows whose `ACTION_CODE` is `'U'` (update) or `'B'` (both update + insert). For each matched target row it sets two columns: `LINK_EXPIRY_DT` (recomputed from the staging `OLD_LINK_EXPIRY_DT`, with a "far-future sentinel" `20501231` rewritten to "current date − 1") and `CURRENT_REC_IND` (driven to `'Y'` for updates, `'N'` otherwise). The `NOT EXISTS` guard suppresses the update whenever an *already-correct* row already exists in `BASE.FLIGHT_FOLDERLINKS` (alias `x`) — i.e. it prevents re-applying an update that would produce a duplicate of an existing link record. The grain of one update is **one target link row per staging update-row**, keyed on the 7-column link identity (`LINK_STATION_CD`, `IN_ORIGN_STATION_CD`, `IN_ALN_CD`, `IN_FLIGHT_NO`, `IN_FLIGHT_SFX_CD`, `IN_DEP_FLIGHT_DT`, `LINK_EFFECTIVE_DT`).

---

## 2. Clause-by-clause walk-through

### 2.1 `UPDATE BASE.FLT_FOLDERLINKS tgt` (line 1)
The update target is the link-folder table `BASE.FLT_FOLDERLINKS`, aliased `tgt`. Only two columns are mutated (see 2.4); the 7-column link identity is the join key and is **not** changed.

> **Divergence from the buggy input:** none here — the target table name is unchanged. Note the **DEF-07 table-name mismatch** with the `NOT EXISTS` probe (2.5): the target is `FLT_FOLDERLINKS` but the guard probes `FLIGHT_FOLDERLINKS`. This is *not corrected* (DEF-07 forbids guessing a rename) and is flagged `TODO(SME)`.

### 2.2 `SET LINK_EXPIRY_DT = src.LINK_EXPIRY_DT, CURRENT_REC_IND = src.CURRENT_REC_IND` (lines 2–4)
Both mutated columns are taken verbatim from the subquery `src`. The subquery (2.3) is where the actual computation happens; the `SET` simply projects `src`'s computed values onto `tgt`.

### 2.3 `FROM ( SELECT … FROM STAGING.Rtr_DirectFlowOfLinksRecords WHERE ACTION_CODE IN ('U','B') ) src` (lines 5–22)
The driving subquery reshapes each staging row into the shape the update needs:

- **Identity projection (lines 7–13):** the seven `OLD_*` staging columns are aliased to the canonical link-identity names (`LINK_STATION_CD`, `IN_ORIGN_STATION_CD`, `IN_ALN_CD`, `IN_FLIGHT_NO`, `IN_FLIGHT_SFX_CD`, `IN_DEP_FLIGHT_DT`, `LINK_EFFECTIVE_DT`). These become the join keys in 2.4.
  - **DEF-07 alias fix (line 13):** the buggy input aliased `OLD_IN_DEP_FLIGHT_DT` to `IN_DEP_GMTFLIGHT_FLIGHT_DT`, but the outer `WHERE` (line 29) and the `NOT EXISTS` guard (line 39) both reference `src.IN_DEP_FLIGHT_DT` / `tgt.IN_DEP_FLIGHT_DT`. That mismatch would raise Snowflake `invalid identifier 'SRC.IN_DEP_FLIGHT_DT'` at run time. The fix restores the alias to `IN_DEP_FLIGHT_DT` — the **minimal-diff** choice (align the alias to the target join key rather than rewrite the outer `WHERE`). This is the one mechanical change in the file and it is gated by `TODO(SME)` because, per DEF-07, the *other* repair (rename the outer reference and keep the long alias) is equally plausible without ground truth.
- **`LINK_EXPIRY_DT` computation (lines 15–19):** an `IFF` rewrites the staging `OLD_LINK_EXPIRY_DT`. If its `YYYYMMDD` string form is **not** the far-future sentinel `'20501231'`, the original expiry is kept; otherwise it is replaced with `DATEADD(DAY, -1, TO_DATE('<% ctx.env.S_vw6122_CompareLinksRecordsWithTeradata_Current_date %>', 'DDMONYY'))` — i.e. "the orchestrator's current date, minus one day." This is the standard Teradata pattern of treating `2050-12-31` as "open-ended / no expiry" and converting it to a concrete "yesterday" boundary on update.
  - **SEM-06 / DTX-09 (line 18):** the `TO_DATE(..., 'DDMONYY')` mask is locale-dependent (`MON` is case- and locale-sensitive in Snowflake) and assumes the orchestrator emits `Current_date` in `DDMONYY` form (e.g. `24JUL26`). Kept as-is; flagged `TODO(SME)`.
  - **SEM-06 / SEM-08 (line 17):** `TO_CHAR(OLD_LINK_EXPIRY_DT,'YYYYMMDD') <> '20501231'` returns **NULL** (not TRUE) when `OLD_LINK_EXPIRY_DT` is NULL, so a NULL expiry routes to the `DATEADD` else-branch — i.e. a NULL staging expiry becomes "current date − 1", not "kept as NULL". Whether that is the intended NULL handling is unknown without ground truth; flagged `TODO(SME)`.
- **`CURRENT_REC_IND` (line 20):** `IFF(ACTION_CODE = 'U', 'Y', 'N')` — `'Y'` for pure updates, `'N'` for `'B'` (both) rows. Combined with the `WHERE ACTION_CODE IN ('U','B')` filter (line 21), only update-ish staging rows survive; pure inserts (`'I'`) are handled by the sibling `S_vwxxx_MloadLinksInserts` script, not here.

> **Divergence from the buggy input:** the only change inside the subquery is the **DEF-07 alias rename** on line 13 (`IN_DEP_GMTFLIGHT_FLIGHT_DT` → `IN_DEP_FLIGHT_DT`). Everything else — the `IFF`, the `DATEADD`, the `TO_DATE` mask, the `ACTION_CODE` filter — is preserved verbatim, including the SNZ-01 template tag.

### 2.4 Outer `WHERE` join (lines 23–29)
`tgt` is matched to `src` on the full 7-column link identity. This is an equi-join on all seven keys; each surviving `tgt` row is updated exactly once per matching `src` row.

- **SEM-03 (lines 24–30):** several keys (`*_CD`, `*_SFX_CD`) are plausibly `CHAR(n)`. Teradata blank-pads `CHAR(n)` and ignores trailing spaces in `=`; Snowflake does **not** pad, so `'A' <> 'A '`. If any key is `CHAR(n)`, the join can silently drop matches that Teradata would have made. Not corrected (no DDL supplied); flagged `TODO(SME)` to wrap in `RTRIM` if any key is CHAR-typed.

### 2.5 `AND NOT EXISTS ( SELECT 1 FROM BASE.FLIGHT_FOLDERLINKS x WHERE … )` (lines 30–42)
The anti-join guard. For each candidate update, it checks whether a row with the **same 7-key identity plus the *new* `LINK_EXPIRY_DT` and `CURRENT_REC_IND`** already exists in `BASE.FLIGHT_FOLDERLINKS`. If such a row exists, the update is suppressed (it would only recreate an already-present record). This is the idempotency / no-duplicate guard typical of MultiLoad "apply only if it changes something" logic.

- **DEF-07 (line 32):** the guard probes `BASE.FLIGHT_FOLDERLINKS`, a **different table name** from the update target `BASE.FLT_FOLDERLINKS` (line 1). This may be intentional (a separate "current-state" table used as the dedup reference) or a copy-paste typo from a sibling script. Per DEF-07, **not corrected** — never guess a table rename. Flagged `TODO(SME)`.
- **SEM-03 (lines 34–40):** the same CHAR-padding risk applies to the anti-join keys; same `TODO(SME)` as 2.4.

### 2.6 SNZ-01 template tag (line 18)
`<% ctx.env.S_vw6122_CompareLinksRecordsWithTeradata_Current_date %>` is a SnowSQL orchestrator template tag. Per `02_rules/07_snowsql_client.md` (SNZ-01) it is **preserved verbatim** — never rewritten, never reported as a syntax defect. Mechanical validation masks it via `snowsql_protect.py`. This is a `KEEP`, not a fix.

---

## 3. Semantic checks table

Every `SEM-*` risk from `02_rules/05_semantic_rules.md`, assessed against this statement. "Equivalent to Teradata?" is necessarily **SME** for every present risk because no Teradata ground truth was supplied.

| ID | Risk | Present? | Corrected how? | Equivalent to Teradata? |
|---|---|---|---|---|
| SEM-01 | Integer division | No | N/A — no `/` division in the statement. | N/A |
| SEM-02 | `QUALIFY` / dedup ordering | No | N/A — no `QUALIFY`/`ROW_NUMBER`. | N/A |
| SEM-03 | `CHAR(n)` padding & comparison | **Yes (plausible)** — join keys (lines 24–30) and anti-join keys (lines 34–40) may be `CHAR(n)`. | **Not corrected** — no DDL supplied. Flagged `TODO(SME)`: wrap keys in `RTRIM` if any is `CHAR(n)`. | **SME** |
| SEM-04 | Timestamp / timezone | No | N/A — only `DATE` / date arithmetic; no `TIMESTAMP`/`TIMESTAMP_TZ`. | N/A |
| SEM-05 | SET-table dedup | No | N/A — this is an `UPDATE`, not an `INSERT`; SEM-05 is INSERT-only. | N/A |
| SEM-06 | Implicit cast / NULL in comparison | **Yes** — (a) `TO_DATE(...,'DDMONYY')` locale-dependent mask (line 18); (b) `TO_CHAR(OLD_LINK_EXPIRY_DT,'YYYYMMDD') <> '20501231'` returns NULL when the date is NULL, routing NULL to the `DATEADD` else-branch (line 17). | **Not corrected** — kept as-is. (a) Flagged `TODO(SME)` to confirm orchestrator emits `DDMONYY` and session locale (also DTX-09). (b) Flagged `TODO(SME)` to confirm intended NULL handling. | **SME** |
| SEM-07 | `NULL` ordering feeding TOP/QUALIFY | No | N/A — no `ORDER BY` feeding a row-limit. | N/A |
| SEM-08 | Empty string vs NULL | **Yes (related)** — the `<> '20501231'` comparison's NULL-on-NULL-date behaviour (see SEM-06b) is the empty/NULL-edge concern. | **Not corrected** — flagged `TODO(SME)` (same item as SEM-06b). | **SME** |
| SEM-09 | Aggregate of empty set / `SUM` NULL | No | N/A — no aggregates. | N/A |
| SEM-10 | Exchange-rate / lookup join direction | No | N/A — no lookup/rate join. | N/A |

**Net:** 3 SEM risks present (SEM-03, SEM-06, SEM-08), all uncorrected and all **SME** because no ground truth was supplied.

---

## 4. Divergences from the original

There is **no Teradata original** in `00_input/`, so "the original" here means the **buggy Snowflake input** that this fix remediates. Against that input, the fixed file diverges in exactly **one** place:

| # | Location | Buggy input | Fixed file | Justification | Rule |
|---|---|---|---|---|---|
| 1 | Subquery alias, line 13 | `OLD_IN_DEP_FLIGHT_DT AS IN_DEP_GMTFLIGHT_FLIGHT_DT` | `OLD_IN_DEP_FLIGHT_DT AS IN_DEP_FLIGHT_DT` | The buggy alias did not match the outer `WHERE` reference `src.IN_DEP_FLIGHT_DT` (line 29) nor the `NOT EXISTS` guard `x.IN_DEP_FLIGHT_DT = tgt.IN_DEP_FLIGHT_DT` (line 39), which would raise `invalid identifier 'SRC.IN_DEP_FLIGHT_DT'` at run time. Minimal-diff fix: align the alias to the target join key. The alternative (keep the long alias, rename the outer reference) is equally plausible and is **not** chosen — hence `TODO(SME)`. | DEF-07 |

Everything else is **preserved verbatim**, including:
- The `IFF` / `DATEADD` / `TO_DATE('…','DDMONYY')` expiry computation (lines 15–19).
- The `IFF(ACTION_CODE = 'U','Y','N')` current-record indicator (line 20).
- The `WHERE ACTION_CODE IN ('U','B')` filter (line 21).
- The 7-column outer equi-join (lines 23–29).
- The `NOT EXISTS` guard against `BASE.FLIGHT_FOLDERLINKS` (lines 30–42) — **including the `FLT_` vs `FLIGHT_` table-name mismatch**, which is deliberately *not* corrected (DEF-07).
- The SNZ-01 template tag `<% ctx.env.S_vw6122_CompareLinksRecordsWithTeradata_Current_date %>` (line 18), preserved per `02_rules/07_snowsql_client.md`.

**No residual Teradata constructs** (`ZEROIFNULL`, `CONTAINS`, `MULTISET`, `(+)`, BTEQ dot-commands, `MINUS`, `SEL`, …) remain.

---

## 5. Open SME questions

Each is phrased as a decision for a human reviewer. All exist because no Teradata ground truth was supplied.

1. **DEF-07 — alias vs outer reference (line 13 vs 29).** Is `IN_DEP_FLIGHT_DT` the intended column name (matching `tgt.IN_DEP_FLIGHT_DT` and the `NOT EXISTS` guard), confirming the fix applied? Or is `IN_DEP_GMTFLIGHT_FLIGHT_DT` the intended name and the outer `WHERE` reference on line 29 is the typo (in which case the fix should be reverted and the outer reference renamed instead)? **This is the critical gate item — the statement will not run until resolved.**
2. **DEF-07 — target vs anti-join table (line 1 vs 32).** Is `BASE.FLIGHT_FOLDERLINKS` (line 32) a genuinely distinct table from the `UPDATE` target `BASE.FLT_FOLDERLINKS` (line 1), or is it a typo and both should reference the same table?
3. **SEM-06 / DTX-09 — date mask locale (line 18).** Does the orchestrator emit `S_vw6122_CompareLinksRecordsWithTeradata_Current_date` as a `DDMONYY`-formatted string (e.g. `24JUL26`), and is the Snowflake session locale set so that `MON` resolves as expected? If not, the `TO_DATE` mask must be changed.
4. **SEM-06 / SEM-08 — NULL handling for `OLD_LINK_EXPIRY_DT` (line 17).** When `OLD_LINK_EXPIRY_DT` is NULL, `TO_CHAR(...) <> '20501231'` evaluates to NULL, routing the row to the `DATEADD` else-branch (expiry becomes "current date − 1"). Is that the intended behaviour, or should a NULL staging expiry be preserved as NULL (e.g. via `COALESCE` / an explicit NULL branch)?
5. **SEM-03 — CHAR padding in the outer join (lines 24–30).** Are any of the 7 join keys (`LINK_STATION_CD`, `IN_ORIGN_STATION_CD`, `IN_ALN_CD`, `IN_FLIGHT_NO`, `IN_FLIGHT_SFX_CD`, `IN_DEP_FLIGHT_DT`, `LINK_EFFECTIVE_DT`) `CHAR(n)` rather than `VARCHAR`? If so, should the join keys be wrapped in `RTRIM` to preserve Teradata's blank-padded `=` semantics?
6. **SEM-03 — CHAR padding in the anti-join (lines 34–40).** Same question for the `NOT EXISTS` guard keys against `BASE.FLIGHT_FOLDERLINKS` — are any `CHAR(n)`, and should they be `RTRIM`-wrapped?
7. **SEM-03 — `LINK_EXPIRY_DT` / `CURRENT_REC_IND` comparison in the guard (lines 40–41).** The guard also compares `x.LINK_EXPIRY_DT = src.LINK_EXPIRY_DT` and `x.CURRENT_REC_IND = src.CURRENT_REC_IND`. Are these columns `CHAR(n)` (especially `CURRENT_REC_IND`, a 1-char flag), and does the comparison need `RTRIM`?
8. **SEM-06 — sentinel value `'20501231'` (line 17).** Is `2050-12-31` confirmed as the "open-ended / no expiry" sentinel in the source system, and is `YYYYMMDD` the correct string form to compare against?
9. **SEM-06 — `DATEADD(DAY, -1, …)` semantics (line 18).** Is "current date − 1 day" the intended concrete boundary to substitute for the `20501231` sentinel on update, or should it be a different offset (e.g. the link's `LINK_EFFECTIVE_DT − 1`)?
10. **SNZ-01 — template tag binding (line 18).** Confirm the orchestrator variable `S_vw6122_CompareLinksRecordsWithTeradata_Current_date` is populated at run time and resolves to a single date value shared with the sibling `S_vw6122_CompareLinksRecordsWithTeradata` script (the name suggests they share the same `Current_date`).

---

## 6. Inline anchors

```anchors
UPDATE BASE.FLT_FOLDERLINKS tgt :: UPDATE target is BASE.FLT_FOLDERLINKS (alias tgt); only LINK_EXPIRY_DT and CURRENT_REC_IND are mutated. DEF-07: the NOT EXISTS guard probes a differently-named table (BASE.FLIGHT_FOLDERLINKS) — see TODO(SME) Q2.
OLD_IN_DEP_FLIGHT_DT AS IN_DEP_FLIGHT_DT :: DEF-07 alias fix: buggy input aliased this to IN_DEP_GMTFLIGHT_FLIGHT_DT, which did not match the outer WHERE reference src.IN_DEP_FLIGHT_DT (line 29) nor the NOT EXISTS guard (line 39) and would raise 'invalid identifier'. Minimal-diff: align alias to the target join key. TODO(SME) Q1 to confirm intended name.
TO_CHAR(OLD_LINK_EXPIRY_DT,'YYYYMMDD') <> '20501231' :: SEM-06/SEM-08: returns NULL (not TRUE) when OLD_LINK_EXPIRY_DT is NULL, routing NULL expiries to the DATEADD else-branch (expiry becomes 'current date - 1'). TODO(SME) Q4 to confirm intended NULL handling. Q8 confirms 20501231 is the open-ended sentinel.
DATEADD(DAY,-1,TO_DATE('<% ctx.env.S_vw6122_CompareLinksRecordsWithTeradata_Current_date %>','DDMONYY')) :: SEM-06/DTX-09: 'DDMONYY' mask is locale-dependent (MON is case/locale sensitive); assumes the orchestrator emits Current_date in DDMONYY form (e.g. 24JUL26). SNZ-01 template tag preserved verbatim. TODO(SME) Q3 (mask/locale) and Q9 (offset semantics).
IFF(ACTION_CODE = 'U','Y','N') AS CURRENT_REC_IND :: CURRENT_REC_IND is 'Y' for pure updates ('U'), 'N' for 'B' (both) rows. Combined with WHERE ACTION_CODE IN ('U','B'), pure inserts ('I') are excluded (handled by the sibling Inserts script).
WHERE ACTION_CODE IN ('U','B') :: Subquery filter: only update-ish staging rows drive this UPDATE; pure inserts are handled by S_vwxxx_MloadLinksInserts.
WHERE tgt.LINK_STATION_CD       = src.LINK_STATION_CD :: Outer equi-join on the 7-column link identity. SEM-03: if any key is CHAR(n), Teradata blank-pads and Snowflake does not — wrap in RTRIM. TODO(SME) Q5.
AND tgt.IN_DEP_FLIGHT_DT = src.IN_DEP_FLIGHT_DT :: The join key that exposed the DEF-07 alias mismatch (the buggy alias IN_DEP_GMTFLIGHT_FLIGHT_DT did not match this reference).
AND NOT EXISTS ( :: Idempotency guard: suppress the update when an already-correct row exists in BASE.FLIGHT_FOLDERLINKS, preventing duplicate link records.
FROM BASE.FLIGHT_FOLDERLINKS x :: DEF-07: guard probes BASE.FLIGHT_FOLDERLINKS, a different table name from the UPDATE target BASE.FLT_FOLDERLINKS. Not corrected (never guess a rename). TODO(SME) Q2.
AND x.LINK_EXPIRY_DT    = src.LINK_EXPIRY_DT :: Guard also compares the *new* expiry and current-rec-ind, so the update is skipped only if the resulting row already exists verbatim. SEM-03: TODO(SME) Q7 if these are CHAR(n).
```