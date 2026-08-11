# Data-type pitfalls (Snowflake)

The buggy input may declare or rely on types the way Teradata behaved. Even when
the type name is legal in Snowflake, the *behavior* can differ — those are
semantic risks (cross-referenced to SEM-*).

| ID | IN construct | OUT / action | Notes |
|---|---|---|---|
| DTX-01 | `BYTEINT` | `NUMBER(3,0)` | Not a Snowflake type. |
| DTX-02 | `VARCHAR(n) CHARACTER SET LATIN/UNICODE` | `VARCHAR(n)` | Drop the `CHARACTER SET` clause (parse error in Snowflake). |
| DTX-03 | `CHAR(n)` comparisons that depend on blank-padding | Keep `CHAR(n)` but flag | Teradata blank-pads CHAR; Snowflake does not. Trailing-space-sensitive comparisons drift → SEM-03. |
| DTX-04 | `TIMESTAMP(n) WITH TIME ZONE` | `TIMESTAMP_TZ(n)`; plain `TIMESTAMP` → `TIMESTAMP_NTZ(n)` | Choosing the wrong one shifts values → SEM-04. |
| DTX-05 | `PERIOD(DATE)` / `PERIOD(TIMESTAMP)` | Two columns `<col>_start_dt` / `<col>_end_dt` | See SFX-01. |
| DTX-06 | `BYTE(n)` / `VARBYTE(n)` | `BINARY(n)` | |
| DTX-07 | `CLOB` / `BLOB` | `VARCHAR` / `BINARY` (max 16 MB) | Flag if larger objects possible. |
| DTX-08 | `INTERVAL` types / interval arithmetic | Model as `NUMBER` + unit, or `DATEADD`/`DATEDIFF` at query time | Flag for SME. |
| DTX-09 | `DATE FORMAT 'YYYY-MM-DD'` in DDL/CAST | `DATE` (drop FORMAT) | Display formatting belongs in the query/report layer. |
| DTX-10 | Implicit string↔number cast (`'123' + 1`, `col = '007'`) | `TRY_TO_NUMBER(...)` / explicit cast | Snowflake is stricter than Teradata → runtime error or silent mismatch. See SEM-06. |
