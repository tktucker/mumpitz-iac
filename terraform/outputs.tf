# =============================================================================
# ROOT MODULE OUTPUTS
# =============================================================================

# -----------------------------------------------------------------------------
# GitHub / CodeStar Connection
# -----------------------------------------------------------------------------
output "github_connection_arn" {
  description = "ARN of the CodeStar Connection to GitHub (must be authorized in AWS Console before pipeline can trigger)"
  value       = module.github.connection_arn
}

output "github_connection_status" {
  description = "Status of the CodeStar Connection (PENDING until authorized in console)"
  value       = module.github.connection_status
}

# -----------------------------------------------------------------------------
# ECR
# -----------------------------------------------------------------------------
output "ecr_repository_url" {
  description = "ECR repository URL (use as the Docker image base path)"
  value       = module.ecr.repository_url
}

# -----------------------------------------------------------------------------
# Application / ALB
# -----------------------------------------------------------------------------
output "alb_dns_name" {
  description = "Public DNS name of the Application Load Balancer"
  value       = module.ecs.alb_dns_name
}

output "app_url" {
  description = "Full HTTPS URL of the deployed Flask application"
  value       = module.dns.app_url
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = module.ecs.cluster_name
}

output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = module.ecs.service_name
}

# -----------------------------------------------------------------------------
# Pipeline
# -----------------------------------------------------------------------------
output "codepipeline_name" {
  description = "Name of the CodePipeline"
  value       = module.codepipeline.pipeline_name
}

output "codepipeline_url" {
  description = "Direct link to the pipeline in the AWS Console"
  value       = "https://${var.aws_region}.console.aws.amazon.com/codesuite/codepipeline/pipelines/${module.codepipeline.pipeline_name}/view"
}

output "artifact_bucket_name" {
  description = "S3 bucket used by CodePipeline for pipeline artifacts"
  value       = module.codepipeline.artifact_bucket_name
}

# -----------------------------------------------------------------------------
# CodeDeploy
# -----------------------------------------------------------------------------
output "codedeploy_app_name" {
  description = "CodeDeploy application name"
  value       = module.codedeploy.app_name
}

output "codedeploy_deployment_group" {
  description = "CodeDeploy deployment group name"
  value       = module.codedeploy.deployment_group_name
}

# -----------------------------------------------------------------------------
# SSO / IAM Identity Center
# -----------------------------------------------------------------------------
output "sso_permission_set_arn" {
  description = "ARN of the IAM Identity Center permission set for devops operators"
  value       = module.sso.permission_set_arn
}
