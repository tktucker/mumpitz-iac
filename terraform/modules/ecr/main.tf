# =============================================================================
# ECR MODULE — Elastic Container Registry
# =============================================================================

variable "project_name" { type = string }
variable "environment"  { type = string }
variable "app_name"     { type = string }

# ECR repos are environment-scoped so dev and prod images are kept isolated.
# Images are tagged with the git commit SHA and promoted across environments.
resource "aws_ecr_repository" "app" {
  name                 = "${var.project_name}-${var.environment}-${var.app_name}"
  image_tag_mutability = "MUTABLE"  # Set to IMMUTABLE in production for reproducibility

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
  lifecycle {
    prevent_destroy = true
    ignore_changes  = [name]
  }
}

# Lifecycle policy — keep last 20 tagged images, purge untagged after 1 day
#
# tagPatternList = ["*"] matches ALL tagged images regardless of prefix,
# including commit SHA tags (8-char hex, e.g. "a1b2c3d4") produced by
# buildspec-build.yml. The previous tagPrefixList = ["v"] only matched
# tags starting with "v" and would not have retained SHA-tagged images.
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Remove untagged images older than 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the last 20 tagged images (SHA tags + latest)"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["*"]
          countType      = "imageCountMoreThan"
          countNumber    = 20
        }
        action = { type = "expire" }
      }
    ]
  })
}

output "repository_url"  { value = aws_ecr_repository.app.repository_url }
output "repository_name" { value = aws_ecr_repository.app.name }
output "repository_arn"  { value = aws_ecr_repository.app.arn }
