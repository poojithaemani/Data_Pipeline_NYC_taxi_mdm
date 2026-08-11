variable "project_name" {
  description = "Project name prefix"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "aws_region" {
  description = "Region the monitored resources live in"
  type        = string
}

variable "state_machine_name" {
  description = "Name of the pipeline state machine. Taken as a plain string rather than an output of the stepfunctions module: the alarms reference the state machine and the state machine references this module's SNS topic, so consuming the output directly would create a dependency cycle."
  type        = string
}

variable "glue_job_names" {
  description = "Glue jobs to watch for failures and to chart"
  type        = list(string)
}

variable "redshift_workgroup_name" {
  description = "Redshift Serverless workgroup to chart and alarm on"
  type        = string
}

############################################
# Notification
############################################

variable "alert_email" {
  description = "Optional email address subscribed to the alerts topic. Left empty by default because a subscription must be confirmed out of band; set it and confirm the emailed link to receive alerts."
  type        = string
  default     = ""
}

############################################
# Alarm thresholds
############################################

variable "pipeline_duration_alarm_ms" {
  description = "Alarm when a single state machine execution exceeds this duration. Measured full pipeline is roughly 12 minutes, so 45 minutes flags a genuinely stuck run without firing on a slow one."
  type        = number
  default     = 2700000
}

variable "glue_failed_tasks_threshold" {
  description = "Reference line drawn on the Glue task-failure chart. Not an alarm threshold: CloudWatch rejects SEARCH expressions on alarms, and Glue's task metrics carry a JobRunId dimension, so job failure is alarmed via the EventBridge rule instead. See the note in main.tf."
  type        = number
  default     = 5
}

variable "redshift_compute_seconds_threshold" {
  description = "Daily RPU-seconds ceiling for the Redshift Serverless workgroup. Default of 43200 is roughly 1.5 hours at 8 RPU, comfortably above the pipeline's own usage, so it fires on runaway or unexpected query load rather than on normal operation."
  type        = number
  default     = 43200
}
