# Semantic explanation — `SFissuetime`

## 1. Purpose
A full-outer-join staging load that carries both legacy and new flight-leg values.

## 2. Statement walk-through
- The INSERT statement targets a staging table and loads rows from the source relations.
- Each branch or join preserves the original grain of one row per business-key combination.
- The final projection keeps the original column order so downstream consumers see the same layout.

## 3. Semantic checks
| Risk | Present? | Corrected how? |
|---|---|---|
| SEM-01 integer division | No | Not applicable |
| SEM-03 CHAR padding | No | Not applicable |
| SEM-04 timezone handling | No | Not applicable |
| SEM-10 join direction | No | The existing join keys were preserved |

## 4. Divergences from the original
No intentional divergence was introduced. The remediation is limited to documentation and obvious parse-safe corrections.

## 5. Open SME questions
- TODO(SME): confirm the target column order and grain against the downstream staging contract.

## 6. Inline anchors
```anchors
INSERT INTO :: Loads the staging rows into the target table.
FROM :: Reads the source rows used by the statement.
GROUP BY :: Preserves the grouping grain of the branch query.
```
