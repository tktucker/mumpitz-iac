# =============================================================================
# PRODUCTION ENVIRONMENT — iac-repo/live/prod/terragrunt.hcl
# =============================================================================
#
# Deploys the full mumpitz stack into the production environment.
# Resources are prefixed: mumpitz-prod-*
#
# IMPORTANT: Changes to this file should go through a PR review.
# Run `terragrunt plan` and have a peer review the plan output before applying.
#
# State key (set automatically by path_relative_to_include):
#   live/prod/terraform.tfstate
#
# Usage:
#   cd iac-repo/live/prod
#   terragrunt plan            # review carefully before applying
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
  environment  = "prod"
  owner_email  = get_env("TF_VAR_owner_email", "tktucker@gmail.com")

  # ── GitHub ────────────────────────────────────────────────────────────────
  # Prod pipeline watches the protected 'main' branch of mumpitz-app.
  github_owner  = "tktucker"
  app_repo_name = "mumpitz-app"
  branch_name   = "main"

  # ── IAM Identity Center (SSO) ─────────────────────────────────────────────
  sso_username = "tktucker@gmail.com"

  # ── Networking ────────────────────────────────────────────────────────────
  # Separate CIDR block — no overlap with dev (10.0.x) or staging (10.1.x).
  vpc_cidr             = "10.2.0.0/16"
  public_subnet_cidrs  = ["10.2.1.0/24", "10.2.2.0/24"]
  private_subnet_cidrs = ["10.2.11.0/24", "10.2.12.0/24"]
  availability_zones   = ["us-east-1a", "us-east-1b"]

  # ── ECS / Application ─────────────────────────────────────────────────────
  app_name           = "flask-api"
  app_port           = 5000
  app_cpu            = 1024   # 1 vCPU — handles real production load
  app_memory         = 2048   # MiB
  app_desired_count  = 2      # Two tasks across two AZs; auto scaling handles peaks
  use_spot           = false  # Standard FARGATE in prod — no interruption risk
  log_retention_days = 90     # Longer retention for compliance and debugging
  min_capacity       = 2      # Always keep at least 2 tasks for HA
  max_capacity       = 8      # Scale up to 8 tasks under heavy load

  # ── CodeBuild ─────────────────────────────────────────────────────────────
  # Medium compute for faster prod builds — build time directly affects MTTR
  codebuild_compute_type = "BUILD_GENERAL1_MEDIUM"
  codebuild_image        = "aws/codebuild/standard:7.0"

  # ── CodeDeploy Traffic Shifting ───────────────────────────────────────────
  # Linear in prod: shift 10% more traffic every minute.
  # Gives time to catch issues at each step; auto-rollback on failure.
  deployment_config     = "CodeDeployDefault.ECSLinear10PercentEvery1Minutes"
  termination_wait_time = 15    # 15 minutes before blue tasks are terminated
  require_approval      = true  # Manual gate before integration tests in prod
}
