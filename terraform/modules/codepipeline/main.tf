# =============================================================================
# CODEPIPELINE MODULE — Full CI/CD orchestration
# =============================================================================
#
# Source: GitHub (via CodeStar Connections GitHub App)
#
# AppSpec path: "appspec.yaml" — at the root of the app-repo.
# Buildspec paths are relative to the app-repo root (set in CodeBuild projects).
#
# Pipeline stages:
#   1. Source       — GitHub (DetectChanges webhook, no polling)
#   2. Validate     — Lint + UnitTest + SecurityScan (parallel)
#   3. Build        — docker build + ECR push; produces taskdef.json
#   4. Deploy       — CodeDeploy ECS blue/green
#   5. Approve      — Manual approval gate (prod only, controlled by require_approval)
#   6. Integration  — pytest vs live ALB
#
# IMPORTANT: After terraform apply, the CodeStar Connection will be in PENDING
# status. You must authorize it manually before the pipeline can trigger:
#   AWS Console → Developer Tools → Connections → select → "Update pending connection"
# =============================================================================

variable "project_name"           { type = string }
variable "environment"            { type = string }
variable "app_name"               { type = string }
variable "region"                 { type = string }
variable "account_id"             { type = string }
variable "pipeline_role_arn"      { type = string }
variable "app_repo_name"          { type = string }  # GitHub repo name, e.g. "mumpitz-app"
variable "branch_name"            { type = string }  # e.g. "main", "develop", "staging"
variable "codestar_connection_arn" { type = string } # ARN of the GitHub CodeStar Connection
variable "github_owner"           { type = string }  # GitHub username or org, e.g. "tktucker"
variable "require_approval"       { type = bool; default = false }
variable "cb_lint_name"           { type = string }
variable "cb_unit_test_name"      { type = string }
variable "cb_security_name"       { type = string }
variable "cb_build_name"          { type = string }
variable "cb_integration_name"    { type = string }
variable "codedeploy_app_name"    { type = string }
variable "codedeploy_group_name"  { type = string }
variable "ecr_repo_url"           { type = string }

locals { name_prefix = "${var.project_name}-${var.environment}" }

# -----------------------------------------------------------------------------
# S3 Artifact Bucket — stores inter-stage artifacts
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "artifacts" {
  bucket        = "${local.name_prefix}-pipeline-artifacts-${var.account_id}"
  force_destroy = true  # Allow terraform destroy to remove non-empty bucket

  tags = { Name = "${local.name_prefix}-pipeline-artifacts" }
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# -----------------------------------------------------------------------------
# CodePipeline
# -----------------------------------------------------------------------------
resource "aws_codepipeline" "main" {
  name     = "${local.name_prefix}-pipeline"
  role_arn = var.pipeline_role_arn

  artifact_store {
    location = aws_s3_bucket.artifacts.bucket
    type     = "S3"
  }

  # Stage 1 — Source: pull from GitHub on every push to the tracked branch.
  # DetectChanges = "true" uses the GitHub App webhook — no polling, no
  # EventBridge rule required. The CodeStar Connection must be in ACTIVE
  # status (authorized in the AWS Console) before triggers will fire.
  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["SourceArtifact"]

      configuration = {
        ConnectionArn        = var.codestar_connection_arn
        FullRepositoryId     = "${var.github_owner}/${var.app_repo_name}"
        BranchName           = var.branch_name
        OutputArtifactFormat = "CODE_ZIP"
        DetectChanges        = "true"
      }
    }
  }

  # Stage 2 — Validate: Lint + UnitTest + SecurityScan run in PARALLEL
  # Actions sharing the same run_order within a stage execute concurrently.
  # Total time = slowest individual action rather than the sum of all three.
  stage {
    name = "Validate"

    action {
      name            = "Lint"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      run_order       = 1
      input_artifacts = ["SourceArtifact"]

      configuration = {
        ProjectName = var.cb_lint_name
      }
    }

    action {
      name            = "UnitTest"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      run_order       = 1
      input_artifacts = ["SourceArtifact"]

      configuration = {
        ProjectName = var.cb_unit_test_name
      }
    }

    action {
      name            = "SecurityScan"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      run_order       = 1
      input_artifacts = ["SourceArtifact"]

      configuration = {
        ProjectName = var.cb_security_name
      }
    }
  }

  # Stage 3 — Build: produces taskdef.json + imageDetail.json
  stage {
    name = "Build"
    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["SourceArtifact"]
      output_artifacts = ["BuildArtifact"]

      configuration = {
        ProjectName = var.cb_build_name
      }
    }
  }

  # Stage 4 — Deploy: CodeDeploy ECS blue/green
  # INPUT_ARTIFACTS must contain taskdef.json (from Build stage)
  # AppSpecTemplatePath is relative to the artifact root (app-repo root)
  stage {
    name = "Deploy"
    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CodeDeployToECS"
      version         = "1"
      input_artifacts = ["BuildArtifact", "SourceArtifact"]

      configuration = {
        ApplicationName                = var.codedeploy_app_name
        DeploymentGroupName            = var.codedeploy_group_name
        TaskDefinitionTemplateArtifact = "BuildArtifact"
        TaskDefinitionTemplatePath     = "taskdef.json"
        AppSpecTemplateArtifact        = "SourceArtifact"
        AppSpecTemplatePath            = "appspec.yaml"
        Image1ArtifactName             = "BuildArtifact"
        Image1ContainerName            = "IMAGE1_NAME"
      }
    }
  }

  # Stage 5 — Manual Approval (optional, prod only)
  # When require_approval = true, a human must approve in the AWS Console
  # or via CLI before the Integration stage runs. This gives operators a
  # window to verify the blue/green deployment looks healthy before
  # running the automated integration test suite.
  dynamic "stage" {
    for_each = var.require_approval ? [1] : []
    content {
      name = "Approve"
      action {
        name     = "ManualApproval"
        category = "Approval"
        owner    = "AWS"
        provider = "Manual"
        version  = "1"

        configuration = {
          CustomData = "Approve post-deploy integration tests for ${var.environment}"
        }
      }
    }
  }

  # Stage 6 — Integration Test: runs after blue/green deployment completes
  stage {
    name = "Integration"
    action {
      name            = "Integration"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["SourceArtifact"]

      configuration = {
        ProjectName = var.cb_integration_name
      }
    }
  }
}

# =============================================================================
# OUTPUTS
# =============================================================================
output "pipeline_name"        { value = aws_codepipeline.main.name }
output "artifact_bucket_name" { value = aws_s3_bucket.artifacts.bucket }
