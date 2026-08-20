# NYC Taxi MDM — final cleanup and reusable-resource retention

**Project status: complete.** This document is the teardown record.

**Nothing has been destroyed. `terraform apply` has not been run.**
A saved plan exists at `terraform/tfplan.decom` awaiting approval.

Identifiers are redacted throughout; live values are in the gitignored operator notes.

---

## 1. Plan summary

```
Plan: 0 to add, 2 to change, 78 to destroy.
```

The count moved from 64 to 78 when approved decisions D3, D4 and D5 were
implemented. Every one of the 14 additions is accounted for, and **nothing left
the destroy list**:

| Decision | Added to destroy | Count |
|---|---|---:|
| D3 | RDS master secret + its version | 2 |
| D4 | 3 CloudWatch log groups (all empty, all NYC-named) | 3 |
| D5 | 9 S3 folder markers — bucket, versioning, encryption and lifecycle all retained | 9 |

No resource is replaced and none is created — the two in-place changes are
policy edits that drop references to things being removed:

| Change | Why |
|---|---|
| `module.kms.aws_kms_key.this` — key policy | The Glue role is being deleted, so it is removed from the key's user list. The **key itself survives** |
| `module.github_oidc.aws_iam_role_policy.plan_state` | Drops the Glue-connection ARN and secret ARNs the CI plan role no longer needs |

Applied with `create_network=false` and `create_rds=false`; all other flags at
their retained defaults.

---

## 2. Correction to the previous draft

An earlier version of this document claimed three `module.kms[0]` references
were unguarded and would fail at plan time:

```
terraform/glue_iam.tf:147 · terraform/main.tf:113 · terraform/main.tf:178
```

**That was wrong.** All three were lazily evaluated — one inside a
`dynamic "statement"` whose `for_each` was already conditional, two inside
module blocks whose `count` was already conditional. Terraform would not have
errored.

The real hazard was different and worse: `module.kms` was gated by
`create_orchestration`, so disabling the orchestration layer would have
**silently destroyed the CMK that encrypts the retained S3 bucket**. That is
what §4 fixes.

---

## 3. Terraform changes made

All local. No AWS call was involved.

**Deleted — every block in these files was NYC-specific, verified individually:**

```
terraform/athena.tf        1 workgroup
terraform/glue_catalog.tf  4 catalog databases
terraform/glue_crawlers.tf 3 crawlers
terraform/glue_iam.tf      Glue role + inline policy
terraform/glue_jobs.tf     6 Glue jobs + 8 script objects
```

**Removed from `main.tf`:** `module "iam"` (Glue/Lambda/EventBridge roles, all
NYC-scoped), `module "monitoring"`, `module "stepfunctions"`, and the `locals`
block that fed them Glue job names.

**Removed from `outputs.tf`:** 23 outputs whose resources no longer exist.

**Removed from `variables.tf`:** 24 variables left unreferenced — catalog and
crawler names, lake path prefixes, alarm thresholds, pipeline timeouts.

**Flags restructured:**

| Flag | Status | Gates |
|---|---|---|
| `create_kms` | **new**, default `true` | The CMK. Split out so the orchestration teardown cannot destroy it |
| `create_secrets` | **new**, default `true` | Secrets Manager. Split out because retained Redshift needs the admin secret |
| `create_network` | **renamed** from `create_orchestration` | Private subnet, NAT gateway, EIP, S3 endpoint, Glue connection |
| `create_orchestration` | **deleted** | Nothing left to gate |
| `create_rds`, `create_redshift`, `create_cicd` | unchanged | — |

`terraform fmt` clean · `terraform validate` **Success** · plan produced without error.

One warning remains: `terraform.tfvars` still sets `alert_email`, now undeclared.
Harmless. That file is gitignored and yours — delete the line when convenient.

---

## 4. KEEP — retained resources (28 real resources)

| Resource | Count | Why retained |
|---|---:|---|
| S3 data lake bucket + versioning, encryption, lifecycle, public-access block | 5 | Reusable storage. **Its default encryption is the CMK** |
| Terraform state bucket + its 4 configs | 5 | The remote backend. Carries `prevent_destroy` |
| KMS CMK + alias | 2 | **Critical.** Destroying it makes every retained S3 object permanently unreadable |
| Redshift Serverless namespace, workgroup, security group, IAM role + policy | 6 | Retained per instruction. The security group is also what the QuickSight VPC connection points at |
| Redshift admin secret + version | 2 | Confirmed retained dependency: the Redshift `COPY` path authenticates through it |
| GitHub OIDC provider, plan/apply roles, policies, attachments | 7 | Reusable CI/CD federation, no long-lived credentials. See §12 |
| `random_password.rds_master` | 1 | State-only, no AWS resource, no cost |

