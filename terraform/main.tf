# =============================================================================
# ROOT MODULE — Wires all sub-modules together
# =============================================================================
#
# Two-repository model (GitHub):
#   mumpitz-app  — Application source; push to branch → triggers CodePipeline
#   mumpitz-iac  — This Terraform code; applied manually via Terragrunt
#
# Deployment pipeline:
#   app-repo push → CodeStar Connections webhook → CodePipeline
#     Stage 1: Source       (GitHub, via CodeStar Connection)
#     Stage 2: Validate     (Lint + UnitTest + SecurityScan, parallel CodeBuild)
#     Stage 3: Build        (CodeBuild — buildspecs/buildspec-build.yml)
#     Stage 4: Deploy       (CodeDeploy ECS Blue/Green)
#     Stage 5: Approve      (Manual gate — prod only, require_approval = true)
#     Stage 6: Integration  (CodeBuild — buildspecs/buildspec-integration.yml)
#
# All buildspec paths are relative to the root of mumpitz-app (not mumpitz-iac).
# =============================================================================

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
}

# -----------------------------------------------------------------------------
# IAM — Roles, policies for CI/CD services + customer-managed devops policies
# Apply this first (admin credentials) to create the policies that SSO attaches.
# -----------------------------------------------------------------------------
module "iam" {
  source = "./modules/iam"

  project_name = var.project_name
  environment  = var.environment
  account_id   = local.account_id
  region       = local.region
}

# -----------------------------------------------------------------------------
# SSO — IAM Identity Center permission set + account assignment
# Depends on iam module (policies must exist before SSO attaches them).
# Requires IAM Identity Center to be enabled in the account.
# -----------------------------------------------------------------------------
module "sso" {
  source = "./modules/sso"

  project_name = var.project_name
  environment  = var.environment
  sso_username = var.sso_username
}

# -----------------------------------------------------------------------------
# GitHub — CodeStar Connection (GitHub App integration)
# IMPORTANT: After apply, authorize the connection in the AWS Console:
#   Developer Tools → Connections → select connection → "Update pending connection"
# -----------------------------------------------------------------------------
module "github" {
  source = "./modules/github"

  project_name  = var.project_name
  environment   = var.environment
  github_owner  = var.github_owner
  app_repo_name = var.app_repo_name
}

# -----------------------------------------------------------------------------
# ECR
# -----------------------------------------------------------------------------
module "ecr" {
  source = "./modules/ecr"

  project_name = var.project_name
  environment  = var.environment
  app_name     = var.app_name
}

# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------
module "vpc" {
  source = "./modules/vpc"

  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
}

# -----------------------------------------------------------------------------
# ECS — Cluster, Service, ALB, Auto Scaling
# use_spot = true saves ~70% on compute cost (dev/staging only).
# Auto scaling: min_capacity → max_capacity based on CPU utilization.
# -----------------------------------------------------------------------------
module "ecs" {
  source = "./modules/ecs"

  project_name        = var.project_name
  environment         = var.environment
  app_name            = var.app_name
  app_port            = var.app_port
  app_cpu             = var.app_cpu
  app_memory          = var.app_memory
  desired_count       = var.app_desired_count
  ecr_image_url       = "${module.ecr.repository_url}:latest"
  vpc_id              = module.vpc.vpc_id
  public_subnets      = module.vpc.public_subnet_ids
  private_subnets     = module.vpc.private_subnet_ids
  task_exec_role      = module.iam.ecs_task_execution_role_arn
  task_role           = module.iam.ecs_task_role_arn
  alb_sg_id           = module.vpc.alb_sg_id
  ecs_sg_id           = module.vpc.ecs_tasks_sg_id
  use_spot            = var.use_spot
  log_retention_days  = var.log_retention_days
  min_capacity        = var.min_capacity
  max_capacity        = var.max_capacity
}

