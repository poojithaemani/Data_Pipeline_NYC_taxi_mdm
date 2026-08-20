"""Capture decommissioning evidence from the live AWS account.

Read-only. Creates nothing in AWS except QuickSight snapshot jobs, which are
ephemeral render tasks, not persistent resources.

Covers steps 1-6 of the teardown runbook:

  1. QuickSight dashboard -> one rendered PDF per sheet
  2. QuickSight dashboard definition (how the 28 visuals were built)
  3. Redshift star-schema reconciliation, actual result rows
  4. Step Functions execution history - one failure and one success
  5. Glue job run history across every job
  6. CloudWatch dashboards + alarms, Terraform resource inventory

Output lands in docs/evidence/ with raw AWS identifiers still in place.
Run the scrub pass (step 8) before any of it is staged for a public repo.

    py scripts/capture_evidence.py [section ...]

With no arguments every section runs.
"""

import json
import os
import re
import subprocess
import sys
import time
import urllib.request

import boto3

ACCOUNT = "749185461065"
REGION = "us-east-2"
DASHBOARD_ID = "nyc-taxi-executive-dashboard"
WORKGROUP = "nyc-taxi-mdm-wg"
DATABASE = "taxi_analytics"

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "docs", "evidence")

GLUE_JOBS = [
    "nyc-taxi-mdm-platform-yellow-taxi-silver-etl",
    "nyc-taxi-mdm-platform-yellow-taxi-gold-etl",
    "nyc-taxi-mdm-platform-golden-zone-etl",
    "nyc-taxi-mdm-platform-warehouse-export-etl",
    "nyc-taxi-mdm-platform-sync-pipeline-runs",
    "nyc-taxi-mdm-platform-delta-demo",
]

manifest = []


def log(msg):
    print(msg, flush=True)


def record(path, note):
    rel = os.path.relpath(path, REPO).replace("\\", "/")
    size = os.path.getsize(path) if os.path.exists(path) else 0
    manifest.append((rel, size, note))
    log(f"    wrote {rel}  ({size:,} bytes)")


