############################################
# Pipeline observability
#
# Additive module: an alerts topic, one EventBridge rule, five alarms and one
# dashboard. It creates no compute, touches no data, and modifies no existing
# resource. modules/cloudwatch is deliberately left byte-identical - its three
# log groups are already wired and in use.
############################################

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  state_machine_arn = "arn:aws:states:${var.aws_region}:${local.account_id}:stateMachine:${var.state_machine_name}"

  # Glue publishes its aggregate metrics with a JobRunId dimension, so a plain
  # metric alarm cannot span runs. A SEARCH expression collapses every run of
  # the pipeline's jobs into one series that an alarm can evaluate.
  glue_failed_tasks_search = format(
    "SUM(SEARCH('{Glue,JobName,JobRunId,Type} MetricName=\"glue.driver.aggregate.numFailedTasks\" (%s)', 'Sum', 300))",
    join(" OR ", [for job in var.glue_job_names : "JobName=\"${job}\""])
  )
}

############################################
# Alerts topic
############################################

resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"

  tags = {
    Name        = "${var.project_name}-alerts"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

data "aws_iam_policy_document" "alerts" {
  statement {
    sid    = "AllowCloudWatchAndEventBridgePublish"
    effect = "Allow"

    principals {
      type = "Service"
      identifiers = [
        "cloudwatch.amazonaws.com",
        "events.amazonaws.com",
      ]
    }

    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_sns_topic_policy" "alerts" {
  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.alerts.json
}

# Optional: only created when an address is supplied. The subscription stays
# in "pending confirmation" until the emailed link is clicked.
resource "aws_sns_topic_subscription" "alerts_email" {
  count = var.alert_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

############################################
# EventBridge - Glue job failures
#
# The state machine's own Catch handler already notifies on any failure inside
# an orchestrated run. This rule additionally catches jobs that fail when
# started outside the state machine, which is how they are run today.
############################################

resource "aws_cloudwatch_event_rule" "glue_job_failed" {
  name        = "${var.project_name}-glue-job-failed"
  description = "Any pipeline Glue job reaching a failed terminal state"

  event_pattern = jsonencode({
    source      = ["aws.glue"]
    detail-type = ["Glue Job State Change"]
    detail = {
      jobName = var.glue_job_names
      state   = ["FAILED", "TIMEOUT", "ERROR"]
    }
  })

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_cloudwatch_event_target" "glue_job_failed" {
  rule      = aws_cloudwatch_event_rule.glue_job_failed.name
  target_id = "alerts-topic"
  arn       = aws_sns_topic.alerts.arn
}

############################################
# Alarms
#
# All alarms treat missing data as not breaching: the pipeline is run on
# demand, so long stretches with no datapoints are the normal state.
############################################

resource "aws_cloudwatch_metric_alarm" "pipeline_execution_failed" {
  alarm_name        = "${var.project_name}-pipeline-execution-failed"
  alarm_description = "A pipeline state machine execution failed. This is the authoritative failure signal: every stage routes its Catch handler through the same failure path."

  namespace   = "AWS/States"
  metric_name = "ExecutionsFailed"
  dimensions  = { StateMachineArn = local.state_machine_arn }

  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_cloudwatch_metric_alarm" "pipeline_execution_timed_out" {
  alarm_name        = "${var.project_name}-pipeline-execution-timed-out"
  alarm_description = "A pipeline state machine execution hit its overall timeout."

  namespace   = "AWS/States"
  metric_name = "ExecutionsTimedOut"
  dimensions  = { StateMachineArn = local.state_machine_arn }

  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_cloudwatch_metric_alarm" "pipeline_execution_duration" {
  alarm_name        = "${var.project_name}-pipeline-execution-duration-high"
  alarm_description = "A pipeline execution ran far longer than the measured baseline of roughly 12 minutes."

  namespace   = "AWS/States"
  metric_name = "ExecutionTime"
  dimensions  = { StateMachineArn = local.state_machine_arn }

  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.pipeline_duration_alarm_ms
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# NOTE - why there is no metric alarm for Glue task failures.
#
# Glue publishes glue.driver.aggregate.numFailedTasks with a JobRunId
# dimension, so no fixed-dimension alarm can span runs. Collapsing the runs
# needs a SEARCH expression, and CloudWatch rejects those on alarms:
# PutMetricAlarm returns "SEARCH is not supported on Metric Alarms". SEARCH is
# a dashboard-only feature, so the expression is charted below instead.
#
# Glue job failure is therefore alarmed on two paths that are strictly better
# than a task-failure count, because a failed Spark task can be retried and the
# job still succeed:
#
#   - aws_cloudwatch_event_rule.glue_job_failed  -> any job reaching FAILED,
#     TIMEOUT or ERROR, whether or not the state machine started it
#   - aws_cloudwatch_metric_alarm.pipeline_execution_failed -> any stage
#     failing inside an orchestrated run
resource "aws_cloudwatch_metric_alarm" "redshift_compute_seconds" {
  alarm_name        = "${var.project_name}-redshift-compute-seconds-high"
  alarm_description = "Redshift Serverless RPU-seconds over a rolling day exceeded the expected ceiling. This is the project's main running cost, so it is alarmed as a budget guard."

  namespace   = "AWS/Redshift-Serverless"
  metric_name = "ComputeSeconds"
  dimensions  = { Workgroup = var.redshift_workgroup_name }

  statistic           = "Sum"
  period              = 86400
  evaluation_periods  = 1
  threshold           = var.redshift_compute_seconds_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

############################################
# Dashboard
############################################

resource "aws_cloudwatch_dashboard" "pipeline" {
  dashboard_name = "${var.project_name}-pipeline"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 2
        properties = {
          markdown = "# ${var.project_name} - pipeline\nSilver -> Gold -> Golden Zone -> Warehouse Export -> Redshift COPY -> QuickSight SPICE refresh, orchestrated by **${var.state_machine_name}**. The pipeline runs on demand, so gaps in these charts are expected."
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 2
        width  = 12
        height = 6
        properties = {
          title  = "Step Functions executions"
          view   = "timeSeries"
          region = var.aws_region
          stat   = "Sum"
          period = 300
          metrics = [
            ["AWS/States", "ExecutionsStarted", "StateMachineArn", local.state_machine_arn],
            [".", "ExecutionsSucceeded", ".", "."],
            [".", "ExecutionsFailed", ".", "."],
            [".", "ExecutionsTimedOut", ".", "."],
            [".", "ExecutionsAborted", ".", "."],
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 2
        width  = 12
        height = 6
        properties = {
          title  = "Pipeline execution duration (ms)"
          view   = "timeSeries"
          region = var.aws_region
          stat   = "Maximum"
          period = 300
          metrics = [
            ["AWS/States", "ExecutionTime", "StateMachineArn", local.state_machine_arn],
          ]
          annotations = {
            horizontal = [
              {
                label = "duration alarm"
                value = var.pipeline_duration_alarm_ms
              },
            ]
          }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 8
        width  = 12
        height = 6
        properties = {
          title  = "Glue job elapsed time per run (ms)"
          view   = "timeSeries"
          region = var.aws_region
          period = 300
          metrics = [
            for job in var.glue_job_names : [
              {
                expression = "SEARCH('{Glue,JobName,JobRunId,Type} MetricName=\"glue.driver.aggregate.elapsedTime\" JobName=\"${job}\"', 'Maximum', 300)"
                label      = job
                id         = "e${index(var.glue_job_names, job)}"
              }
            ]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 8
        width  = 12
        height = 6
        properties = {
          title  = "Glue failed Spark tasks"
          view   = "timeSeries"
          region = var.aws_region
          period = 300
          metrics = [
            [
              {
                expression = local.glue_failed_tasks_search
                label      = "Failed tasks (all pipeline jobs)"
                id         = "failed_tasks"
              }
            ]
          ]
          annotations = {
            horizontal = [
              {
                label = "task failure watch level"
                value = var.glue_failed_tasks_threshold
              },
            ]
          }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 14
        width  = 12
        height = 6
        properties = {
          title  = "Redshift Serverless capacity and usage"
          view   = "timeSeries"
          region = var.aws_region
          period = 300
          metrics = [
            ["AWS/Redshift-Serverless", "ComputeCapacity", "Workgroup", var.redshift_workgroup_name, { stat = "Average", label = "RPU capacity" }],
            ["AWS/Redshift-Serverless", "ComputeSeconds", "Workgroup", var.redshift_workgroup_name, { stat = "Sum", label = "RPU-seconds" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 14
        width  = 12
        height = 6
        properties = {
          title  = "Redshift query activity"
          view   = "timeSeries"
          region = var.aws_region
          period = 300
          metrics = [
            ["AWS/Redshift-Serverless", "QueriesCompletedPerSecond", "Workgroup", var.redshift_workgroup_name, { stat = "Average" }],
            ["AWS/Redshift-Serverless", "QueryDuration", "Workgroup", var.redshift_workgroup_name, { stat = "Average" }],
            ["AWS/Redshift-Serverless", "QueriesRunning", "Workgroup", var.redshift_workgroup_name, { stat = "Maximum" }],
          ]
        }
      },
    ]
  })
}
