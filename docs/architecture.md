# Architecture

The deployed architecture of the NYC Taxi MDM platform. Everything described
here exists and has been validated end to end; nothing in this document is
aspirational.

Region: `us-east-2`. All infrastructure is managed by Terraform with remote
state in S3.

---

## 1. Data flow

Two pipelines run side by side and converge at the warehouse export. The
transactional side carries volume; the reference side carries the mastered
business meaning.

```
NYC TLC source data                      NYC TLC taxi zone lookup (CSV)
        |                                              |
        v                                              v
  S3 bronze/transactions/            S3 bronze/reference/taxi_zones/
        |                                              |
        | yellow_taxi_silver_etl                       | golden_zone_etl
        v                                              v
  S3 silver/ (Delta)                       RDS PostgreSQL  -  MDM
   partitioned by                            golden_zones (SCD Type 2)
   pickup_year/month                         taxi_zones, zone_matches
        |                                    audit_log, pipeline_runs
        | yellow_taxi_gold_etl                         |
        v                                              |
  S3 gold/ (Delta, 5 summaries)                        |
        |                                              |
        |            warehouse_export_etl              |
        +--------------------+-------------------------+
                             v
              S3 warehouse/ (plain Parquet)
              fact_trips, dim_zone, dim_date, dim_payment
                             |
                             | Redshift COPY (Data API)
                             v
              Redshift Serverless - taxi_analytics
                    star schema, 4 tables
                             |
                             | SPICE ingestion
                             v
                 QuickSight - 5-sheet dashboard
```

Athena queries the Silver and Gold Delta tables directly through the Glue Data
Catalog, in parallel with the Redshift path. It is the ad-hoc analysis route
and the cross-engine reconciliation reference; it is not in the dashboard's
serving path.

### Why a separate `warehouse/` dataset exists

Redshift `COPY` cannot read Delta Lake, and the Gold tables are pre-aggregated
with no dimensional keys, so they cannot supply a trip-grain fact table.
Exporting a separate plain-Parquet snapshot satisfies the warehouse
requirement while leaving the Silver and Gold Delta tables untouched.

`fact_trips` is a lossless projection of Silver - no filter, no deduplication,
no enrichment - so its row count must equal Silver exactly, which is what makes
the reconciliation against Gold meaningful.

### S3 layout

| Prefix | Contents |
|---|---|
| `bronze/` | Raw trip Parquet and the taxi zone reference CSV |
| `silver/` | Cleaned trip data, Delta, partitioned by pickup year and month |
| `gold/` | Five Delta summaries: daily, vendor, borough, payment, hourly |
| `warehouse/` | Redshift-ready star schema snapshot, plain Snappy Parquet |
| `master/` | Published mastered zone reference (`golden_zones/`) |
| `demo/` | Isolated Delta time-travel demonstration and its evidence |
| `glue/` | Job scripts and the Glue temp directory |
| `athena-results/`, `checkpoints/`, `logs/`, `metadata/`, `quality/` | Supporting prefixes |

---

## 2. Orchestration

A single Step Functions state machine drives the whole chain. It is strictly
sequential because each stage consumes the previous stage's output:
`warehouse_export_etl` reads both the Silver Delta table and the mastered zones
in RDS, and the Redshift `COPY` reads the warehouse snapshot.

```
Step Functions: nyc-taxi-mdm-platform-pipeline  (17 states)
 |
 +-- SilverETL           glue:startJobRun.sync
 +-- GoldETL             glue:startJobRun.sync
 +-- GoldenZoneETL       glue:startJobRun.sync
 +-- WarehouseExport     glue:startJobRun.sync
 +-- StartRedshiftCopy   redshiftdata:batchExecuteStatement  -> poll loop
 +-- StartSpiceRefresh   quicksight:createIngestion          -> poll loop
 +-- PipelineSucceeded
```

Every stage carries retries with exponential backoff and a `Catch` handler
that routes to a single failure path: publish to SNS, then a terminal `Fail`
state. The two asynchronous stages poll their own status rather than assuming
completion.

The COPY statements are not restated in the state machine. Terraform reads
`services/redshift/load/02_copy_from_s3.sql` at plan time and passes its 13
statements to the Data API, so that file stays the single source of truth for
the load.

### Glue jobs

| Job | Type | Purpose | In VPC |
|---|---|---|---|
| `yellow-taxi-silver-etl` | Spark | Bronze Parquet to Silver Delta | no |
| `yellow-taxi-gold-etl` | Spark | Silver Delta to five Gold summaries | no |
| `golden-zone-etl` | Spark | Zone CSV to `golden_zones` via SCD2 procedure | yes |
| `warehouse-export-etl` | Spark | Silver + MDM to warehouse Parquet | yes |
| `sync-pipeline-runs` | Python Shell | Glue run history into `pipeline_runs` | yes |
| `delta-demo` | Spark | Delta time-travel demonstration | no |

