# Semantic-equivalence rules & explanation policy

Fixing syntax makes a script **run**. This file makes it **mean the same thing**
the original Teradata logic meant, and defines the written explanation that
Stage 6 produces for every script.

## Principle

> A remediation is only complete when the fixed Snowflake statement is provably
> equivalent to the Teradata source for every row, or every intended
> divergence is documented and SME-approved.

When the Teradata original is supplied, it is **ground truth**. We do not
re-derive intent from the buggy Snowflake — we compare against Teradata. When it
is not supplied, semantic intent is inferred from sibling columns / naming
conventions and every inference is flagged `TODO(SME)`.

## Semantic risk catalogue

These parse fine on Snowflake but can change results. Each must be checked and,
if present, corrected and explained.

| ID | Risk | Teradata behavior | Snowflake behavior | Rule |
|---|---|---|---|---|
| SEM-01 | Integer division | `INT / INT` truncates toward zero | `/` returns a decimal | If truncation was the intent, wrap in `FLOOR`/`TRUNC`; else keep `/` and note that results now have decimals. |
| SEM-02 | `QUALIFY` / dedup ordering | `ROW_NUMBER` ties broken by physical order | Same function, but ties are non-deterministic in both | Ensure `ORDER BY` fully determines the winner; if it does not, ordering drift is a real risk → flag. |
| SEM-03 | `CHAR(n)` padding & comparison | Blank-pads; trailing spaces ignored in `=` | No padding; `'A' <> 'A '` | If any predicate/join compares CHAR columns, wrap with `TRIM`/`RTRIM` to preserve Teradata semantics. |
| SEM-04 | Timestamp / timezone | Session TZ, `TIMESTAMP` = no TZ | `TIMESTAMP_NTZ` vs `TIMESTAMP_TZ` differ; session TZ default differs | Pin the session `TIMEZONE`; pick NTZ/TZ to match source. |
| SEM-05 | SET-table dedup | `CREATE SET TABLE` silently drops full-row duplicates on INSERT | `CREATE TABLE` keeps duplicates | Whether a target is SET vs MULTISET lives in its `CREATE TABLE` DDL — **not** in an INSERT-only script, so it cannot be inferred from the SQL alone. **Never assume.** If that DDL is supplied, detect `SET`/`MULTISET` directly. If it is **not** supplied, treat multiple INSERTs into one target — or a `UNION`/`UNION ALL` whose branches all write to one target — as a SET-dedup *signal, not proof*: raise an SME question ("Is `<target>` a SET table?") and classify the finding `SME`. Only once SET is confirmed, port each INSERT as `INSERT INTO tgt ( SELECT … EXCEPT SELECT * FROM tgt )` — never a single cross-branch `UNION`. |
| SEM-06 | Implicit cast / NULL in comparison | Lenient implicit casts | Strict; may error or mismatch | Make casts explicit; verify `NULL` handling in `IN`/`=`. |
| SEM-07 | `NULL` ordering | `NULLS FIRST` default varies | Snowflake: `NULLS LAST` for ASC, `NULLS FIRST` for DESC by default | If `ORDER BY` feeds a `QUALIFY`/`TOP`, a differing NULL position changes which row wins. Make `NULLS FIRST/LAST` explicit. |
| SEM-08 | Empty string vs NULL | Teradata often treats `''` distinctly | Snowflake `''` is a real empty string, not NULL | Check `NULLIF(x,'')` intent survived the conversion. |
| SEM-09 | Aggregate of empty set / `SUM` NULL | Same, but division downstream differs | — | Confirm `COALESCE` around aggregates matches source. |
| SEM-10 | Exchange-rate / lookup join direction | Alias names can lie about direction | — | Verify join key direction against Teradata; a "fixed" alias can hide a real bug. Never rename to "make it read right" without SME. |

## What Stage 6 must produce per script

`06_explain/output/semantic_<name>.md` — a plain-language account a reviewer can
read without opening the SQL:

1. **Purpose** — one paragraph: what the statement does in business terms
   (source tables, target table, the grain of one output row).
2. **Statement-by-statement / clause-by-clause walk-through** — for each major
   block (each CASE, each JOIN, the final dedup), what it computes and *why*.
3. **Semantic checks table** — every `SEM-*` risk: Present? Corrected how?
   Equivalent to Teradata? (Yes / Yes-with-assumption / SME).
4. **Divergences from the original** — anything that is intentionally *not*
   bit-identical, with justification.
5. **Open SME questions** — the `TODO(SME)` items, each phrased as a decision.

This markdown is the source for the semantic panels in `report.html`.

## The explanation is editable and embedded in the SQL

The Stage-6 markdown is the **editable source of truth** — the human reviewer
enriches it before sign-off. It also carries a section 6, **Inline anchors**
(a fenced ```anchors``` block of `MATCH text :: note` lines), which
`06_explain/annotate.py` uses to inject the explanation **as comments** into the
final SQL:

- Purpose (section 1) + Open SME questions (section 5) → a `SEMANTIC
  EXPLANATION` header block in the SQL.
- Each anchor `note` → a `-- SEM ▸ <note>` comment above the first SQL line
  containing its `MATCH text`.

Output is `03_fix/output/<name>_final.sql` (the pure `<name>_fixed.sql` is left
untouched). Regeneration is idempotent — edit the markdown, re-run annotate, and
the SQL comments refresh. Only comments are added, so the statement still parses.
