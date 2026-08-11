# Validation — `SFfixedtime`

## Final SQL
```text
PASS  parse: 1 statement(s) parsed as snowflake
PASS  stmt 1: INSERT columns (60) == SELECT expressions (60)
PASS  stmt 1: no duplicate INSERT columns
PASS  no residual Teradata constructs
INFO  TODO(SME) markers outstanding: 0
------------------------------------------------------------
RESULT: PASS
```

## Buggy input control
```text
FAIL  parse: Invalid expression / Unexpected token. Line 94, Col: 5.
  t_rec_ind,
      o.carrier_ac_typ,
      o.dep_utc_variation_txt,
      o.arr_utc_variation_txt
	  o[4m.[0marr_utc_variation_txt,
      o.sched_src_typ,
      n.seq_no,
      n.operating_airline_cd,
      n.
PASS  no residual Teradata constructs
INFO  TODO(SME) markers outstanding: 0
------------------------------------------------------------
RESULT: FAIL (1 hard check(s))
```