Only the jobs that reach the database run inside the VPC.

---

## 3. MDM and SCD Type 2

Taxi zones are the master data entity: they carry descriptive business
attributes (`borough`, `zone`, `service_zone`) that can change and need
history. `vendorid` is deliberately **not** mastered - no authoritative vendor
source exists, and the data contains a vendor code that no available source can
name, so it is carried as a degenerate dimension on the fact table.

### Tables

| Table | Role |
|---|---|
| `taxi_zones` | Source-aligned reference records, one row per `location_id` |
| `golden_zones` | Mastered records with full SCD Type 2 version history |
| `zone_matches` | Validated mapping from source zone to golden record |
| `audit_log` | Row-level change history, written by an AFTER INSERT OR UPDATE trigger |
| `pipeline_runs` | Operational tracking, mirrored from Glue run history |

### How a change is applied

`golden_zone_etl` standardises each source row, computes a `record_hash`, and
calls `sp_upsert_golden_zone`. The procedure compares the hash and takes one of
three paths, which are the three transitions SCD Type 2 has to get right:

- **INSERTED** - no current record exists, so version 1 is created
- **NO_CHANGE** - the hash matches, so nothing is written
- **UPDATED** - the hash differs, so the current version is expired with an
  `end_date` and a new version is inserted with `is_current = true`

### Current-record resolution

Downstream consumers resolve the current golden record **by business key**:

```
zone_matches.source_zone_id -> taxi_zones.location_id
                            -> golden_zones.location_id  WHERE is_current
```

It is deliberately **not** resolved through `zone_matches.golden_zone_row_id`.
That column points at one specific version row, and nothing repoints it when a
new version supersedes it - so joining on it silently drops every zone that has
ever been updated. Going through `taxi_zones` also excludes the test fixture
`location_id = 99999` structurally rather than by a magic-number filter, which
matters because that fixture's version 2 is `is_current = true`.

---

## 4. Security

```
GitHub Actions ──OIDC──> IAM roles (no access keys)
                              │
                              ▼
                        Terraform ──> AWS
Internet
   │  (no path)
   ✗
RDS PostgreSQL  (publicly_accessible = false)
   ▲
   │ TLS 1.3, credentials from Secrets Manager
   │
Glue ENIs ── private subnet ──┬── NAT gateway ──> PyPI
                              └── S3 gateway endpoint ──> data lake
```

| Control | Implementation |
|---|---|
| Database exposure | RDS is not publicly accessible; its security group admits only the Glue security group on 5432 |
| Glue connectivity | A `NETWORK` Glue connection places database-facing jobs on ENIs in a dedicated private subnet |
| Egress | NAT gateway for the runtime `pip install` both DB jobs require; S3 gateway endpoint keeps bulk data off the metered NAT |
| Credentials | Two Secrets Manager secrets (RDS master, Redshift admin). Jobs receive only a secret ARN and resolve the credential at runtime |
| Encryption at rest | Customer managed KMS key with rotation enabled, backing S3 data-lake default encryption, Athena results and both secrets |
| Encryption in transit | `rds.force_ssl = 1`; connections observed at TLS 1.3 with a 256-bit cipher |
| IAM | Per-service roles with scoped policies. The Step Functions role can read one secret and refresh one QuickSight dataset; the Glue role can read one secret and its own log group |
| CI credentials | GitHub OIDC only. No long-lived AWS access key exists for automation |
| Backups | 7-day RDS automated backups and deletion protection |

Redshift Serverless is not publicly accessible and requires SSL. QuickSight
reaches it over a VPC connection.

**Known limitation.** `02_copy_from_s3.sql` interleaves `TRUNCATE` and `COPY`,
and Redshift's `TRUNCATE` commits implicitly - so a failure part-way through
leaves the warehouse partially refreshed rather than rolling back. Recovery is
a re-run of the same file. A staging-table-and-swap redesign would remove this;
it is accepted and documented rather than fixed.

---

## 5. Observability

| Signal | Mechanism |
|---|---|
| Pipeline outcome | Step Functions execution history, `ALL`-level logging to CloudWatch |
| Stage failure | `Catch` on every state publishes to SNS, then fails the execution |
| Glue job failure | EventBridge rule on `Glue Job State Change` (FAILED, TIMEOUT, ERROR) to SNS - catches jobs started outside the state machine too |
| Alarms | Execution failed, execution timed out, execution duration, Redshift RPU-seconds |
| Dashboard | CloudWatch dashboard covering executions, per-job Glue metrics and Redshift capacity |
| Run history | `pipeline_runs` in RDS, mirrored from Glue by the `sync-pipeline-runs` job |

There is deliberately no metric alarm on Glue task failures: the metric carries
a `JobRunId` dimension, so spanning runs needs a `SEARCH` expression, and
CloudWatch rejects those on alarms. Job failure is alarmed through EventBridge
and the state machine instead, which are better signals anyway - a failed Spark
task can be retried and the job still succeed.

