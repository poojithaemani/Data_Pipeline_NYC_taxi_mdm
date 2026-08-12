# Project Overview

An NYC Taxi **Master Data Management and analytics platform on AWS**. It is
deliberately production-grade in its patterns - SCD Type 2, infrastructure as
code, least privilege, cross-engine reconciliation - while staying small enough
to run cheaply.

For how the pieces are wired together, see [architecture.md](architecture.md).
This document covers what the platform is for and why it is built the way it
is.

---

## 1. What the platform does

It processes ~2.85 million yellow taxi trips through a medallion data lake,
masters the NYC taxi zone reference data with full version history, and serves
the result as a Redshift star schema behind a QuickSight dashboard - all
orchestrated by a single Step Functions execution and deployed by Terraform.

The interesting part is not the volume. It is that two pipelines with very
different characteristics have to meet correctly: a high-volume transactional
flow that is reprocessed wholesale, and a low-volume reference flow where every
individual change must be preserved forever.

---

## 2. Core concepts

**Medallion architecture.** Bronze holds raw source data. Silver holds cleaned,
validated, typed trip records in Delta Lake. Gold holds five business
aggregations. Each layer is reproducible from the one before it.

**Master Data Management.** Taxi zones are the master entity. They were chosen
over vendors because they carry descriptive business attributes - `borough`,
`zone`, `service_zone` - that genuinely change over time and need history.

**SCD Type 2.** Changes to a golden zone never overwrite. The current version
is expired with an `end_date` and a new version is inserted, so the full
history of every zone is queryable. Implemented as a PostgreSQL stored
procedure so the compare-and-version step is atomic and cannot race.

**Infrastructure as code.** Every AWS resource is Terraform-managed, with
remote state in S3 and locking via S3 conditional writes. There is no
click-ops step in the platform's construction.

**Reconciliation as a first-class test.** The warehouse is not trusted because
the job reported success. It is trusted because 18 in-Redshift checks pass and
33 days of trip counts and revenue tie out against the independently computed
Gold tables in Athena, to the cent.

---

## 3. Design decisions worth explaining

### Why `vendorid` is not mastered

No authoritative vendor master exists for this dataset, and the data contains a
vendor code that no available source can name. Creating a `dim_vendor` would
mean inventing master data inside an MDM project, which is precisely the thing
MDM exists to prevent. `vendorid` is carried as a degenerate dimension on the
fact table instead.

### Why there is no surrogate trip key

Silver has no stable natural trip identifier - the strongest available
six-column composite still collides on one pair of rows - and nothing
downstream needs one. A Redshift `IDENTITY` column would be worse than nothing:
values are assigned non-deterministically across slices, so every reload would
renumber every trip and the warehouse would stop being reproducible.

### Why the fact table is `DISTSTYLE EVEN`

Every dimension is `DISTSTYLE ALL` and therefore replicated to all nodes, so
joins to them need no redistribution at all. A `DISTKEY` on the fact would buy
nothing against a replicated dimension, could serve only one of the two zone
joins, and would introduce real skew because NYC pickups concentrate heavily in
a handful of zones.

### Why a separate warehouse export exists

Redshift `COPY` cannot read Delta Lake, and Gold is pre-aggregated with no
dimensional keys, so it cannot supply a trip-grain fact table. A separate
plain-Parquet snapshot satisfies the warehouse requirement without touching the
Silver and Gold Delta tables or the jobs that own them.

### Why current records are resolved by business key

`zone_matches` carries a pointer to a specific SCD2 version row, and nothing
repoints it when a new version supersedes that one. Joining on it silently
drops every zone that has ever been updated. Resolution therefore goes
`zone_matches` to `taxi_zones` to `golden_zones WHERE is_current`, by
`location_id` - which always finds whichever version is current and survives
any number of future updates.

### Why apply is manual

The platform holds a reconciled multi-million-row warehouse, a private database
with SCD2 history, and a live dashboard. Applying infrastructure changes
because someone merged a commit is not a trade worth making. A human dispatches
the deploy, types a confirmation, and a protected environment approves it.

---

## 4. Validated state

Figures from the last full validated pipeline execution. Any change that moves
one of these without explanation is a bug.

