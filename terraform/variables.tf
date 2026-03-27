# =============================================================================
# INPUT VARIABLES
# =============================================================================

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short project identifier used as a prefix for all resource names"
  type        = string
  default     = "mumpitz"
}

variable "environment" {
  description = "Deployment environment (dev / staging / prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "owner_email" {
  description = "Email address of the project owner (used in resource tags)"
  type        = string
  default     = "tktucker@gmail.com"
}

# -----------------------------------------------------------------------------
# GitHub — Source Control
# -----------------------------------------------------------------------------
variable "github_owner" {
  description = "GitHub username or organization that owns the repositories"
  type        = string
  default     = "tktucker"
}

variable "app_repo_name" {
  description = "GitHub repository name for application source code (triggers CodePipeline)"
  type        = string
  default     = "mumpitz-app"
}

variable "branch_name" {
  description = "Branch name in the app repo that triggers the pipeline"
  type        = string
  default     = "main"
}

# -----------------------------------------------------------------------------
# IAM Identity Center (SSO)
# -----------------------------------------------------------------------------
variable "sso_username" {
  description = "IAM Identity Center username (email) of the devops operator"
  type        = string
  default     = "tktucker@gmail.com"
}

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "availability_zones" {
  description = "List of AZs to deploy into (must match subnet list lengths)"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

# -----------------------------------------------------------------------------
# ECS / Application
# -----------------------------------------------------------------------------
variable "app_name" {
  description = "Name of the application container"
  type        = string
  default     = "flask-api"
}

variable "app_port" {
  description = "Port the Flask application listens on inside the container"
  type        = number
  default     = 5000
}

variable "app_cpu" {
  description = "Fargate task CPU units (256 = 0.25 vCPU)"
  type        = number
  default     = 256
}

variable "app_memory" {
  description = "Fargate task memory in MiB"
  type        = number
  default     = 512
}

variable "app_desired_count" {
  description = "Initial number of ECS tasks to run (auto scaling will adjust from here)"
  type        = number
  default     = 2
}

variable "use_spot" {
  description = "Use FARGATE_SPOT capacity provider for ~70% cost savings (recommended for dev/staging)"
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "CloudWatch log group retention in days (14 dev, 30 staging, 90 prod)"
  type        = number
  default     = 30
}

variable "min_capacity" {
  description = "Minimum number of ECS tasks (auto scaling lower bound)"
  type        = number
  default     = 1
}

variable "max_capacity" {
  description = "Maximum number of ECS tasks (auto scaling upper bound)"
  type        = number
  default     = 4
}

# -----------------------------------------------------------------------------
# CodeBuild
# -----------------------------------------------------------------------------
variable "codebuild_compute_type" {
  description = "CodeBuild compute type for build projects"
  type        = string
  default     = "BUILD_GENERAL1_SMALL"
}

variable "codebuild_image" {
  description = "Docker image for the CodeBuild environment"
  type        = string
  default     = "aws/codebuild/standard:7.0"
}

# -----------------------------------------------------------------------------
# CodeDeploy
# -----------------------------------------------------------------------------
variable "deployment_config" {
  description = "CodeDeploy deployment configuration for ECS blue/green traffic shifting"
  type        = string
  default     = "CodeDeployDefault.ECSAllAtOnce"
  # Options:
  #   CodeDeployDefault.ECSAllAtOnce
  #   CodeDeployDefault.ECSLinear10PercentEvery1Minutes
  #   CodeDeployDefault.ECSLinear10PercentEvery3Minutes
  #   CodeDeployDefault.ECSCanary10Percent5Minutes
  #   CodeDeployDefault.ECSCanary10Percent15Minutes
}

variable "termination_wait_time" {
  description = "Minutes to wait before terminating the original (blue) task set after traffic shift"
  type        = number
  default     = 5
}

variable "require_approval" {
  description = "Require manual approval in CodePipeline before the Integration stage (recommended for prod)"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# DNS / ACM
# -----------------------------------------------------------------------------
variable "domain_name" {
  description = "Root Route53 hosted zone domain (the zone must already exist)"
  type        = string
  default     = "mumpitz.click"
}

# -----------------------------------------------------------------------------
# SNS
# -----------------------------------------------------------------------------
variable "email" {
  description = "Email address for pipeline success/failure notifications"
  type        = string
  default     = "tktucker@gmail.com"
}