# -----------------------------------------------------------------------------
# CodeBuild — Five projects (lint, unit-test, security, build, integration)
# All buildspec paths are relative to the root of the mumpitz-app repo.
# -----------------------------------------------------------------------------
module "codebuild" {
  source = "./modules/codebuild"

  project_name       = var.project_name
  environment        = var.environment
  app_name           = var.app_name
  app_port           = var.app_port
  compute_type       = var.codebuild_compute_type
  build_image        = var.codebuild_image
  codebuild_role_arn  = module.iam.codebuild_role_arn
  ecr_repo_url        = module.ecr.repository_url
  account_id          = local.account_id
  region              = local.region
  vpc_id              = module.vpc.vpc_id
  private_subnets     = module.vpc.private_subnet_ids
  codebuild_sg_id     = module.vpc.codebuild_sg_id
  alb_dns_name        = module.ecs.alb_dns_name
  domain_name         = var.domain_name
  task_exec_role_arn  = module.iam.ecs_task_execution_role_arn
  task_role_arn       = module.iam.ecs_task_role_arn
}

# -----------------------------------------------------------------------------
# DNS — ACM certificate + Route53 ALIAS + HTTPS ALB listener
# Depends on ECS (ALB outputs) and must complete before CodeDeploy so that
# the HTTPS listener ARN is available for the deployment group.
# -----------------------------------------------------------------------------
module "dns" {
  source = "./modules/dns"

  project_name = var.project_name
  environment  = var.environment
  domain_name  = var.domain_name
  alb_arn      = module.ecs.alb_arn
  alb_dns_name = module.ecs.alb_dns_name
  alb_zone_id  = module.ecs.alb_zone_id
  tg_blue_arn  = module.ecs.tg_blue_arn
}

# -----------------------------------------------------------------------------
# CodeDeploy
# -----------------------------------------------------------------------------
module "codedeploy" {
  source = "./modules/codedeploy"

  project_name            = var.project_name
  environment             = var.environment
  app_name                = var.app_name
  ecs_cluster_name        = module.ecs.cluster_name
  ecs_service_name        = module.ecs.service_name
  alb_https_listener_arn  = module.dns.alb_https_listener_arn
  tg_blue_name            = module.ecs.tg_blue_name
  tg_green_name           = module.ecs.tg_green_name
  codedeploy_role_arn     = module.iam.codedeploy_role_arn
  deployment_config       = var.deployment_config
  termination_wait_time   = var.termination_wait_time
}

# -----------------------------------------------------------------------------
# SNS — pipeline success/failure email notifications
# -----------------------------------------------------------------------------
module "sns" {
  source = "./modules/sns"

  project_name       = var.project_name
  environment        = var.environment
  region             = local.region
  account_id         = local.account_id
  notification_email = var.email
  pipeline_name      = module.codepipeline.pipeline_name
}

# -----------------------------------------------------------------------------
# CodePipeline — GitHub source, 6-stage pipeline
# -----------------------------------------------------------------------------
module "codepipeline" {
  source = "./modules/codepipeline"

  project_name             = var.project_name
  environment              = var.environment
  app_name                 = var.app_name
  region                   = local.region
  account_id               = local.account_id
  pipeline_role_arn        = module.iam.codepipeline_role_arn
  app_repo_name            = var.app_repo_name
  branch_name              = var.branch_name
  codestar_connection_arn  = module.github.connection_arn
  github_owner             = var.github_owner
  require_approval         = var.require_approval

  cb_lint_name             = module.codebuild.lint_project_name
  cb_unit_test_name        = module.codebuild.unit_test_project_name
  cb_security_name         = module.codebuild.security_project_name
  cb_build_name            = module.codebuild.build_project_name
  cb_integration_name      = module.codebuild.integration_project_name

  codedeploy_app_name      = module.codedeploy.app_name
  codedeploy_group_name    = module.codedeploy.deployment_group_name

  ecr_repo_url             = module.ecr.repository_url
}
