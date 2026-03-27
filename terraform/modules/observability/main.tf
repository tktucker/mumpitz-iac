# =============================================================================
# OBSERVABILITY MODULE — CloudWatch Alarms + Dashboard
# =============================================================================
#
# Creates five CloudWatch Alarms (all wired to the SNS topic for email alerts):
#   1. ALB5xxErrors      — any 5XX response from the load balancer
#   2. ALBHighLatency    — p99 response time > 2 seconds
#   3. UnhealthyHosts    — any target group host fails health checks
#   4. ECSHighCPU        — ECS service average CPU > 80% for 5 minutes
#   5. ECSHighMemory     — ECS service average memory > 80% for 5 minutes
#
# Creates one CloudWatch Dashboard with widgets for:
#   - ALB request count (total and 5XX)
#   - ALB target response time (average)
#   - ECS CPU and memory utilization
#   - ECS task count (running tasks)
# =============================================================================

variable "project_name"      { type = string }
variable "environment"       { type = string }
variable "region"            { type = string }
variable "alb_arn_suffix"    { type = string }  # e.g. "app/mumpitz-dev-alb/abc123"
variable "tg_blue_arn_suffix" { type = string } # e.g. "targetgroup/mumpitz-dev-tg-blue/xyz"
variable "ecs_cluster_name"  { type = string }
variable "ecs_service_name"  { type = string }
variable "sns_topic_arn"     { type = string }

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# =============================================================================
# CLOUDWATCH ALARMS
# =============================================================================

# -----------------------------------------------------------------------------
# 1. ALB 5XX Errors
# Fires when the load balancer returns any 5XX response — indicates the
# application or the load balancer itself is erroring.
# Threshold of 5 over 1 minute avoids single-request noise.
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${local.name_prefix}-alb-5xx-errors"
  alarm_description   = "${local.name_prefix}: ALB is returning 5XX errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 5
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]

  tags = { Name = "${local.name_prefix}-alb-5xx" }
}

# -----------------------------------------------------------------------------
# 2. ALB High Latency (p99 > 2s)
# p99 response time over 2 seconds indicates the application is struggling
# under load or has a slow code path affecting 1% of requests.
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "alb_latency" {
  alarm_name          = "${local.name_prefix}-alb-high-latency"
  alarm_description   = "${local.name_prefix}: ALB p99 response time exceeded 2 seconds"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  extended_statistic  = "p99"
  threshold           = 2
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]

  tags = { Name = "${local.name_prefix}-alb-latency" }
}

# -----------------------------------------------------------------------------
# 3. Unhealthy Hosts
# Fires immediately when any registered target fails its health check.
# This is the earliest signal of an ECS task crash or failed deployment.
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${local.name_prefix}-unhealthy-hosts"
  alarm_description   = "${local.name_prefix}: One or more ECS targets are failing health checks"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.tg_blue_arn_suffix
  }

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]

  tags = { Name = "${local.name_prefix}-unhealthy-hosts" }
}

# -----------------------------------------------------------------------------
# 4. ECS High CPU
# Sustained high CPU (> 80% for 5 consecutive minutes) indicates the service
# needs more tasks. Auto scaling should prevent this, but the alarm catches
# cases where scaling can't keep up or hits max_capacity.
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "ecs_cpu" {
  alarm_name          = "${local.name_prefix}-ecs-high-cpu"
  alarm_description   = "${local.name_prefix}: ECS service CPU exceeded 80% for 5 minutes"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 5
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.ecs_service_name
  }

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]

  tags = { Name = "${local.name_prefix}-ecs-cpu" }
}

# -----------------------------------------------------------------------------
# 5. ECS High Memory
# Memory pressure above 80% can cause OOM kills and task restarts.
# Unlike CPU, Fargate doesn't let tasks burst above the allocated memory.
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "ecs_memory" {
  alarm_name          = "${local.name_prefix}-ecs-high-memory"
  alarm_description   = "${local.name_prefix}: ECS service memory exceeded 80% for 5 minutes"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 5
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.ecs_service_name
  }

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]

  tags = { Name = "${local.name_prefix}-ecs-memory" }
}