Not Terraform-managed, also retained: the **QuickSight account, subscription and
VPC connection**, and the account's default VPC and subnets.

Not Terraform-managed, also retained: the **QuickSight account, subscription and
VPC connection**, and the account's default VPC and subnets.

---

## 5. DELETE — 64 resources in the plan

| Group | Count | Notes |
|---|---:|---|
| `module.network` | 11 | NAT gateway, EIP, private subnet, route table + route + association, S3 VPC endpoint, Glue connection, Glue SG + 2 rules |
| `module.iam` | 11 | Glue, Lambda and EventBridge roles and policies — Lambda and EventBridge were never wired to anything |
| `module.monitoring` | 10 | SNS topic, dashboard, alarms — all reference NYC job names |
| `module.rds` | 4 | Instance, subnet group, parameter group, security group |
| `module.stepfunctions` | 4 | State machine, role, policy, log group |
| Glue jobs | 6 | silver, gold, golden-zone, warehouse-export, sync-pipeline-runs, delta-demo |
| Glue crawlers | 3 | bronze, silver, gold |
| Glue catalog databases | 4 | bronze, silver, gold, master |
| S3 script objects | 8 | ETL scripts and the temp-dir marker |
| Glue IAM role + policy | 2 | |
| Athena workgroup | 1 | |

---

## 6. NOT covered by Terraform — separate steps required

The plan does **not** touch these. They need explicit action after the apply.

| Item | Detail |
|---|---|
| **S3 lake data** | ~700 MB current across 13 NYC prefixes, plus ~1,000 non-current versions and ~839 delete markers. The bucket is versioned and has no `force_destroy`, so versions and delete markers must be purged explicitly |
| **Redshift NYC tables** | `fact_trips`, `dim_zone`, `dim_date`, `dim_payment` in `taxi_analytics`. Dropping them reclaims storage; the namespace and workgroup stay |
| **QuickSight NYC assets** | Dashboard, analysis, SPICE dataset (1.78 GiB consumed), Redshift data source. **Account, subscription and VPC connection are preserved** |
| **Orphaned Glue log groups** | 6 auto-created `/aws-glue/*` groups totalling ~17.5 MB, never in Terraform state. See decision D6 |

Sequencing note: delete the QuickSight **dataset** before dropping the Redshift
tables, otherwise the dataset is left pointing at missing tables. Both are being
removed, so the only consequence is a confusing error if done in reverse.

---

## 7. Decisions needed

| # | Item | Recurring cost | Recommendation |
|---|---|---|---|
| **D1** | **NAT Gateway** | ~$32.85/mo at list, plus $0.045/GB | **Delete.** Nothing retained needs it — it existed only for VPC-bound Glue egress. Recreating it later is one `terraform apply` with `create_network=true`; the module source stays on disk. Already in the plan |
| **D2** | **RDS** (`db.t3.micro`, 20 GB gp2, single-AZ, 7-day backups) | ~$13/mo instance + ~$2/mo storage at list; may be free-tier covered | **Delete.** MDM data is exported and verified (834 rows). ⚠️ `skip_final_snapshot = true` — **no snapshot is taken**. Already in the plan |
| **D3** | RDS master secret | $0.40/mo | Orphaned once RDS goes. Suggest deleting; not in the current plan |
| **D4** | 3 CloudWatch log groups | ~$0 | All empty, two belong to modules never deployed. Suggest deleting; not in the current plan |
| **D5** | 9 S3 folder markers | $0 | NYC-shaped layout (`bronze/`, `silver/`, `gold/`, `master/`…) in a bucket you are keeping. Suggest clearing for a clean reusable bucket |
| **D6** | 6 orphaned `/aws-glue/*` log groups | ~$0 | ~17.5 MB, outside Terraform. Suggest deleting manually |
| **D7** | QuickSight author seat (`ADMIN_PRO`) | Billed monthly once any trial ends | Retained per instruction. **Verify the trial end date in the console** — this is the charge most likely to appear unnoticed later |
| **D8** | GitHub OIDC roles | $0 | Trust policy is scoped to this repository. Retain and repoint via variable for future repos, or delete. `apply` role carries **PowerUserAccess** — worth narrowing if retained |

---

## 8. Recurring cost table

List prices, us-east-2. Month-to-date observed spend is effectively **$0** across
all services, consistent with free-tier or trial coverage — so these are ceilings,
not current charges.

