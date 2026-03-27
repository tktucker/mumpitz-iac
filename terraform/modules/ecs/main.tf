# =============================================================================
# ECS MODULE — Fargate Cluster, Service, ALB (Blue/Green Target Groups)
# =============================================================================
#
# ECS CodeDeploy blue/green requires:
#   1. Deployment controller type = "CODE_DEPLOY" on the ECS service
#   2. Two ALB target groups (blue + green)
#   3. Two ALB listeners (production on :80, test/green on :8080)
#   4. CodeDeploy manages swapping traffic between target groups
#
# Fargate Spot: set use_spot = true (dev/staging) to save ~70% on compute.
# Fargate Spot instances can be interrupted with 2-minute notice; CodeDeploy
# blue/green ensures zero-downtime replacements when interruptions occur.
#
# Auto Scaling: scales the ECS service between min_capacity and max_capacity
# based on average CPU utilization (target: 70%). Scales out when busy,
# scales in when idle to reduce cost.
# =============================================================================

variable "project_name"      { type = string }
variable "environment"       { type = string }
variable "app_name"          { type = string }
variable "app_port"          { type = number }
variable "app_cpu"           { type = number }
variable "app_memory"        { type = number }
variable "desired_count"     { type = number }
variable "ecr_image_url"     { type = string }
variable "vpc_id"            { type = string }
variable "public_subnets"    { type = list(string) }
variable "private_subnets"   { type = list(string) }
variable "task_exec_role"    { type = string }
variable "task_role"         { type = string }
variable "alb_sg_id"         { type = string }
variable "ecs_sg_id"         { type = string }

