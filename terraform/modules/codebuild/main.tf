# =============================================================================
# CODEBUILD MODULE — One project per pipeline stage
# =============================================================================
#
# Five CodeBuild projects, each running a buildspec from the app-repo root:
#   lint        — buildspecs/buildspec-lint.yml        (flake8)
#   unit-test   — buildspecs/buildspec-test.yml        (pytest + coverage ≥ 80%)
#   security    — buildspecs/buildspec-security.yml    (bandit + pip-audit)
#   build       — buildspecs/buildspec-build.yml       (docker build + ECR push)
#   integration — buildspecs/buildspec-integration.yml (pytest vs live ALB)
#
# All projects run inside the VPC (private subnets) so they can reach the
# ECS service for integration tests and ECR via NAT gateway.
#
# CodeBuild environment variables are passed at project creation.
# Sensitive values should use parameter-store or secrets-manager type.
# =============================================================================

variable "project_name"         { type = string }
variable "environment"          { type = string }
variable "app_name"             { type = string }
variable "app_port"             { type = number }
variable "compute_type"         { type = string }
variable "build_image"          { type = string }
variable "codebuild_role_arn"   { type = string }
variable "ecr_repo_url"         { type = string }
variable "account_id"           { type = string }
variable "region"               { type = string }
variable "vpc_id"               { type = string }
variable "private_subnets"      { type = list(string) }
variable "codebuild_sg_id"      { type = string }
variable "alb_dns_name"         { type = string }
variable "domain_name"          { type = string }
variable "task_exec_role_arn"   { type = string }
variable "task_role_arn"        { type = string }

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  common_env = [
    { name = "APP_NAME",       value = var.app_name,           type = "PLAINTEXT" },
    { name = "APP_PORT",       value = tostring(var.app_port), type = "PLAINTEXT" },
    { name = "ECR_REPO_URL",   value = var.ecr_repo_url,       type = "PLAINTEXT" },
    { name = "AWS_ACCOUNT_ID", value = var.account_id,         type = "PLAINTEXT" },
    { name = "NAME_PREFIX",    value = local.name_prefix,      type = "PLAINTEXT" },
  ]
}

# -----------------------------------------------------------------------------
# Stage 2: Lint — flake8 + pylint
# -----------------------------------------------------------------------------
resource "aws_codebuild_project" "lint" {
  name          = "${local.name_prefix}-lint"
  description   = "Lint stage: flake8 static analysis"
  service_role  = var.codebuild_role_arn
  build_timeout = 10

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspecs/buildspec-lint.yml"
  }

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = var.compute_type
    image                       = var.build_image
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    dynamic "environment_variable" {
      for_each = local.common_env
      content {
        name  = environment_variable.value.name
        value = environment_variable.value.value
        type  = environment_variable.value.type
      }
    }
  }

  cache {
    type  = "LOCAL"
    modes = ["LOCAL_SOURCE_CACHE"]
  }

  vpc_config {
    vpc_id             = var.vpc_id
    subnets            = var.private_subnets
    security_group_ids = [var.codebuild_sg_id]
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "/aws/codebuild/${local.name_prefix}-lint"
      stream_name = "build"
    }
  }

  tags = { Name = "${local.name_prefix}-lint" }
}

# -----------------------------------------------------------------------------
# Stage 3: Unit Test — pytest + coverage gate
# -----------------------------------------------------------------------------
resource "aws_codebuild_project" "unit_test" {
  name          = "${local.name_prefix}-unit-test"
  description   = "Unit test stage: pytest with ≥80% coverage gate"
  service_role  = var.codebuild_role_arn
  build_timeout = 15

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspecs/buildspec-test.yml"
  }

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = var.compute_type
    image                       = var.build_image
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    dynamic "environment_variable" {
      for_each = local.common_env
      content {
        name  = environment_variable.value.name
        value = environment_variable.value.value
        type  = environment_variable.value.type
      }
    }
  }

  cache {
    type  = "LOCAL"
    modes = ["LOCAL_SOURCE_CACHE"]
  }

  vpc_config {
    vpc_id             = var.vpc_id
    subnets            = var.private_subnets
    security_group_ids = [var.codebuild_sg_id]
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "/aws/codebuild/${local.name_prefix}-unit-test"
      stream_name = "build"
    }
  }

  tags = { Name = "${local.name_prefix}-unit-test" }
}

