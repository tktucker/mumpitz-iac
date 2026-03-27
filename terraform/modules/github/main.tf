# =============================================================================
# GITHUB MODULE — CodeStar Connections (GitHub App integration)
# =============================================================================
#
# Creates an AWS CodeStar Connection to GitHub. After `terraform apply`, the
# connection will be in PENDING status. You must authorize it manually:
#
#   AWS Console → Developer Tools → Connections → select connection → "Update pending connection"
#
# Only after authorization will CodePipeline be able to trigger from GitHub
# pushes and access repository contents.
#
# The IAC repository is referenced by CodePipeline's Source stage but not
# managed as an AWS resource — GitHub repos are external and pre-existing.
# =============================================================================

variable "project_name" { type = string }
variable "environment"  { type = string }
variable "github_owner" { type = string }  # GitHub username or org, e.g. "tktucker"
variable "app_repo_name" { type = string } # e.g. "mumpitz-app"

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# -----------------------------------------------------------------------------
# CodeStar Connection to GitHub
#
# Uses the GitHub App provider type — this is the modern replacement for
# OAuth tokens and provides more granular repository access controls.
# One connection can serve multiple pipelines across the same account.
# -----------------------------------------------------------------------------
resource "aws_codestarconnections_connection" "github" {
  name          = "${local.name_prefix}-github"
  provider_type = "GitHub"

  tags = {
    Name        = "${local.name_prefix}-github"
    Environment = var.environment
    Project     = var.project_name
  }
}

# =============================================================================
# OUTPUTS
# =============================================================================
output "connection_arn"       { value = aws_codestarconnections_connection.github.arn }
output "connection_status"    { value = aws_codestarconnections_connection.github.connection_status }
output "app_repo_full_name"   { value = "${var.github_owner}/${var.app_repo_name}" }
