# =============================================================================
# CODECOMMIT MODULE — Two repositories
# =============================================================================
#
# app-repo: application source code — push to main triggers CodePipeline
# iac-repo: Terraform IaC — managed independently, NOT a pipeline source
#
# CodeCommit is a fully managed, private Git service.
# Access is controlled via IAM policies (HTTPS Git credentials or SSH keys).
# EventBridge watches for repository state changes to trigger CodePipeline.
# =============================================================================

variable "project_name"  { type = string }
variable "environment"   { type = string }
variable "app_repo_name" { type = string }
variable "iac_repo_name" { type = string }

# Note: CodeCommit repos are SHARED across environments — one source of truth.
# Different environments watch different branches of the same repo:
#   dev:     watches 'develop'
#   staging: watches 'staging'
#   prod:    watches 'main'

# Application repository — source for the CI/CD pipeline
resource "aws_codecommit_repository" "app" {
  repository_name = var.app_repo_name
  description     = "Application source code for ${var.project_name} — push to main triggers CodePipeline"

  tags = { Name = var.app_repo_name }
}

# IaC repository — managed separately, not wired into the pipeline
resource "aws_codecommit_repository" "iac" {
  repository_name = var.iac_repo_name
  description     = "Terraform IaC for ${var.project_name} — apply manually via Terragrunt"

  tags = { Name = var.iac_repo_name }
}

# =============================================================================
# OUTPUTS
# =============================================================================
output "app_repository_name" { value = aws_codecommit_repository.app.repository_name }
output "app_clone_url_http"  { value = aws_codecommit_repository.app.clone_url_http }
output "app_clone_url_ssh"   { value = aws_codecommit_repository.app.clone_url_ssh }
output "iac_clone_url_http"  { value = aws_codecommit_repository.iac.clone_url_http }
output "iac_clone_url_ssh"   { value = aws_codecommit_repository.iac.clone_url_ssh }