def write_json(name, obj, note):
    path = os.path.join(OUT, name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(obj, f, indent=2, default=str)
    record(path, note)


def write_text(name, text, note):
    path = os.path.join(OUT, name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    record(path, note)


# ---------------------------------------------------------------- section 1
def section_1_quicksight_pdfs():
    """Render every dashboard sheet to PDF.

    The presigned URL the job returns expires after 300 seconds, so submit,
    poll and download have to stay inside one run - the URL cannot be saved
    and fetched later.
    """
    log("[1] QuickSight sheet PDFs")
    qs = boto3.client("quicksight", region_name=REGION)

    definition = qs.describe_dashboard_definition(
        AwsAccountId=ACCOUNT, DashboardId=DASHBOARD_ID
    )
    sheets = [(s["SheetId"], s.get("Name", s["SheetId"]))
              for s in definition["Definition"]["Sheets"]]
    log(f"    {len(sheets)} sheets to render")

    stamp = int(time.time())
    for sheet_id, sheet_name in sheets:
        job_id = f"decom-{sheet_id}-{stamp}"
        qs.start_dashboard_snapshot_job(
            AwsAccountId=ACCOUNT,
            DashboardId=DASHBOARD_ID,
            SnapshotJobId=job_id,
            UserConfiguration={
                "AnonymousUsers": [
                    {"RowLevelPermissionTags": [{"Key": "none", "Value": "none"}]}
                ]
            },
            SnapshotConfiguration={
                "FileGroups": [
                    {
                        "Files": [
                            {
                                "SheetSelections": [
                                    {"SheetId": sheet_id,
                                     "SelectionScope": "ALL_VISUALS"}
                                ],
                                "FormatType": "PDF",
                            }
                        ]
                    }
                ]
            },
        )

        status = "QUEUED"
        for _ in range(30):
            status = qs.describe_dashboard_snapshot_job(
                AwsAccountId=ACCOUNT, DashboardId=DASHBOARD_ID, SnapshotJobId=job_id
            )["JobStatus"]
            if status not in ("QUEUED", "RUNNING"):
                break
            time.sleep(10)

        if status != "COMPLETED":
            log(f"    !! {sheet_id}: job ended {status}, skipping")
            continue

        result = qs.describe_dashboard_snapshot_job_result(
            AwsAccountId=ACCOUNT, DashboardId=DASHBOARD_ID, SnapshotJobId=job_id
        )
        uri = (result["Result"]["AnonymousUsers"][0]["FileGroups"][0]
               ["S3Results"][0]["S3Uri"])

        path = os.path.join(OUT, "quicksight", f"{sheet_id}.pdf")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with urllib.request.urlopen(uri) as r, open(path, "wb") as f:
            f.write(r.read())
        record(path, f"rendered dashboard sheet: {sheet_name}")


# ---------------------------------------------------------------- section 2
def section_2_quicksight_definition():
    log("[2] QuickSight definition + dataset")
    qs = boto3.client("quicksight", region_name=REGION)

    d = qs.describe_dashboard_definition(AwsAccountId=ACCOUNT,
                                         DashboardId=DASHBOARD_ID)
    d.pop("ResponseMetadata", None)
    visuals = sum(len(s.get("Visuals", [])) for s in d["Definition"]["Sheets"])
    write_json("quicksight/dashboard-definition.json", d,
               f"dashboard definition - {len(d['Definition']['Sheets'])} sheets, "
               f"{visuals} visuals")

    for ds in qs.list_data_sets(AwsAccountId=ACCOUNT)["DataSetSummaries"]:
        full = qs.describe_data_set(AwsAccountId=ACCOUNT,
                                    DataSetId=ds["DataSetId"])
        full.pop("ResponseMetadata", None)
        write_json(f"quicksight/dataset-{ds['DataSetId']}.json", full,
                   f"dataset {ds['Name']} ({ds.get('ImportMode')})")


# ---------------------------------------------------------------- section 3
def section_3_redshift_reconciliation():
    """Run the frozen reconciliation SQL and keep the verdict rows."""
    log("[3] Redshift reconciliation")
    rsd = boto3.client("redshift-data", region_name=REGION)

    def run(sql, warm=False):
        sid = rsd.execute_statement(WorkgroupName=WORKGROUP, Database=DATABASE,
                                    Sql=sql)["Id"]
        # Serverless cold-starts; the first statement can take ~2 minutes.
        for _ in range(60):
            d = rsd.describe_statement(Id=sid)
            if d["Status"] in ("FINISHED", "FAILED", "ABORTED"):
                break
            time.sleep(5)
        if d["Status"] != "FINISHED":
            raise RuntimeError(f"{d['Status']}: {d.get('Error')}")
        if warm:
            return None
        return rsd.get_statement_result(Id=sid)

    log("    warming the workgroup (cold start can take ~2 min)")
    run("SELECT 1", warm=True)

    sql_path = os.path.join(REPO, "services", "redshift", "validation",
                            "03_reconciliation.sql")
    raw = open(sql_path, encoding="utf-8").read()
    # Strip comment lines before splitting so a ';' inside prose cannot split a
    # statement.
    stripped = "\n".join(l for l in raw.split("\n")
                         if not l.strip().startswith("--"))
    statements = [s.strip() for s in stripped.split(";") if s.strip()]
    log(f"    {len(statements)} statements")

    report, passes, fails = [], 0, 0
    for i, sql in enumerate(statements, 1):
        try:
            res = run(sql)
        except RuntimeError as e:
            report.append(f"--- statement {i}: ERROR {e}\n")
            fails += 1
            continue

        cols = [c["name"] for c in res["ColumnMetadata"]]
        rows = []
        for rec in res["Records"]:
            vals = []
            for cell in rec:
                v = next((x for k, x in cell.items() if k != "isNull"), None)
                vals.append("" if cell.get("isNull") else str(v))
            rows.append(vals)
            if "verdict" in [c.lower() for c in cols]:
                idx = [c.lower() for c in cols].index("verdict")
                if idx < len(vals):
                    passes += vals[idx] == "PASS"
                    fails += vals[idx] == "FAIL"

        report.append(f"--- statement {i} " + "-" * 50)
        report.append(" | ".join(cols))
        report += [" | ".join(r) for r in rows]
        report.append("")

    header = [
        "Redshift star-schema reconciliation - captured before decommissioning",
        f"workgroup={WORKGROUP} database={DATABASE}",
        f"verdict rows: {passes} PASS / {fails} FAIL",
        "=" * 70, "",
    ]
    write_text("redshift-reconciliation.txt", "\n".join(header + report),
               f"reconciliation output - {passes} PASS / {fails} FAIL")
    log(f"    {passes} PASS / {fails} FAIL")


# ---------------------------------------------------------------- section 4
def section_4_stepfunctions():
    log("[4] Step Functions")
    sfn = boto3.client("stepfunctions", region_name=REGION)

    arn = sfn.list_state_machines()["stateMachines"][0]["stateMachineArn"]
    sm = sfn.describe_state_machine(stateMachineArn=arn)
    sm.pop("ResponseMetadata", None)
    write_json("stepfunctions/state-machine-definition.json", sm,
               "deployed state machine definition")

    execs = sfn.list_executions(stateMachineArn=arn, maxResults=100)["executions"]
    write_json("stepfunctions/executions.json", execs,
               f"{len(execs)} executions "
               f"({sum(e['status'] == 'SUCCEEDED' for e in execs)} succeeded, "
               f"{sum(e['status'] == 'FAILED' for e in execs)} failed)")

    # One of each outcome: the failure-then-fix arc is the interesting evidence.
    for status in ("SUCCEEDED", "FAILED"):
        pick = next((e for e in execs if e["status"] == status), None)
        if not pick:
            continue
        events = []
        token = None
        while True:
            kw = {"executionArn": pick["executionArn"], "maxResults": 1000}
            if token:
                kw["nextToken"] = token
            page = sfn.get_execution_history(**kw)
            events += page["events"]
            token = page.get("nextToken")
            if not token:
                break
        write_json(f"stepfunctions/history-{status.lower()}.json",
                   {"execution": pick, "events": events},
                   f"{status} execution history - {len(events)} events")


# ---------------------------------------------------------------- section 5
def section_5_glue_runs():
    log("[5] Glue job run history")
    glue = boto3.client("glue", region_name=REGION)

    all_runs, summary = {}, []
    for job in GLUE_JOBS:
        try:
            runs = glue.get_job_runs(JobName=job, MaxResults=200)["JobRuns"]
        except glue.exceptions.EntityNotFoundException:
            log(f"    -- {job}: not found, skipping")
            continue
        all_runs[job] = runs
        ok = sum(r["JobRunState"] == "SUCCEEDED" for r in runs)
        secs = [r.get("ExecutionTime", 0) for r in runs
                if r["JobRunState"] == "SUCCEEDED"]
        summary.append(
            f"{job:52s} {len(runs):3d} runs  {ok:3d} ok  "
            f"avg {int(sum(secs) / len(secs)) if secs else 0:5d}s  "
            f"max {max(secs) if secs else 0:5d}s"
        )
        log(f"    {job}: {len(runs)} runs")

    write_json("glue/job-runs.json", all_runs,
               f"full run history for {len(all_runs)} jobs")
    write_text("glue/job-runs-summary.txt",
               "Glue job run history\n" + "=" * 90 + "\n" +
               "\n".join(summary) + "\n",
               "per-job run counts and durations")


# ---------------------------------------------------------------- section 6
def section_6_cloudwatch_and_terraform():
    log("[6] CloudWatch + Terraform inventory")
    cw = boto3.client("cloudwatch", region_name=REGION)

    dashboards = cw.list_dashboards().get("DashboardEntries", [])
    bodies = {}
    for d in dashboards:
        body = cw.get_dashboard(DashboardName=d["DashboardName"])["DashboardBody"]
        bodies[d["DashboardName"]] = json.loads(body)
    write_json("cloudwatch/dashboards.json", bodies,
               f"{len(bodies)} CloudWatch dashboards")

    alarms = cw.describe_alarms()["MetricAlarms"]
    write_json("cloudwatch/alarms.json", alarms,
               f"{len(alarms)} metric alarms")
    log(f"    {len(dashboards)} dashboards, {len(alarms)} alarms")

    tf = os.path.join(REPO, "terraform")

    def terraform(*args):
        return subprocess.run(["terraform", "-chdir=" + tf, *args],
                              capture_output=True, text=True, timeout=300)

    r = terraform("state", "list")
    if r.returncode == 0:
        n = len([l for l in r.stdout.split("\n") if l.strip()])
        write_text("terraform-resource-inventory.txt",
                   f"# Terraform-managed resources at decommissioning: {n}\n\n"
                   + r.stdout,
                   f"{n} managed resources")
    else:
        log(f"    !! terraform state list failed: {r.stderr.strip()[:200]}")

    # Plain `output`, not `-json`: the plain form prints <sensitive> for
    # sensitive values, the JSON form emits them in clear.
    r = terraform("output")
    if r.returncode == 0:
        write_text("terraform-outputs.txt", r.stdout,
                   "terraform outputs (sensitive values redacted by terraform)")
    else:
        log(f"    !! terraform output failed: {r.stderr.strip()[:200]}")


# Descriptions survive a partial re-run, so the manifest stays meaningful even
# when only one section is executed.
E = "docs/evidence"
STATIC_NOTES = {
    f"{E}/quicksight/sheet-overview.pdf": "rendered sheet: Executive Overview",
    f"{E}/quicksight/sheet-time.pdf": "rendered sheet: Time & Demand",
    f"{E}/quicksight/sheet-geography.pdf": "rendered sheet: Geography (MDM Zones)",
    f"{E}/quicksight/sheet-vendor-payment.pdf": "rendered sheet: Vendor & Payment",
    f"{E}/quicksight/sheet-trip-behaviour.pdf": "rendered sheet: Trip Behaviour",
    f"{E}/quicksight/dashboard-definition.json": "dashboard definition - 5 sheets, 28 visuals",
    f"{E}/quicksight/dataset-nyc-taxi-trips-star.json": "SPICE dataset definition",
    f"{E}/redshift-reconciliation.txt": "reconciliation output - 18 PASS / 0 FAIL",
    f"{E}/stepfunctions/state-machine-definition.json": "deployed state machine definition",
    f"{E}/stepfunctions/executions.json": "5 executions - 2 succeeded, 3 failed",
    f"{E}/stepfunctions/history-succeeded.json": "SUCCEEDED execution, full event history",
    f"{E}/stepfunctions/history-failed.json": "FAILED execution, full event history",
    f"{E}/glue/job-runs.json": "full run history for 6 jobs",
    f"{E}/glue/job-runs-summary.txt": "39 runs - counts and durations per job",
    f"{E}/cloudwatch/dashboards.json": "1 CloudWatch dashboard",
    f"{E}/cloudwatch/alarms.json": "4 metric alarms",
    f"{E}/terraform-resource-inventory.txt": "131 Terraform-managed resources",
    f"{E}/terraform-outputs.txt": "terraform outputs, sensitive values redacted",
}

SECTIONS = {
    "1": section_1_quicksight_pdfs,
    "2": section_2_quicksight_definition,
    "3": section_3_redshift_reconciliation,
    "4": section_4_stepfunctions,
    "5": section_5_glue_runs,
    "6": section_6_cloudwatch_and_terraform,
}


def main():
    wanted = sys.argv[1:] or list(SECTIONS)
    os.makedirs(OUT, exist_ok=True)

    for key in wanted:
        try:
            SECTIONS[key]()
        except Exception as e:                       # keep going; report at end
            log(f"    !! section {key} failed: {type(e).__name__}: {e}")

    # Build the manifest from what is on disk, not from this run's records -
    # sections are runnable individually, and a partial run must not erase the
    # entries written by earlier ones.
    notes = dict(STATIC_NOTES)
    notes.update({rel: note for rel, _, note in manifest})
    lines = ["# Evidence manifest", "",
             "Captured from the live AWS account before decommissioning.",
             "Raw AWS identifiers are still present - run the scrub pass "
             "before staging.", "",
             "| Artifact | Bytes | What it shows |", "|---|---:|---|"]
    found = []
    for root, _, files in os.walk(OUT):
        for fn in sorted(files):
            if fn == "MANIFEST.md":
                continue
            full = os.path.join(root, fn)
            rel = os.path.relpath(full, REPO).replace("\\", "/")
            found.append((rel, os.path.getsize(full),
                          notes.get(rel, "captured in an earlier run")))
    for rel, size, note in sorted(found):
        lines.append(f"| `{rel}` | {size:,} | {note} |")
    lines += ["", f"**{len(found)} artifacts.**"]

    path = os.path.join(OUT, "MANIFEST.md")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    log(f"    wrote docs/evidence/MANIFEST.md ({len(found)} artifacts)")

    log(f"\ndone: {len(manifest)} artifacts under docs/evidence/")


if __name__ == "__main__":
    main()
