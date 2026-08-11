# Function fixes

Legacy/Teradata functions left in the "converted" script that are invalid or
behave differently on Snowflake.

| ID | IN (buggy) | OUT (Snowflake) | Notes |
|---|---|---|---|
| FNX-01 | `ZEROIFNULL(x)` | `COALESCE(x, 0)` | Teradata function; **not defined in Snowflake** → resolution error. |
| FNX-02 | `NULLIFZERO(x)` | `NULLIF(x, 0)` | Same — undefined in Snowflake. |
| FNX-03 | `<date> - <int>` / `<date> + <int>` | `DATEADD('day', ±n, <date>)` | Snowflake accepts date±int, but DATEADD is explicit and safe inside larger expressions. Standardize. |
| FNX-04 | `INDEX(s, sub)` | `POSITION(sub, s)` | Argument order flips. |
| FNX-05 | `OREPLACE(s, a, b)` | `REPLACE(s, a, b)` | |
| FNX-06 | `OTRANSLATE(s, a, b)` | `TRANSLATE(s, a, b)` | |
| FNX-07 | `STRTOK(s, delim, n)` | `SPLIT_PART(s, delim, n)` | |
| FNX-08 | `CAST(x AS DATE FORMAT 'YYYYMMDD')` | `TO_DATE(x, 'YYYYMMDD')` | Format-cast has no Snowflake equivalent. |
| FNX-09 | `x MOD y` | `MOD(x, y)` or `x % y` | |
| FNX-10 | `**` (power) | `POWER(x, y)` | |
| FNX-11 | `LIKE ANY ('a%', 'b%')` | `(x LIKE 'a%' OR x LIKE 'b%')` / `RLIKE` | Expand — `LIKE ANY` list form is Teradata. |
| FNX-12 | `HASHROW` / `HASHBUCKET` / `HASHAMP` | `HASH()` (different algorithm) | Only valid for distribution checks; values differ, never for stored keys. |
| FNX-13 | `TITLE`, `FORMAT` phrases in SELECT | `TO_CHAR(x, 'fmt')` / column alias | Display phrases are invalid in Snowflake SELECT. |
| FNX-14 | `CURRENT_DATE`/`CURRENT_TIMESTAMP` relied on Teradata session TZ | Keep, but pin `TIMEZONE` at account/session level | Behavior identical only if TZ is set. See SEM-04. |
| FNX-15 | `SUBSTRING(s FROM a FOR b)` | `SUBSTR(s, a, b)` | ANSI form works too, but standardize. |

## Division caution (carries a semantic flag)

| FNX-16 | `int_col_a / int_col_b` | Keep `/` **only if** both are truly decimal | Teradata truncates INT/INT; Snowflake returns a decimal. If truncation was intended, use `FLOOR(a/b)` / `TRUNC(a/b)`. **Check every division on integer columns** → SEM-01. |
