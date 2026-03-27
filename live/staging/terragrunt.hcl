# =============================================================================
# STAGING ENVIRONMENT — iac-repo/live/staging/terragrunt.hcl
# =============================================================================
#
# Deploys the full mumpitz stack into the staging environment.
# Resources are prefixed: mumpitz-staging-*
#
# Staging mirrors production sizing and deployment strategy as closely as
# possible — it's the final validation gate before prod.
#
# State key (set automatically by path_relative_to_include):
#   live/staging/terraform.tfstate
#
# Usage:
#   cd iac-repo/live/staging
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
  environment  = "staging"
  owner_email  = get_env("TF_VAR_owner_email", "tktucker@gmail.com")

  # ── GitHub ────────────────────────────────────────────────────────────────
  # Staging pipeline watches the 'staging' branch of mumpitz-app.
  github_owner  = "tktucker"
  app_repo_name = "mumpitz-app"
  branch_name   = "staging"

  # ── IAM Identity Center (SSO) ─────────────────────────────────────────────
  sso_username = "tktucker@gmail.com"

  # ── Networking ────────────────────────────────────────────────────────────
  # Separate CIDR block — avoids overlap with dev (10.0.x) and prod (10.2.x).
  vpc_cidr             = "10.1.0.0/16"
  public_subnet_cidrs  = ["10.1.1.0/24", "10.1.2.0/24"]
  private_subnet_cidrs = ["10.1.11.0/24", "10.1.12.0/24"]
  availability_zones   = ["us-east-1a", "us-east-1b"]

  # ── ECS / Application ─────────────────────────────────────────────────────
  app_name           = "flask-api"
  app_port           = 5000
  app_cpu            = 512    # 0.5 vCPU — mirrors prod for realistic perf testing
  app_memory         = 1024   # MiB
  app_desired_count  = 2      # HA across two AZs — same as prod
  use_spot           = true   # FARGATE_SPOT acceptable in staging (non-critical)
  log_retention_days = 30
  min_capacity       = 1
  max_capacity       = 4

  # ── CodeBuild ─────────────────────────────────────────────────────────────
  codebuild_compute_type = "BUILD_GENERAL1_SMALL"
  codebuild_image        = "aws/codebuild/standard:7.0"

  # ── CodeDeploy Traffic Shifting ───────────────────────────────────────────
  # Canary in staging: shift 10% first, verify for 5 min, then 100%.
  # Catches regressions before they hit full traffic — mirrors prod strategy.
  deployment_config     = "CodeDeployDefault.ECSCanary10Percent5Minutes"
  termination_wait_time = 5     # 5 minutes before blue task set is terminated
  require_approval      = false # Staging validates automatically; prod needs approval
}
