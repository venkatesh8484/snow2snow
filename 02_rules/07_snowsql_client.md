# SnowSQL client layer — `SNZ-*`

Applies **only** to inputs with the `.snowsql` extension. These are SnowSQL
scripts: mostly ordinary Snowflake SQL, plus a thin client/orchestration layer
that is **not** plain SQL. Policy for that layer is **preserve as-is** — the
fixer never rewrites it; it is masked for mechanical validation and restored
byte-for-byte.

- **IN/OUT are identical** for every `SNZ-*` construct — that is the point.
- The mechanical masking is done by `snowsql_protect.py` (wired into
  `04_validate/validate.py`). The rules below tell the **analyze** and **fix**
  agents how to treat these constructs so they match the validator's behaviour.
- A plain `.sql` input has none of this — these rules simply don't fire.

| ID | Construct | Example | Policy |
|---|---|---|---|
| `SNZ-01` | Template placeholder | `<% ctx.env.LANDING_STAGE %>` | **Preserve verbatim.** Resolved by the orchestrator at run time, not by Snowflake. Never inline a value, rename, requote, or "fix" it. It masks to a bare token (`__TPL_n__`) for parsing only. |
| `SNZ-02` | `PUT` command | `PUT file://<% ctx.env.DIR %> @stage OVERWRITE=TRUE` | **Preserve verbatim.** SnowSQL-CLI-only local→stage upload. Not runnable through a plain SQL connection; not a defect. Do not convert to `COPY`. |
| `SNZ-03` | `GET` command | `GET @stage/out.csv file://<% ctx.env.OUT %>` | **Preserve verbatim.** SnowSQL-CLI-only stage→local download. Same treatment as `SNZ-02`. |
| `SNZ-04` | Stage DML | `COPY INTO … FROM @stage`, `REMOVE @stage/…`, `LIST @stage` | **Valid Snowflake SQL — treat normally.** These parse and run server-side; remediate their SQL bodies (e.g. the SELECT inside `COPY INTO @stage FROM (…)`) under the usual `SFX-*/FNX-*/DEF-*/SEM-*` rules. Only the `@stage`/`file://` targets and any `<% %>` inside them are preserved (`SNZ-01`). |

## Analyze stage (`01_analyze`)

- **Inventory** every `SNZ-*` construct with line numbers, but classify it
  `KEEP` (a preserve-as-is item), **not** `AUTO`/`FIX`/`SME`. It is context to
  respect, not a finding to repair.
- A `<% %>` tag or a `PUT`/`GET` line is **never** a syntax defect — do not
  report it as "unparseable" or "invalid on Snowflake".
- SQL *inside* an `SNZ-04` statement is analysed normally.

## Fix stage (`03_fix`)

- **Do not modify any `SNZ-01/02/03` text.** Leave template tags and PUT/GET
  commands exactly as written, in place. Do not reorder them.
- Fix only the real SQL (including the SQL body of `SNZ-04` stage statements).
- In the `FIX LOG`, add one `[KEEP] SNZ-0x` line per distinct preserved
  construct so the reviewer sees it was seen and deliberately left alone. `KEEP`
  lines are no-ops and are **not** counted as issues fixed.

## Report stage (`05_report`)

- State the counts, e.g. *"N template tags (SNZ-01) and M PUT/GET commands
  (SNZ-02/03) detected and preserved verbatim; not remediated."*

> **Why preserve and not resolve?** The template values live in the
> orchestrator's environment, and `PUT`/`GET` are part of the CLI job wiring.
> Flattening them here would break the job and lose the parameterisation. If a
> future task needs a flattened, portable `.sql` (values inlined, includes
> expanded), that is a separate mode — add `SNZ-1x` rules for it; do not do it
> under preserve-as-is.
