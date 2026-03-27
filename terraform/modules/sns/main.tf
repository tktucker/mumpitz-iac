# =============================================================================
# SNS MODULE — Pipeline notification emails
#
# Sends an email to var.notification_email whenever the CodePipeline
# execution reaches a FAILED or SUCCEEDED terminal state.
#
# How it works:
#   EventBridge rule  →  SNS topic  →  Email subscription
#
# NOTE: After the first `terragrunt apply`, AWS sends a confirmation email to
# var.notification_email. Notifications will not arrive until the subscriber
# clicks "Confirm subscription" in that email.
# =============================================================================

variable "project_name"       { type = string }
variable "environment"        { type = string }
variable "region"             { type = string }
variable "account_id"         { type = string }
variable "notification_email" { type = string }
variable "pipeline_name"      { type = string }

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# -----------------------------------------------------------------------------
# SNS Topic
# -----------------------------------------------------------------------------
resource "aws_sns_topic" "pipeline_notifications" {
  name = "${local.name_prefix}-pipeline-notifications"

  tags = { Name = "${local.name_prefix}-pipeline-notifications" }
}

# -----------------------------------------------------------------------------
# SNS Topic Policy — allow EventBridge to publish
# -----------------------------------------------------------------------------
resource "aws_sns_topic_policy" "pipeline_notifications" {
  arn = aws_sns_topic.pipeline_notifications.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEventBridgePublish"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.pipeline_notifications.arn
        Condition = {
          ArnLike = {
            "aws:SourceArn" = "arn:aws:events:${var.region}:${var.account_id}:rule/*"
          }
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Email Subscription
# -----------------------------------------------------------------------------
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.pipeline_notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# -----------------------------------------------------------------------------
# EventBridge Rule — watch for pipeline FAILED or SUCCEEDED
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "pipeline_state" {
  name        = "${local.name_prefix}-pipeline-state-change"
  description = "Fires when ${var.pipeline_name} reaches FAILED or SUCCEEDED"

  event_pattern = jsonencode({
    source      = ["aws.codepipeline"]
    "detail-type" = ["CodePipeline Pipeline Execution State Change"]
    detail = {
      state    = ["FAILED", "SUCCEEDED"]
      pipeline = [var.pipeline_name]
    }
  })

  tags = { Name = "${local.name_prefix}-pipeline-state-change" }
}

# -----------------------------------------------------------------------------
# EventBridge Target — publish to SNS with a human-readable message
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_event_target" "pipeline_sns" {
  rule      = aws_cloudwatch_event_rule.pipeline_state.name
  target_id = "PipelineNotificationSNS"
  arn       = aws_sns_topic.pipeline_notifications.arn

  input_transformer {
    input_paths = {
      pipeline  = "$.detail.pipeline"
      state     = "$.detail.state"
      execution = "$.detail.execution-id"
      time      = "$.time"
    }
    # Produces a plain-text email body
    input_template = "\"CodePipeline Notification\\n\\nPipeline:     <pipeline>\\nStatus:       <state>\\nExecution ID: <execution>\\nTime:         <time>\""
  }
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
output "topic_arn" { value = aws_sns_topic.pipeline_notifications.arn }