# -----------------------------------------------------------------------------
# Stage 4: Security Scan — bandit + pip-audit
# -----------------------------------------------------------------------------
resource "aws_codebuild_project" "security" {
  name          = "${local.name_prefix}-security"
  description   = "Security scan stage: bandit SAST + pip-audit dependency check"
  service_role  = var.codebuild_role_arn
  build_timeout = 10

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspecs/buildspec-security.yml"
  }

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = var.compute_type
    image                       = var.build_image
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    dynamic "environment_variable" {
      for_each = local.common_env
      content {
        name  = environment_variable.value.name
        value = environment_variable.value.value
        type  = environment_variable.value.type
      }
    }
  }

  cache {
    type  = "LOCAL"
    modes = ["LOCAL_SOURCE_CACHE"]
  }

  vpc_config {
    vpc_id             = var.vpc_id
    subnets            = var.private_subnets
    security_group_ids = [var.codebuild_sg_id]
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "/aws/codebuild/${local.name_prefix}-security"
      stream_name = "build"
    }
  }

  tags = { Name = "${local.name_prefix}-security" }
}

# -----------------------------------------------------------------------------
# Stage 5: Build — Docker build + ECR push
# Produces taskdef.json and imagedefinitions.json as BuildArtifacts
# -----------------------------------------------------------------------------
resource "aws_codebuild_project" "build" {
  name          = "${local.name_prefix}-build"
  description   = "Build stage: docker build, ECR push, generate taskdef.json"
  service_role  = var.codebuild_role_arn
  build_timeout = 20

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspecs/buildspec-build.yml"
  }

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = var.compute_type
    image                       = var.build_image
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true  # Required for docker build inside CodeBuild

    dynamic "environment_variable" {
      for_each = local.common_env
      content {
        name  = environment_variable.value.name
        value = environment_variable.value.value
        type  = environment_variable.value.type
      }
    }

    # Role ARNs are injected here so taskdef.json uses the correct
    # environment-prefixed names (e.g. mumpitz-dev-ecs-task-role)
    # rather than hardcoded strings that break across environments.
    environment_variable {
      name  = "TASK_EXEC_ROLE_ARN"
      value = var.task_exec_role_arn
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "TASK_ROLE_ARN"
      value = var.task_role_arn
      type  = "PLAINTEXT"
    }
  }

  # Build project gets both docker layer cache and source cache.
  # Layer cache avoids re-downloading base image layers on each build.
  # Source cache skips git fetch when the same commit is rebuilt.
  cache {
    type  = "LOCAL"
    modes = ["LOCAL_DOCKER_LAYER_CACHE", "LOCAL_SOURCE_CACHE"]
  }

  vpc_config {
    vpc_id             = var.vpc_id
    subnets            = var.private_subnets
    security_group_ids = [var.codebuild_sg_id]
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "/aws/codebuild/${local.name_prefix}-build"
      stream_name = "build"
    }
  }

  tags = { Name = "${local.name_prefix}-build" }
}

# -----------------------------------------------------------------------------
# Stage 7: Integration Test — pytest against the live ALB
# Runs AFTER CodeDeploy completes the blue/green deployment
# -----------------------------------------------------------------------------
resource "aws_codebuild_project" "integration" {
  name          = "${local.name_prefix}-integration"
  description   = "Integration test stage: pytest against live ALB endpoint"
  service_role  = var.codebuild_role_arn
  build_timeout = 15

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspecs/buildspec-integration.yml"
  }

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = var.compute_type
    image                       = var.build_image
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    dynamic "environment_variable" {
      for_each = local.common_env
      content {
        name  = environment_variable.value.name
        value = environment_variable.value.value
        type  = environment_variable.value.type
      }
    }

    environment_variable {
      name  = "APP_BASE_URL"
      value = "https://app.${var.environment}.${var.domain_name}"
      type  = "PLAINTEXT"
    }
  }

  cache {
    type  = "LOCAL"
    modes = ["LOCAL_SOURCE_CACHE"]
  }

  vpc_config {
    vpc_id             = var.vpc_id
    subnets            = var.private_subnets
    security_group_ids = [var.codebuild_sg_id]
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "/aws/codebuild/${local.name_prefix}-integration"
      stream_name = "build"
    }
  }

  tags = { Name = "${local.name_prefix}-integration" }
}

# =============================================================================
# OUTPUTS
# =============================================================================
output "lint_project_name"        { value = aws_codebuild_project.lint.name }
output "unit_test_project_name"   { value = aws_codebuild_project.unit_test.name }
output "security_project_name"    { value = aws_codebuild_project.security.name }
output "build_project_name"       { value = aws_codebuild_project.build.name }
output "integration_project_name" { value = aws_codebuild_project.integration.name }