| Resource | Keep/Delete | NYC-specific? | Recurring cost | Reason |
|---|---|---|---|---|
| NAT Gateway | **Delete** | Yes | ~$32.85/mo | Largest cost in the estate; nothing retained needs it |
| RDS instance | **Delete** | Yes | ~$15/mo | Data exported; no future use identified |
| Redshift Serverless | **Keep** | No | $0 idle; $0.36/RPU-hr on query; storage ~$0.024/GB-mo | Reusable. Idle workgroups bill no compute |
| Redshift NYC tables | **Delete** | Yes | Storage only | Reclaims storage inside a retained namespace |
| QuickSight account | **Keep** | No | Author seat, monthly, after trial | Explicitly retained |
| QuickSight NYC assets | **Delete** | Yes | Frees 1.78 GiB SPICE | Releases capacity for reuse |
| S3 data lake bucket | **Keep** | No | ~$0.02/mo now; near $0 after purge | Reusable storage |
| S3 NYC data + versions | **Delete** | Yes | — | 700 MB + ~1,000 versions + ~839 markers |
| S3 Terraform state bucket | **Keep** | No | negligible | The backend |
| KMS CMK | **Keep** | No | $1/mo | **Encrypts retained S3 data** |
| Secrets Manager (2) | **Keep** (1 by decision) | Mixed | $0.40 each/mo | Redshift admin required; RDS one orphaned (D3) |
| CloudWatch log groups | **Keep** (D4) | Yes | ~$0 | Empty |
| Glue jobs/crawlers/catalog | **Delete** | Yes | $0 idle | Pay-per-run; no charge when idle, but obsolete |
| Step Functions | **Delete** | Yes | $0 idle | Pay-per-transition |
| Athena workgroup | **Delete** | Yes | $0 idle | Pay-per-query |
| IAM / OIDC | **Keep** | No | $0 | No long-lived credentials issued |

**Estimated saving from D1 + D2: roughly $48/month at list price.**

---

## 9. Validation performed

- `terraform fmt -recursive` — clean
- `terraform validate` — Success (one benign tfvars warning, §3)
- `terraform plan` — 0 add, 2 change, 64 destroy; no replacements
- Region sweep — us-east-1, us-west-2, eu-west-1, ap-south-1 all clear of RDS, Redshift, EC2 and Glue
- Account-wide S3 — exactly 2 buckets, both accounted for
- No EC2 instances in any region checked
- Evidence capture verified before teardown: 18 artifacts, 834 MDM rows, 18/18 reconciliation checks passing

Post-apply verification is **not yet done** — it runs after approval.

---

## 10. Limitations and things intentionally outside Terraform

- **QuickSight is entirely API-managed.** No Terraform coverage exists for the
  account, VPC connection, data source, dataset, analysis or dashboard.
- **Redshift table DDL is not Terraform-managed** — it lives in
  `services/redshift/ddl/`, applied out of band.
- **The Glue-created log groups** were never in state and must be cleaned manually.
- **`services/database/schema.sql` remains stale** relative to the live database.
  The authoritative capture is `services/database/seed/mdm_live_schema.sql`,
  reconstructed from `information_schema` at decommissioning.
- The deleted `modules/` source directories for `stepfunctions`, `monitoring`,
  `network` and `iam` are **retained on disk** — only their root wiring was
  removed, so the patterns remain reusable.

---

## 12. D8 — narrowing the CI apply role

Reviewed, **not changed**. No permission was expanded.

The supplementary policy is already tight: `iam:*` actions are scoped by ARN to
roles and policies carrying the project prefix, so the role cannot touch an
unrelated principal or attach `AdministratorAccess` outside that prefix.

The broad grant is the managed **`PowerUserAccess`** attachment — full access to
every service except IAM, Organizations and Account.

What could safely replace it after teardown: a customer-managed policy limited
to the services the retained estate actually uses — S3, KMS, Redshift Serverless,
Secrets Manager, and EC2 describe/security-group actions. Glue, Step Functions,
RDS, SNS, Athena and CloudWatch permissions become dead weight once those
resources are gone.

**Sequencing matters: do not narrow it before the teardown.** The apply role is
what deletes the Glue jobs, state machine, RDS instance and alarms; removing
those permissions first would break the very apply that removes them.

The trade-off to weigh afterwards: a narrowed policy blocks any new service a
future project introduces until the policy is extended. That is arguably the
correct default for a shared account, but it is a real friction cost.

---

## 11. Approval gate

Before any destructive operation I need explicit approval on:

1. The plan as summarised in §1 (covers D1 and D2)
2. Decisions D3–D8 in §7
3. The four non-Terraform cleanups in §6

`terraform apply` will not be run until then.
