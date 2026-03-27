# =============================================================================
# DEV ENVIRONMENT — iac-repo/live/dev/terragrunt.hcl
# =============================================================================
#
# Deploys the full mumpitz stack into the dev environment.
# Resources are prefixed: mumpitz-dev-*
#
# State key (set automatically by path_relative_to_include):
#   live/dev/terraform.tfstate
#
# Usage:
#   cd iac-repo/live/dev
#   terragrunt plan
#   terragrunt apply
# =============================================================================

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "../../terraform"
}

inputs = {
  # ── Core ─────────────────────────────────────────────────────────────────
  aws_region   = include.root.locals.aws_region
  project_name = include.root.locals.project_name
  environment  = "dev"
  owner_email  = get_env("TF_VAR_owner_email", "tktucker@gmail.com")

  # ── GitHub ────────────────────────────────────────────────────────────────
  # Dev pipeline watches the 'develop' branch of mumpitz-app.
  github_owner  = "tktucker"
  app_repo_name = "mumpitz-app"
  branch_name   = "develop"

  # ── IAM Identity Center (SSO) ─────────────────────────────────────────────
  sso_username = "tktucker@gmail.com"

  # ── Networking ────────────────────────────────────────────────────────────
  vpc_cidr             = "10.0.0.0/16"
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]
  availability_zones   = ["us-east-1a", "us-east-1b"]

  # ── ECS / Application ─────────────────────────────────────────────────────
  app_name           = "flask-api"
  app_port           = 5000
  app_cpu            = 256    # 0.25 vCPU — minimal for dev
  app_memory         = 512    # MiB
  app_desired_count  = 1      # Single task in dev to minimise cost
  use_spot           = true   # FARGATE_SPOT saves ~70% in dev
  log_retention_days = 14     # Short retention in dev
  min_capacity       = 1
  max_capacity       = 2      # Cap at 2 tasks in dev

  # ── CodeBuild ─────────────────────────────────────────────────────────────
  codebuild_compute_type = "BUILD_GENERAL1_SMALL"
  codebuild_image        = "aws/codebuild/standard:7.0"

  # ── CodeDeploy Traffic Shifting ───────────────────────────────────────────
  # AllAtOnce in dev: instant cutover, fast iteration.
  deployment_config     = "CodeDeployDefault.ECSAllAtOnce"
  termination_wait_time = 0     # Terminate blue immediately — no wait in dev
  require_approval      = false # No manual gate in dev
}