Alarms publish to an SNS topic. A subscriber must be added for anyone to be
notified.

---

## 6. CI/CD

| Workflow | Trigger | AWS access | Purpose |
|---|---|---|---|
| `ci.yml` | PR and push to `main` | **none** | `terraform fmt -check`, `init -backend=false`, `validate`, `compileall`, `pytest`, gitleaks, forbidden-file guard |
| `terraform-plan.yml` | PR to `main` | OIDC, read-only | Plan posted to the job summary |
| `terraform-apply.yml` | `workflow_dispatch` only | OIDC, write | Gated deploy |

CI needs no credentials by design, so the checks that gate a pull request
cannot be blocked by cloud access and a fork's pull request can never obtain
credentials.

Two IAM roles back this, because the blast radius differs by an order of
magnitude. The plan role's trust policy pins the `sub` claim to
`repo:<owner>/<repo>:pull_request` and grants read-only. The apply role pins it
to `repo:<owner>/<repo>:environment:production`, so the environment's required
reviewers are enforced by the AWS trust policy rather than by workflow
convention alone.

Apply has no push or pull-request trigger at all and is gated three ways: a
person dispatches it, a typed confirmation must read `APPLY`, and the
protected environment must approve. No plan file is ever uploaded as an
artifact - a saved plan embeds sensitive values in plaintext.

State lives in a private, versioned S3 bucket with S3 conditional-write
locking, so no DynamoDB lock table is needed.

---

## 7. Delta Lake demonstration

An isolated demonstration under `demo/`, built by the `delta-demo` Glue job. It
reads the Bronze zone CSV and writes only to `demo/`; no production table is
touched.

| Version | Operation | Result |
|---|---|---|
| v0 | `WRITE` | 265 zones, 4 columns |
| v1 | `UPDATE` | one row's `service_zone` rewritten in place |
| v2 | `WRITE` with `mergeSchema` | 3 rows appended carrying a new `zone_category` column |

Read back without rewriting anything, `versionAsOf 0` still returns the
original 4-column schema **and** the pre-update value, `versionAsOf 1` shows
the changed value with the original schema, and the current version carries the
evolved 5-column schema with the 265 pre-existing rows reading NULL in the new
column. `DESCRIBE HISTORY` lists all three versions with their operations.

Evidence is persisted to `demo/evidence/delta_demo_evidence.json`. The table is
rebuilt on every run so the version numbers are always deterministically 0, 1
and 2.

---

## 8. Component inventory

| Layer | Components |
|---|---|
| Storage | S3 data lake; S3 remote-state bucket |
| Compute | 6 Glue jobs (5 Spark, 1 Python Shell); 3 Glue crawlers |
| Catalog | Glue databases `bronze_db`, `silver_db`, `gold_db`, `master_db` |
| MDM | RDS PostgreSQL, private, with SCD2 procedure, audit trigger and 13 migrations |
| Warehouse | Redshift Serverless, 8 RPU, private, `taxi_analytics` star schema |
| BI | QuickSight SPICE dataset, analysis and 5-sheet dashboard over a VPC connection |
| Orchestration | Step Functions state machine |
| Observability | CloudWatch dashboard, 4 alarms, EventBridge rule, SNS topic |
| Security | KMS CMK, 2 Secrets Manager secrets, NAT gateway, S3 gateway endpoint, private subnet, GitHub OIDC provider and 2 CI roles |
| Analytics | Athena workgroup over the Delta tables |

### Terraform layout

Root configuration in `terraform/` declares the Glue jobs and crawlers, the
Glue catalog databases, the Athena workgroup, the Glue IAM role, the state
bucket and the CI wiring. Everything else lives in wired modules: `s3`, `iam`,
`cloudwatch`, `rds`, `redshift`, `network`, `kms`, `secrets`, `stepfunctions`,
`monitoring`, `github_oidc`.

### Known technical debt

- The Glue execution role is declared twice - once in the root configuration
  and once in `modules/iam` - and both map to the same physical IAM role.
  Removing either would make Terraform destroy the role every Glue job runs
  as, so untangling it needs a state operation.
- `--spark-sql-extensions` and `--spark-sql-catalog-spark_catalog` in the
  shared Glue job arguments are ordinary job arguments, not Spark
  configuration, and reach nothing. The Spark jobs that use only the Delta
  DataSource API are unaffected; the demo job passes the Delta configuration
  explicitly via `--conf`.
- The historical vendor SCD2 artifacts (`vendor_etl.py`,
  `sp_upsert_vendor.sql`, `test_vendor.sql`) are referenced by nothing, but the
  `vendors` table and its procedure still exist in RDS and the frozen
  migrations create them, so the files are retained as the origin record.
