# =============================================================================
# IAM MODULE — Roles and policies for all CI/CD services
# =============================================================================
# =============================================================================

variable "project_name" { type = string }
variable "environment"  { type = string }
variable "account_id"   { type = string }
variable "region"       { type = string }

locals {
  name_prefix      = "${var.project_name}-${var.environment}"
  artifact_bucket  = "${var.project_name}-${var.environment}-pipeline-artifacts-${var.account_id}"
}

data "aws_iam_policy_document" "codepipeline_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "codebuild_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "codedeploy_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codedeploy.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "ecs_task_exec_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# =============================================================================
# CODEPIPELINE ROLE
# =============================================================================
resource "aws_iam_role" "codepipeline" {
  name               = "${local.name_prefix}-codepipeline-role"
  assume_role_policy = data.aws_iam_policy_document.codepipeline_assume.json
}

resource "aws_iam_role_policy" "codepipeline" {
  name = "${local.name_prefix}-codepipeline-policy"
  role = aws_iam_role.codepipeline.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3ArtifactAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject", "s3:GetObjectVersion",
          "s3:PutObject", "s3:GetBucketVersioning"
        ]
        Resource = [
          "arn:aws:s3:::${local.artifact_bucket}",
          "arn:aws:s3:::${local.artifact_bucket}/*"
        ]
      },
      {
        # UseConnection is required for CodePipeline to read source artifacts
        # from GitHub via the CodeStar Connection (GitHub App integration).
        # GetConnection is required by Terraform during plan/apply to read
        # the connection status and validate the ARN.
        Sid    = "CodeStarConnectionsAccess"
        Effect = "Allow"
        Action = [
          "codestar-connections:UseConnection",
          "codestar-connections:GetConnection"
        ]
        Resource = "arn:aws:codestar-connections:${var.region}:${var.account_id}:connection/*"
      },
      {
        Sid    = "CodeBuildAccess"
        Effect = "Allow"
        Action = [
          "codebuild:BatchGetBuilds",
          "codebuild:StartBuild"
        ]
        Resource = "arn:aws:codebuild:${var.region}:${var.account_id}:project/${local.name_prefix}-*"
      },
      {
        Sid    = "CodeDeployAccess"
        Effect = "Allow"
        Action = [
          "codedeploy:CreateDeployment",
          "codedeploy:GetDeployment",
          "codedeploy:GetApplication",
          "codedeploy:GetApplicationRevision",
          "codedeploy:RegisterApplicationRevision",
          "codedeploy:GetDeploymentConfig",
          "ecs:RegisterTaskDefinition"
        ]
        Resource = "*"
      },
      {
        Sid    = "PassRoleToECS"
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = [
          "arn:aws:iam::${var.account_id}:role/${local.name_prefix}-ecs-task-exec-role",
          "arn:aws:iam::${var.account_id}:role/${local.name_prefix}-ecs-task-role"
        ]
      }
    ]
  })
}

# =============================================================================
# CODEBUILD ROLE
# =============================================================================
resource "aws_iam_role" "codebuild" {
  name               = "${local.name_prefix}-codebuild-role"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume.json
}

