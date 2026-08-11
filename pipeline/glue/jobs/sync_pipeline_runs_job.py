"""Glue Python Shell wrapper that runs scripts/sync_pipeline_runs.py in the VPC.

Why this exists
---------------
The security phase made the RDS instance private, so sync_pipeline_runs.py can
no longer reach the database from a workstation. Operational tracking is a
required deliverable, so the script needs to run somewhere inside the VPC.

A Glue Python Shell job is the smallest option that fits the existing
architecture: it reuses the Glue NETWORK connection, the Glue IAM role and the
Secrets Manager credential that the ETL jobs already use, and it needs no new
service. A Lambda would have meant a new runtime, a new role and a packaging
step for psycopg2.

Why it wraps rather than reimplements
-------------------------------------
scripts/sync_pipeline_runs.py is frozen. This wrapper does not copy, edit or
reimplement any of its logic - it downloads that exact file and executes it as
__main__. The sync behaviour, including the ON CONFLICT (run_id) DO NOTHING
idempotency, is whatever the frozen file says it is.

The frozen script reads its connection settings from the environment and takes
no arguments beyond an optional --dry-run, so the wrapper's whole job is to
populate os.environ from Secrets Manager and hand over a clean sys.argv.
"""

import json
import logging
import os
import runpy
import sys
import tempfile

import boto3
from awsglue.utils import getResolvedOptions

REQUIRED_ARGS = [
    "SCRIPT_S3_URI",
    "SECRET_ARN",
    "DB_HOST",
    "DB_PORT",
    "DB_NAME",
]


def _route_script_logging_to_stdout():
    """Make the frozen script's log output visible in the Glue output stream.

    The frozen script calls logging.basicConfig, which installs a stderr
    handler. Glue Python Shell captures stderr only for the setup phase, so
    the sync's own lines - including the "pipeline_runs: before -> after"
    tally that proves what it did - were being lost.

    Attaching a stdout handler to the root logger first means basicConfig
    becomes a no-op (it does nothing when handlers already exist) and every
    record propagates here instead. The frozen file is not touched.
    """
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(
        logging.Formatter("%(asctime)s | %(levelname)s | %(message)s")
    )
    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(logging.INFO)


def main():
    args = getResolvedOptions(sys.argv, REQUIRED_ARGS)
    _route_script_logging_to_stdout()

    # --dry-run is passed through when present so the job can be used to
    # preview a sync without writing, exactly as the script supports locally.
    dry_run = "--dry-run" in sys.argv

    secret = json.loads(
        boto3.client("secretsmanager")
        .get_secret_value(SecretId=args["SECRET_ARN"])["SecretString"]
    )

    os.environ["DB_HOST"] = args["DB_HOST"]
    os.environ["DB_PORT"] = args["DB_PORT"]
    os.environ["DB_NAME"] = args["DB_NAME"]
    os.environ["DB_USER"] = secret["username"]
    os.environ["DB_PASSWORD"] = secret["password"]
    os.environ.setdefault("AWS_REGION", os.environ.get("AWS_DEFAULT_REGION", "us-east-2"))

    bucket, _, key = args["SCRIPT_S3_URI"].removeprefix("s3://").partition("/")
    local_path = os.path.join(tempfile.gettempdir(), "sync_pipeline_runs.py")
    boto3.client("s3").download_file(bucket, key, local_path)
    print(f"Fetched frozen sync script from {args['SCRIPT_S3_URI']}")

    # The frozen script parses sys.argv with argparse, which rejects unknown
    # arguments - and Glue fills sys.argv with --JOB_NAME and friends. Replace
    # it with exactly what the script expects.
    sys.argv = ["sync_pipeline_runs.py"] + (["--dry-run"] if dry_run else [])

    print(f"Running frozen sync script (dry_run={dry_run})")
    try:
        runpy.run_path(local_path, run_name="__main__")
    except SystemExit as exit_signal:
        # argparse and the script's own exit paths raise SystemExit; a
        # non-zero code must fail the Glue job rather than pass silently.
        if exit_signal.code not in (0, None):
            raise RuntimeError(
                f"sync_pipeline_runs.py exited with code {exit_signal.code}"
            ) from exit_signal

    print("Sync complete.")


if __name__ == "__main__":
    main()
