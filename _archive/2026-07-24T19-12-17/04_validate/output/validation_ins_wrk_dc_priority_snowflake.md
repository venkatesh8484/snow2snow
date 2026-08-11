# Validation — `ins_wrk_dc_priority_snowflake`

## Final SQL
```text
PASS  parse: 1 statement(s) parsed as snowflake
PASS  stmt 1: INSERT columns (131) == SELECT expressions (131)
PASS  stmt 1: no duplicate INSERT columns
PASS  no residual Teradata constructs
INFO  TODO(SME) markers outstanding: 5
------------------------------------------------------------
RESULT: PASS
```

## Buggy input control
```text
FAIL  parse: Expecting ). Line 218, Col: 12.
           ) * 4
                ,0
            ) + best_sa.cou_no
        ) BETWEEN 1 AND 16
        [4mTHEN[0m (
            COALESCE(
                (
                    (CAST((best_sa.dc_no, 0, 9999999999) 
FAIL  residual Teradata constructs: 4 found
        line 164: ZEROIFNULL (Teradata) -> COALESCE(x,0)  [FNX-01]
        line 165: ZEROIFNULL (Teradata) -> COALESCE(x,0)  [FNX-01]
        line 451: PERIOD CONTAINS (Teradata) -> BETWEEN   [SFX-01]
        line 456: PERIOD CONTAINS (Teradata) -> BETWEEN   [SFX-01]
INFO  TODO(SME) markers outstanding: 0
------------------------------------------------------------
RESULT: FAIL (2 hard check(s))
```
