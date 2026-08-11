# Validation — `SFIssueSET`

## Final SQL (corrected remediation)
```text
PASS  parse: 3 statement(s) parsed as snowflake
PASS  no residual Teradata constructs
INFO  TODO(SME) markers outstanding: 0
------------------------------------------------------------
RESULT: PASS
```

## Note on the buggy input
The delivered `SFIssueSET.sql` **also** parses PASS — that is the whole point.
The defect (SET-table dedup replaced by `UNION`) is **semantic**, so a parser
cannot distinguish good from bad here. A green `parse PASS` on the input is not
evidence the file is correct.

## What still needs a real check
Mechanical parse is not enough for this unit. Before sign-off, run a **data
test** on a staged copy to confirm: (a) rows already in `staging.wrk_target` are
not re-inserted (the `EXCEPT` guard), and (b) row multiplicity across the three
branches matches the Teradata SET-table behaviour.