# New variables for modernization
variable "use_spot" {
  type    = bool
  default = false # true = FARGATE_SPOT (dev/staging)
}
variable "log_retention_days" {
  type    = number
  default = 30 # CloudWatch log retention
}
variable "min_capacity" {
  type    = number
  default = 1 # Auto scaling minimum
}
variable "max_capacity" {
  type    = number
  default = 4 # Auto scaling maximum
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# -----------------------------------------------------------------------------
# ECS Cluster
# -----------------------------------------------------------------------------
resource "aws_ecs_cluster" "main" {
  name = "${local.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${local.name_prefix}/${var.app_name}"
  retention_in_days = var.log_retention_days
}

# -----------------------------------------------------------------------------
# ECS Task Definition
# CodeDeploy will register a NEW task definition revision on each deployment;
# this initial definition gives Fargate something to start with.
# -----------------------------------------------------------------------------
resource "aws_ecs_task_definition" "app" {
  family                   = "${local.name_prefix}-${var.app_name}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.app_cpu
  memory                   = var.app_memory
  execution_role_arn       = var.task_exec_role
  task_role_arn            = var.task_role

  container_definitions = jsonencode([
    {
      name      = var.app_name
      image     = var.ecr_image_url
      essential = true

      portMappings = [
        {
          containerPort = var.app_port
          hostPort      = var.app_port
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "FLASK_ENV",  value = var.environment },
        { name = "APP_PORT",   value = tostring(var.app_port) }
      ]

      healthCheck = {
        command     = ["CMD-SHELL", "python -c 'import urllib.request; urllib.request.urlopen(\"http://localhost:${var.app_port}/health\")' || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

data "aws_region" "current" {}

# -----------------------------------------------------------------------------
# Application Load Balancer
# -----------------------------------------------------------------------------
resource "aws_lb" "main" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_sg_id]
  subnets            = var.public_subnets

  enable_deletion_protection = false  # Set true in production

  tags = { Name = "${local.name_prefix}-alb" }
}

# Blue Target Group — receives production traffic
resource "aws_lb_target_group" "blue" {
  name        = "${local.name_prefix}-tg-blue"
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"  # Required for Fargate (awsvpc networking)

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Green Target Group — receives test traffic, then swapped to production
resource "aws_lb_target_group" "green" {
  name        = "${local.name_prefix}-tg-green"
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Production listener — port 80 → permanent redirect to HTTPS
# The HTTP→HTTPS redirect is handled by the ALB, not by the application.
# CodeDeploy manages the HTTPS (443) listener; Terraform fully owns this redirect.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# Test listener — port 8080 → green target group
# Allows testing the green deployment before shifting production traffic
resource "aws_lb_listener" "test" {
  load_balancer_arn = aws_lb.main.arn
  port              = 8080
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.green.arn
  }

  lifecycle {
    ignore_changes = [default_action]
  }
}

# -----------------------------------------------------------------------------
# ECS Service
#
# launch_type is NOT set — capacity_provider_strategy controls scheduling.
# With use_spot = true (dev/staging), tasks run on FARGATE_SPOT (~70% cheaper).
# With use_spot = false (prod), tasks run on standard FARGATE.
#
# NOTE: deployment_circuit_breaker is NOT supported with CODE_DEPLOY controller.
# CodeDeploy's auto_rollback_configuration in the codedeploy module handles
# automatic rollback on deployment failure.
# -----------------------------------------------------------------------------
resource "aws_ecs_service" "app" {
  name            = "${local.name_prefix}-${var.app_name}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count

  # Use FARGATE_SPOT for dev/staging (cost savings), FARGATE for prod (reliability)
  dynamic "capacity_provider_strategy" {
    for_each = var.use_spot ? [1] : []
    content {
      capacity_provider = "FARGATE_SPOT"
      weight            = 100
      base              = 1
    }
  }

  dynamic "capacity_provider_strategy" {
    for_each = var.use_spot ? [] : [1]
    content {
      capacity_provider = "FARGATE"
      weight            = 100
      base              = 1
    }
  }

  network_configuration {
    subnets          = var.private_subnets
    security_groups  = [var.ecs_sg_id]
    assign_public_ip = false  # Private subnet + NAT Gateway
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.blue.arn
    container_name   = var.app_name
    container_port   = var.app_port
  }

  # CRITICAL: Must be CODE_DEPLOY for ECS blue/green deployments
  deployment_controller {
    type = "CODE_DEPLOY"
  }

  # These lifecycle rules prevent Terraform from fighting CodeDeploy
  # CodeDeploy will change the task definition and load balancer on each deploy
  lifecycle {
    ignore_changes = [
      task_definition,
      load_balancer,
      desired_count,
      capacity_provider_strategy  # CodeDeploy may adjust during deployment
    ]
  }

  depends_on = [aws_lb_listener.http]
}

# -----------------------------------------------------------------------------
# Application Auto Scaling
#
# Registers the ECS service as a scalable target and configures CPU-based
# target tracking. When average CPU > 70%, ECS adds tasks (scale out).
# When average CPU drops below 70%, ECS removes tasks (scale in).
#
# Scale-out is fast (60s cooldown); scale-in is conservative (300s cooldown)
# to avoid thrashing under bursty traffic.
# -----------------------------------------------------------------------------
resource "aws_appautoscaling_target" "ecs" {
  max_capacity       = var.max_capacity
  min_capacity       = var.min_capacity
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "ecs_cpu" {
  name               = "${local.name_prefix}-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    target_value       = 70.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

# =============================================================================
# OUTPUTS
# =============================================================================
output "cluster_name"        { value = aws_ecs_cluster.main.name }
output "cluster_arn"         { value = aws_ecs_cluster.main.arn }
output "service_name"        { value = aws_ecs_service.app.name }
output "alb_dns_name"        { value = aws_lb.main.dns_name }
output "alb_zone_id"         { value = aws_lb.main.zone_id }  # Required for Route53 ALIAS records
output "alb_arn"             { value = aws_lb.main.arn }
output "alb_listener_arn"    { value = aws_lb_listener.http.arn }
output "tg_blue_name"        { value = aws_lb_target_group.blue.name }
output "tg_blue_arn"         { value = aws_lb_target_group.blue.arn }
output "tg_green_name"       { value = aws_lb_target_group.green.name }
output "task_definition_arn" { value = aws_ecs_task_definition.app.arn }