resource "aws_iam_role_policy" "codebuild" {
  name = "${local.name_prefix}-codebuild-policy"
  role = aws_iam_role.codebuild.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.region}:${var.account_id}:log-group:/aws/codebuild/${local.name_prefix}-*"
      },
      {
        Sid    = "S3ArtifactReadWrite"
        Effect = "Allow"
        Action = [
          "s3:GetObject", "s3:GetObjectVersion",
          "s3:PutObject", "s3:GetBucketAcl", "s3:GetBucketLocation"
        ]
        Resource = [
          "arn:aws:s3:::${local.artifact_bucket}",
          "arn:aws:s3:::${local.artifact_bucket}/*"
        ]
      },
      {
        Sid    = "ECRAuth"
        Effect = "Allow"
        Action = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid    = "ECRPushPull"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = "arn:aws:ecr:${var.region}:${var.account_id}:repository/${local.name_prefix}-*"
      },
      {
        Sid    = "VPCNetworking"
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeDhcpOptions",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeVpcs",
          "ec2:CreateNetworkInterfacePermission"
        ]
        Resource = "*"
      },
      {
        Sid    = "SSMParameterRead"
        Effect = "Allow"
        Action = ["ssm:GetParameter", "ssm:GetParameters"]
        Resource = "arn:aws:ssm:${var.region}:${var.account_id}:parameter/${local.name_prefix}/*"
      },
      {
        # Required for CodeBuild test reports (coverage-report in buildspec-test.yml).
        # CodeBuild auto-creates a report group named <project>-<report-group-name>
        # during the UPLOAD_ARTIFACTS phase when reports: section is present in buildspec.
        Sid    = "CodeBuildReportGroups"
        Effect = "Allow"
        Action = [
          "codebuild:CreateReportGroup",
          "codebuild:UpdateReportGroup",
          "codebuild:DeleteReportGroup",
          "codebuild:DescribeTestCases",
          "codebuild:CreateReport",
          "codebuild:UpdateReport",
          "codebuild:BatchPutTestCases",
          "codebuild:BatchPutCodeCoverages"
        ]
        Resource = "arn:aws:codebuild:${var.region}:${var.account_id}:report-group/${local.name_prefix}-*"
      }
    ]
  })
}

# =============================================================================
# CODEDEPLOY ROLE
# =============================================================================
resource "aws_iam_role" "codedeploy" {
  name               = "${local.name_prefix}-codedeploy-role"
  assume_role_policy = data.aws_iam_policy_document.codedeploy_assume.json
}

# AWS-managed policy that grants CodeDeploy ECS blue/green permissions
resource "aws_iam_role_policy_attachment" "codedeploy_ecs" {
  role       = aws_iam_role.codedeploy.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS"
}

# =============================================================================
# ECS TASK EXECUTION ROLE
# Grants ECS agent permissions to pull images from ECR and write logs
# =============================================================================
resource "aws_iam_role" "ecs_task_execution" {
  name               = "${local.name_prefix}-ecs-task-exec-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_exec_assume.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# =============================================================================
# ECS TASK ROLE
# Permissions the application itself needs at runtime (e.g. SSM, S3, etc.)
# =============================================================================
resource "aws_iam_role" "ecs_task" {
  name               = "${local.name_prefix}-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_exec_assume.json
}

resource "aws_iam_role_policy" "ecs_task" {
  name = "${local.name_prefix}-ecs-task-policy"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SSMReadOnly"
        Effect = "Allow"
        Action = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
        Resource = "arn:aws:ssm:${var.region}:${var.account_id}:parameter/${local.name_prefix}/*"
      },
      {
        Sid    = "CloudWatchMetrics"
        Effect = "Allow"
        Action = ["cloudwatch:PutMetricData"]
        Resource = "*"
      },
      {
        # Required for the X-Ray daemon sidecar and the aws-xray-sdk in Flask.
        # PutTraceSegments — send trace segments to the X-Ray service.
        # PutTelemetryRecords — send daemon health telemetry.
        # GetSamplingRules/GetSamplingTargets — fetch dynamic sampling rules
        #   so the SDK can respect centrally configured sampling rates.
        Sid    = "XRayTracing"
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords",
          "xray:GetSamplingRules",
          "xray:GetSamplingTargets",
          "xray:GetSamplingStatisticSummaries"
        ]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# OUTPUTS
# =============================================================================
output "codepipeline_role_arn"        { value = aws_iam_role.codepipeline.arn }
output "codebuild_role_arn"           { value = aws_iam_role.codebuild.arn }
output "codedeploy_role_arn"          { value = aws_iam_role.codedeploy.arn }
output "ecs_task_execution_role_arn"  { value = aws_iam_role.ecs_task_execution.arn }
output "ecs_task_role_arn"            { value = aws_iam_role.ecs_task.arn }