| Metric | Value |
|---|---|
| Silver rows / `fact_trips` / SPICE rows | 2,851,125 |
| `dim_zone` / `zone_matches` / `taxi_zones` | 265 |
| `dim_date` (gap-free calendar) | 33 |
| `dim_payment` (full TLC code set) | 7 |
| `SUM(fare_amount)` | 52,389,612.60 |
| `SUM(total_amount)` | 79,198,239.40 |
| Gold: daily / vendor / borough / payment / hourly | 33 / 95 / 203,611 / 128 / 748 |
| Distinct vendors | 3 |

Reconciliation status: 18 of 18 in-Redshift checks pass; 33 of 33 days tie out
against Gold on both trip count and revenue; the SPICE ingestion reports
2,851,125 rows with 0 dropped.

`golden_zones` holds more rows than there are zones, which is correct and is
the point of SCD Type 2 - superseded versions are retained alongside the
current ones.

---

## 5. Technology choices

| Technology | Why |
|---|---|
| **Terraform** | Reproducible, reviewable infrastructure; a plan diff is the change-control mechanism |
| **S3** | Durable, cheap data lake storage |
| **Glue (PySpark)** | Serverless Spark; no cluster to manage for a pipeline that runs on demand |
| **Delta Lake** | ACID writes, schema evolution and time travel over S3 |
| **RDS PostgreSQL** | Transactional guarantees the SCD2 procedure depends on. Not Aurora - a single small instance is sufficient and cheaper |
| **Redshift Serverless** | Star-schema serving without a permanently running cluster |
| **QuickSight (SPICE)** | Fast dashboards decoupled from warehouse availability |
| **Athena** | Ad-hoc SQL over the Delta tables and the independent reconciliation reference |
| **Step Functions** | Orchestration with retries, error handling and durable, inspectable execution history |
| **GitHub Actions + OIDC** | CI without any long-lived AWS credential |

---

## 6. What is deliberately not built

- **No `dim_vendor`** - see above; it would fabricate master data
- **No API layer** - an earlier design sketched API Gateway to Lambda to RDS
  for master-data lookups. It was never deployed and the scaffolding has been
  removed. Consumers reach mastered data through the warehouse
- **No Kafka, Airflow, EMR, ECS or EKS** - the pipeline is batch and runs on
  demand; Step Functions and Glue cover it without adding a platform to operate
- **No streaming ingestion** - the source is published as periodic files

---

## 7. Known limitations

Documented rather than hidden. Each is a deliberate decision with a stated
reason.

| Limitation | Status |
|---|---|
| The Redshift load is not atomic - `TRUNCATE` commits implicitly, so a mid-load failure leaves the warehouse partially refreshed | Accepted; recovery is a re-run. A staging-and-swap redesign would fix it |
| RDS server certificate is not verified client-side; traffic is encrypted but the certificate is not pinned | Accepted; pinning needs the RDS CA bundle staged into the Glue container |
| RDS storage and the Redshift namespace use AWS managed KMS keys rather than the project CMK | Accepted; switching either would require replacing the resource |
| Alarms have no SNS subscriber, so they transition but notify nobody | Open; needs an address |
| 321 Silver rows have a negative `total_amount`, and one trip is $863,380.37 | Carried through deliberately - Silver validates `fare_amount` but not `total_amount`, and filtering would break the Silver-to-fact reconciliation |
| `gold_db.payment_summary.total_amount` actually contains `SUM(fare_amount)` | A naming defect in a frozen job. Reconciliation compares counts, or compares against `fare_amount` |
| The Glue execution role is declared twice in Terraform, both mapping to the same physical role | Untangling needs a state operation; documented in architecture.md |

---

## 8. Repository layout

```
pipeline/glue/jobs/     Deployed Glue job scripts
pipeline/ingestion/     Python reference-data ingestion orchestrator
configs/                source.yaml and ingestion configuration
services/database/      Schema, 13 migrations, SCD2 procedure, audit trigger, tests
services/redshift/      Star-schema DDL, COPY script, reconciliation SQL
scripts/                sync_pipeline_runs.py - Glue history into pipeline_runs
terraform/              Root configuration and 11 wired modules
.github/workflows/      CI, Terraform plan, protected apply
docs/                   This documentation
diagrams/               Architecture diagram source
notebooks/              Exploratory analysis
tests/                  Unit tests
```

The historical vendor SCD2 implementation is retained under
`pipeline/glue/jobs/vendor_etl.py` and `services/database/`. It is inactive and
referenced by nothing, but the `vendors` table and its stored procedure still
exist in the database and the migrations create them, so the files remain as
the record of their origin.
