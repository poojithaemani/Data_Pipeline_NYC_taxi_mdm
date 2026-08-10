"""
Sync AWS Glue job run history into the pipeline_runs table.

Satisfies the operational-tracking requirement (PostgreSQL -> pipeline_runs)
without modifying any frozen ETL script. AWS Glue already holds authoritative
execution history for every job in the pipeline; this script mirrors it into
RDS so run history is queryable in SQL alongside the MDM data.

Design notes
------------
* run_id maps to the Glue JobRunId, which is the table's PRIMARY KEY. That
  makes the sync naturally idempotent via ON CONFLICT (run_id) DO NOTHING.
* pipeline_runs.completed_at is NOT NULL, so only finished runs are recorded.
  Still-running jobs are skipped and picked up on a later sync.
* records_processed is populated from the structured "Final job summary" JSON
  that golden_zone_etl writes to CloudWatch. The silver and gold jobs emit no
  structured summary, so their records_processed is left NULL rather than
  scraped from free-text log lines.

Usage
-----
    python scripts/sync_pipeline_runs.py [--dry-run]
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import sys
from typing import Any

import boto3
import psycopg2

logging.basicConfig(level=logging.INFO, format="%(asctime)s | %(levelname)s | %(message)s")
logger = logging.getLogger(__name__)

REGION = os.getenv("AWS_REGION", "us-east-2")

JOB_NAMES = [
    "nyc-taxi-mdm-platform-golden-zone-etl",
    "nyc-taxi-mdm-platform-yellow-taxi-silver-etl",
    "nyc-taxi-mdm-platform-yellow-taxi-gold-etl",
]

TERMINAL_STATES = {"SUCCEEDED", "FAILED", "ERROR", "TIMEOUT", "STOPPED"}

GLUE_LOG_GROUP = "/aws-glue/jobs/logs-v2"


def db_config() -> dict[str, Any]:
    """Read database connection settings from the environment."""
    return {
        "host": os.environ["DB_HOST"],
        "port": int(os.getenv("DB_PORT", "5432")),
        "dbname": os.getenv("DB_NAME", "taxi_mdm"),
        "user": os.environ["DB_USER"],
        "password": os.environ["DB_PASSWORD"],
        "connect_timeout": 15,
    }


def fetch_records_processed(logs_client, run_id: str) -> int | None:
    """Extract the record count from a job's structured CloudWatch summary.

    Only golden_zone_etl emits `Final job summary` as JSON. Returns None for
    jobs that do not, rather than parsing free-text log lines.
    """
    try:
        events = logs_client.get_log_events(
            logGroupName=GLUE_LOG_GROUP,
            logStreamName=f"{run_id}-driver",
            limit=10000,
        )["events"]
    except Exception:
        logger.debug("No driver log stream for %s", run_id)
        return None

    for event in events:
        message = event.get("message", "")
        if "Final job summary" not in message:
            continue
        start = message.find("{")
        if start == -1:
            continue
        try:
            summary = json.loads(message[start:])
        except json.JSONDecodeError:
            continue
        execution = summary.get("execution_summary", {})
        if execution:
            return sum(
                int(execution.get(key, 0))
                for key in ("inserted", "updated", "no_change")
            )
    return None


def collect_runs(glue_client, logs_client) -> list[tuple]:
    """Build one pipeline_runs row per completed Glue job run."""
    rows: list[tuple] = []

    for job_name in JOB_NAMES:
        job_start = len(rows)
        paginator = glue_client.get_paginator("get_job_runs")
        for page in paginator.paginate(JobName=job_name):
            for run in page.get("JobRuns", []):
                state = run.get("JobRunState")
                started = run.get("StartedOn")
                completed = run.get("CompletedOn")

                # completed_at is NOT NULL: skip runs that have not finished.
                if state not in TERMINAL_STATES or not started or not completed:
                    logger.info("Skipping in-flight run %s (%s)", run.get("Id"), state)
                    continue

                rows.append((
                    run["Id"],
                    job_name,
                    state,
                    fetch_records_processed(logs_client, run["Id"]),
                    started,
                    completed,
                ))

        logger.info("%s: collected %d completed run(s)", job_name, len(rows) - job_start)

    return rows


def upsert(rows: list[tuple]) -> int:
    """Insert run rows, skipping any already present. Returns rows inserted."""
    if not rows:
        logger.info("Nothing to sync.")
        return 0

    conn = psycopg2.connect(**db_config())
    try:
        with conn, conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) FROM pipeline_runs")
            before = cur.fetchone()[0]

            cur.executemany(
                """
                INSERT INTO pipeline_runs (
                    run_id, job_name, status, records_processed,
                    started_at, completed_at
                ) VALUES (%s, %s, %s, %s, %s, %s)
                ON CONFLICT (run_id) DO NOTHING
                """,
                rows,
            )

            cur.execute("SELECT COUNT(*) FROM pipeline_runs")
            after = cur.fetchone()[0]

        logger.info("pipeline_runs: %d -> %d (%d inserted)", before, after, after - before)
        return after - before
    finally:
        conn.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="Sync Glue job runs into pipeline_runs")
    parser.add_argument("--dry-run", action="store_true",
                        help="Collect and print rows without writing to the database")
    args = parser.parse_args()

    glue_client = boto3.client("glue", region_name=REGION)
    logs_client = boto3.client("logs", region_name=REGION)

    rows = collect_runs(glue_client, logs_client)
    logger.info("Collected %d completed run(s) across %d job(s)", len(rows), len(JOB_NAMES))

    if args.dry_run:
        for row in rows:
            logger.info("DRY RUN %s | %s | %s | records=%s", row[0][:24], row[1], row[2], row[3])
        return

    inserted = upsert(rows)
    logger.info("Sync complete. Rows inserted: %d", inserted)


if __name__ == "__main__":
    try:
        main()
    except KeyError as exc:
        logger.error("Missing required environment variable: %s", exc)
        sys.exit(1)
