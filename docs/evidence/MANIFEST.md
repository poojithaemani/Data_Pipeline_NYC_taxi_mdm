# Evidence manifest

Captured from the live AWS account before decommissioning.
Raw AWS identifiers are still present - run the scrub pass before staging.

| Artifact | Bytes | What it shows |
|---|---:|---|
| `docs/evidence/cloudwatch/alarms.json` | 6,461 | 4 metric alarms |
| `docs/evidence/cloudwatch/dashboards.json` | 6,975 | 1 CloudWatch dashboard |
| `docs/evidence/glue/job-runs-summary.txt` | 676 | 39 runs - counts and durations per job |
| `docs/evidence/glue/job-runs.json` | 29,155 | full run history for 6 jobs |
| `docs/evidence/quicksight/dashboard-definition.json` | 74,397 | dashboard definition - 5 sheets, 28 visuals |
| `docs/evidence/quicksight/dataset-nyc-taxi-trips-star.json` | 17,438 | SPICE dataset definition |
| `docs/evidence/quicksight/sheet-geography.pdf` | 97,521 | rendered sheet: Geography (MDM Zones) |
| `docs/evidence/quicksight/sheet-overview.pdf` | 34,592 | rendered sheet: Executive Overview |
| `docs/evidence/quicksight/sheet-time.pdf` | 63,259 | rendered sheet: Time & Demand |
| `docs/evidence/quicksight/sheet-trip-behaviour.pdf` | 51,038 | rendered sheet: Trip Behaviour |
| `docs/evidence/quicksight/sheet-vendor-payment.pdf` | 44,555 | rendered sheet: Vendor & Payment |
| `docs/evidence/redshift-reconciliation.txt` | 27,479 | reconciliation output - 18 PASS / 0 FAIL |
| `docs/evidence/stepfunctions/executions.json` | 2,303 | 5 executions - 2 succeeded, 3 failed |
| `docs/evidence/stepfunctions/history-failed.json` | 47,816 | FAILED execution, full event history |
| `docs/evidence/stepfunctions/history-succeeded.json` | 79,233 | SUCCEEDED execution, full event history |
| `docs/evidence/stepfunctions/state-machine-definition.json` | 13,490 | deployed state machine definition |
| `docs/evidence/terraform-outputs.txt` | 3,444 | terraform outputs, sensitive values redacted |
| `docs/evidence/terraform-resource-inventory.txt` | 6,281 | 131 Terraform-managed resources |

**18 artifacts.**
