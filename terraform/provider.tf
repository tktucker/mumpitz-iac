# =============================================================================
# AWS PROVIDER
# =============================================================================
# No terraform {} block here — Terragrunt generates versions_generated.tf
# with required_version and required_providers at plan/apply time.
# =============================================================================

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terragrunt"
      Owner       = var.owner_email
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