# =============================================================================
# CLOUDWATCH DASHBOARD
# =============================================================================
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${local.name_prefix}-overview"

  dashboard_body = jsonencode({
    widgets = [
      # ── Row 1: ALB traffic overview ────────────────────────────────────────
      {
        type   = "metric"
        x      = 0; y = 0; width = 8; height = 6
        properties = {
          title  = "ALB Request Count"
          region = var.region
          view   = "timeSeries"
          stat   = "Sum"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix]
          ]
        }
      },
      {
        type   = "metric"
        x      = 8; y = 0; width = 8; height = 6
        properties = {
          title  = "ALB 5XX Errors"
          region = var.region
          view   = "timeSeries"
          stat   = "Sum"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", var.alb_arn_suffix, { color = "#d62728" }],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.alb_arn_suffix, { color = "#ff7f0e" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 16; y = 0; width = 8; height = 6
        properties = {
          title  = "ALB Target Response Time"
          region = var.region
          view   = "timeSeries"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, { stat = "Average", label = "Average" }],
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, { stat = "p99", label = "p99", color = "#d62728" }]
          ]
        }
      },

      # ── Row 2: ECS health ──────────────────────────────────────────────────
      {
        type   = "metric"
        x      = 0; y = 6; width = 8; height = 6
        properties = {
          title  = "ECS CPU Utilization"
          region = var.region
          view   = "timeSeries"
          stat   = "Average"
          period = 60
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", var.ecs_cluster_name, "ServiceName", var.ecs_service_name]
          ]
          annotations = {
            horizontal = [{ value = 80, label = "Alarm threshold", color = "#d62728" }]
          }
        }
      },
      {
        type   = "metric"
        x      = 8; y = 6; width = 8; height = 6
        properties = {
          title  = "ECS Memory Utilization"
          region = var.region
          view   = "timeSeries"
          stat   = "Average"
          period = 60
          metrics = [
            ["AWS/ECS", "MemoryUtilization", "ClusterName", var.ecs_cluster_name, "ServiceName", var.ecs_service_name]
          ]
          annotations = {
            horizontal = [{ value = 80, label = "Alarm threshold", color = "#d62728" }]
          }
        }
      },
      {
        type   = "metric"
        x      = 16; y = 6; width = 8; height = 6
        properties = {
          title  = "ALB Healthy / Unhealthy Hosts"
          region = var.region
          view   = "timeSeries"
          stat   = "Average"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", var.tg_blue_arn_suffix, "LoadBalancer", var.alb_arn_suffix, { label = "Healthy", color = "#2ca02c" }],
            ["AWS/ApplicationELB", "UnHealthyHostCount", "TargetGroup", var.tg_blue_arn_suffix, "LoadBalancer", var.alb_arn_suffix, { label = "Unhealthy", color = "#d62728" }]
          ]
        }
      },

      # ── Row 3: Alarm status overview ───────────────────────────────────────
      {
        type   = "alarm"
        x      = 0; y = 12; width = 24; height = 3
        properties = {
          title = "Active Alarms"
          alarms = [
            aws_cloudwatch_metric_alarm.alb_5xx.arn,
            aws_cloudwatch_metric_alarm.alb_latency.arn,
            aws_cloudwatch_metric_alarm.unhealthy_hosts.arn,
            aws_cloudwatch_metric_alarm.ecs_cpu.arn,
            aws_cloudwatch_metric_alarm.ecs_memory.arn
          ]
        }
      }
    ]
  })
}

# =============================================================================
# OUTPUTS
# =============================================================================
output "dashboard_name" { value = aws_cloudwatch_dashboard.main.dashboard_name }
output "dashboard_url" {
  value = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}
