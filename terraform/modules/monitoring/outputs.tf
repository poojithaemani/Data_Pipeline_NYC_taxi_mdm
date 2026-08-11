output "alerts_topic_arn" {
  description = "SNS topic that alarms, the EventBridge rule and the state machine's failure handler all publish to"
  value       = aws_sns_topic.alerts.arn
}

output "alerts_topic_name" {
  description = "Name of the alerts topic"
  value       = aws_sns_topic.alerts.name
}

output "dashboard_name" {
  description = "CloudWatch dashboard name"
  value       = aws_cloudwatch_dashboard.pipeline.dashboard_name
}

output "alarm_names" {
  description = "All alarms created by this module"
  value = [
    aws_cloudwatch_metric_alarm.pipeline_execution_failed.alarm_name,
    aws_cloudwatch_metric_alarm.pipeline_execution_timed_out.alarm_name,
    aws_cloudwatch_metric_alarm.pipeline_execution_duration.alarm_name,
    aws_cloudwatch_metric_alarm.redshift_compute_seconds.alarm_name,
  ]
}

output "glue_failure_rule_name" {
  description = "EventBridge rule watching for failed pipeline Glue job runs"
  value       = aws_cloudwatch_event_rule.glue_job_failed.name
}
