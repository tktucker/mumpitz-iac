# =============================================================================
# CODEDEPLOY MODULE — ECS Blue/Green Deployment
# =============================================================================
#
# ECS blue/green with CodeDeploy requires three things aligned:
#   1. ECS service with deployment_controller = "CODE_DEPLOY"
#   2. Two ALB target groups (blue receives prod traffic, green receives test)
#   3. Two ALB listeners (port 443 prod HTTPS, port 8080 test/green HTTP)
#      Port 80 does a static HTTP→HTTPS redirect and is NOT managed by CodeDeploy.
#
# CodeDeploy deployment lifecycle:
#   1. Register new task definition revision
#   2. Start replacement (green) task set in the green target group
#   3. Wait for green tasks to pass health checks
#   4. Shift test traffic (port 8080) to green — run integration tests
#   5. Shift production traffic (port 443) to green
#   6. Wait termination_wait_time minutes
#   7. Terminate original (blue) task set
#
# Deployment configs for exam study:
#   ECSAllAtOnce                       — instant 100% shift (fastest)
#   ECSCanary10Percent5Minutes         — 10% for 5 min, then 100%
#   ECSCanary10Percent15Minutes        — 10% for 15 min, then 100%
#   ECSLinear10PercentEvery1Minutes    — 10% more per minute
#   ECSLinear10PercentEvery3Minutes    — 10% more every 3 minutes
# =============================================================================

variable "project_name"          { type = string }
variable "environment"           { type = string }
variable "app_name"              { type = string }

locals { name_prefix = "${var.project_name}-${var.environment}" }
variable "ecs_cluster_name"      { type = string }
variable "ecs_service_name"      { type = string }
# CodeDeploy manages the production listener during blue/green.
# The HTTPS (443) listener is used as the production listener so that traffic
# shifting applies to encrypted traffic. HTTP (80) does a static redirect to
# HTTPS and is not managed by CodeDeploy.
variable "alb_https_listener_arn" { type = string }
variable "tg_blue_name"          { type = string }
variable "tg_green_name"         { type = string }
variable "codedeploy_role_arn"   { type = string }
variable "deployment_config"     { type = string }
variable "termination_wait_time" { type = number }

# CodeDeploy Application — the logical container for deployment groups
resource "aws_codedeploy_app" "main" {
  name             = "${local.name_prefix}-${var.app_name}"
  compute_platform = "ECS"
}

# Deployment Group — wires together ECS service, ALB, target groups, and strategy
resource "aws_codedeploy_deployment_group" "main" {
  app_name               = aws_codedeploy_app.main.name
  deployment_group_name  = "${local.name_prefix}-${var.app_name}-dg"
  service_role_arn       = var.codedeploy_role_arn
  deployment_config_name = var.deployment_config

  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }

  blue_green_deployment_config {
    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }

    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = var.termination_wait_time
    }
  }

  ecs_service {
    cluster_name = var.ecs_cluster_name
    service_name = var.ecs_service_name
  }

  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = [var.alb_https_listener_arn]
      }

      target_group {
        name = var.tg_blue_name
      }

      target_group {
        name = var.tg_green_name
      }
    }
  }

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE"]
  }
}

# =============================================================================
# OUTPUTS
# =============================================================================
output "app_name"              { value = aws_codedeploy_app.main.name }
output "deployment_group_name" { value = aws_codedeploy_deployment_group.main.deployment_group_name }
