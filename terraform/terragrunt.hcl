# =============================================================================
# STACK-LEVEL TERRAGRUNT CONFIGURATION
# Path: iac-repo/terraform/terragrunt.hcl
# =============================================================================
#
# This file wires together:
#   1. The root config (remote_state + version generation)
#   2. All Terraform variable values for this stack
#
# To add a new environment (e.g. prod), create live/prod/terragrunt.hcl
# with the same include block and override only the values that differ:
#
#   live/
#   ├── dev/
#   │   └── terragrunt.hcl   ← copy of this file, environment = "dev"
#   └── prod/
#       └── terragrunt.hcl   ← environment = "prod", desired_count = 4, etc.
#
# Each environment automatically gets its own isolated state key:
#   live/dev/terraform.tfstate
#   live/prod/terraform.tfstate
# =============================================================================

# ---------------------------------------------------------------------------
# include "root" — inherit remote_state, generate blocks from iac-repo/root.hcl
# ---------------------------------------------------------------------------
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

# ---------------------------------------------------------------------------
# inputs — injected as Terraform variable values
# ---------------------------------------------------------------------------
inputs = {
  # ── Core ─────────────────────────────────────────────────────────────────
  aws_region   = include.root.locals.aws_region
  project_name = include.root.locals.project_name
  environment  = "dev"
  owner_email  = get_env("TF_VAR_owner_email", "tktucker@gmail.com")

  # ── GitHub ────────────────────────────────────────────────────────────────
  github_owner  = "tktucker"
  app_repo_name = "mumpitz-app"
  branch_name   = "main"

  # ── IAM Identity Center (SSO) ─────────────────────────────────────────────
  sso_username = "tktucker@gmail.com"

  # ── Networking ────────────────────────────────────────────────────────────
  vpc_cidr             = "10.0.0.0/16"
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]
  availability_zones   = ["us-east-1a", "us-east-1b"]

  # ── ECS / Application ─────────────────────────────────────────────────────
  app_name          = "flask-api"
  app_port          = 5000
  app_cpu           = 256    # 0.25 vCPU — suitable for dev; increase for prod
  app_memory        = 512    # MiB
  app_desired_count = 2
  use_spot          = false
  log_retention_days = 30
  min_capacity      = 1
  max_capacity      = 4

  # ── CodeBuild ─────────────────────────────────────────────────────────────
  codebuild_compute_type = "BUILD_GENERAL1_SMALL"
  codebuild_image        = "aws/codebuild/standard:7.0"

  # ── CodeDeploy Traffic Shifting ───────────────────────────────────────────
  deployment_config     = "CodeDeployDefault.ECSAllAtOnce"
  termination_wait_time = 5
  require_approval      = false
}
