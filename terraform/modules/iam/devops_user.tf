# =============================================================================
# DEVOPS POLICIES — Customer-managed policies for infrastructure operators
# =============================================================================
#
# These three policies are designed to be attached via AWS IAM Identity Center
# (SSO) permission sets rather than directly to an IAM user. They grant the
# minimum permissions required to run:
#   terragrunt plan / terragrunt apply
#   manual CodePipeline / CodeBuild / CodeDeploy interactions
#   CodeStar Connections management (GitHub integration)
#
# THREE customer-managed policies stay under the AWS 6,144-character limit:
#   1. devops-networking  — VPC, EC2, ALB
#   2. devops-compute     — ECS, ECR, CodeBuild/Deploy/Pipeline, CodeStar
#   3. devops-platform    — S3, IAM (scoped), CloudWatch Logs, STS, ACM, Route53
#
# The path /mumpitz/ groups all project policies and matches what the SSO
# module's customer_managed_policy_reference expects.
# =============================================================================

# =============================================================================
# POLICY 1 — Networking
# Covers: VPC, subnets, route tables, IGW, NAT, EIPs, security groups,
#         network interfaces, ELBv2 (ALB, listeners, target groups)
# =============================================================================
resource "aws_iam_policy" "devops_networking" {
  name        = "${var.project_name}-devops-networking"
  path        = "/${var.project_name}/"
  description = "VPC and ALB management for ${var.project_name} devops operators"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "VPCManagement"
        Effect = "Allow"
        Action = [
          "ec2:CreateVpc", "ec2:DeleteVpc", "ec2:DescribeVpcs",
          "ec2:ModifyVpcAttribute", "ec2:DescribeVpcAttribute",
          "ec2:CreateSubnet", "ec2:DeleteSubnet", "ec2:DescribeSubnets",
          "ec2:ModifySubnetAttribute",
          "ec2:CreateInternetGateway", "ec2:DeleteInternetGateway",
          "ec2:AttachInternetGateway", "ec2:DetachInternetGateway",
          "ec2:DescribeInternetGateways",
          "ec2:CreateRouteTable", "ec2:DeleteRouteTable",
          "ec2:AssociateRouteTable", "ec2:DisassociateRouteTable",
          "ec2:CreateRoute", "ec2:DeleteRoute", "ec2:DescribeRouteTables",
          "ec2:CreateNatGateway", "ec2:DeleteNatGateway",
          "ec2:DescribeNatGateways",
          "ec2:AllocateAddress", "ec2:ReleaseAddress",
          "ec2:AssociateAddress", "ec2:DisassociateAddress",
          "ec2:DescribeAddresses", "ec2:DescribeAddressesAttribute",
          "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup",
          "ec2:DescribeSecurityGroups",
          "ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress",
          "ec2:AuthorizeSecurityGroupEgress", "ec2:RevokeSecurityGroupEgress",
          "ec2:CreateNetworkInterface", "ec2:DeleteNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:CreateTags", "ec2:DeleteTags", "ec2:DescribeTags",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeAccountAttributes"
        ]
        Resource = "*"
      },
      {
        Sid    = "ALBManagement"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:CreateLoadBalancer",
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:CreateTargetGroup",
          "elasticloadbalancing:DeleteTargetGroup",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetGroupAttributes",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:RemoveTags",
          "elasticloadbalancing:DescribeTags",
          "elasticloadbalancing:SetSecurityGroups",
          "elasticloadbalancing:SetSubnets"
        ]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# POLICY 2 — Compute & CI/CD
# Covers: ECS (cluster, service, task def), ECR (repo, lifecycle),
#         CodeStar Connections, CodeBuild, CodeDeploy, CodePipeline,
#         Application Auto Scaling (ECS service scaling)
# =============================================================================
resource "aws_iam_policy" "devops_compute" {
  name        = "${var.project_name}-devops-compute"
  path        = "/${var.project_name}/"
  description = "ECS, ECR, and CI/CD pipeline management for ${var.project_name} devops operators"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECSManagement"
        Effect = "Allow"
        Action = [
          "ecs:CreateCluster", "ecs:DeleteCluster",
          "ecs:DescribeClusters", "ecs:UpdateClusterSettings",
          "ecs:PutClusterCapacityProviders",
          "ecs:CreateService", "ecs:DeleteService",
          "ecs:UpdateService", "ecs:DescribeServices",
          "ecs:RegisterTaskDefinition", "ecs:DeregisterTaskDefinition",
          "ecs:DescribeTaskDefinition", "ecs:ListTaskDefinitions",
          "ecs:TagResource", "ecs:UntagResource", "ecs:ListTagsForResource"
        ]
        Resource = "*"
      },
      {
        Sid    = "AppAutoScaling"
        Effect = "Allow"
        Action = [
          "application-autoscaling:RegisterScalableTarget",
          "application-autoscaling:DeregisterScalableTarget",
          "application-autoscaling:DescribeScalableTargets",
          "application-autoscaling:PutScalingPolicy",
          "application-autoscaling:DeleteScalingPolicy",
          "application-autoscaling:DescribeScalingPolicies",
          "application-autoscaling:DescribeScalingActivities",
          "cloudwatch:PutMetricAlarm", "cloudwatch:DeleteAlarms",
          "cloudwatch:DescribeAlarms"
        ]
        Resource = "*"
      },
      {
        Sid    = "ECRManagement"
        Effect = "Allow"
        Action = [
          "ecr:CreateRepository", "ecr:DeleteRepository",
          "ecr:DescribeRepositories",
          "ecr:SetRepositoryPolicy", "ecr:GetRepositoryPolicy",
          "ecr:DeleteRepositoryPolicy",
          "ecr:PutLifecyclePolicy", "ecr:GetLifecyclePolicy",
          "ecr:DeleteLifecyclePolicy",
          "ecr:PutImageScanningConfiguration",
          "ecr:PutEncryptionConfiguration",
          "ecr:GetAuthorizationToken",
          "ecr:TagResource", "ecr:UntagResource", "ecr:ListTagsForResource"
        ]
        Resource = "*"
      },
      {
        # Replaces CodeCommitManagement. UseConnection allows triggering pipelines
        # and reading source. GetConnection / ListConnections allow Terraform to
        # refresh CodeStar connection state during plan/apply.
        Sid    = "CodeStarConnectionsManagement"
        Effect = "Allow"
        Action = [
          "codestar-connections:CreateConnection",
          "codestar-connections:DeleteConnection",
          "codestar-connections:GetConnection",
          "codestar-connections:ListConnections",
          "codestar-connections:UseConnection",
          "codestar-connections:TagResource",
          "codestar-connections:UntagResource",
          "codestar-connections:ListTagsForResource"
        ]
        Resource = "arn:aws:codestar-connections:${var.region}:${var.account_id}:connection/*"
      },
      {
        Sid    = "CodeBuildManagement"
        Effect = "Allow"
        Action = [
          "codebuild:CreateProject", "codebuild:DeleteProject",
          "codebuild:UpdateProject", "codebuild:BatchGetProjects",
          "codebuild:ListProjects",
          "codebuild:CreateWebhook", "codebuild:DeleteWebhook",
          "codebuild:UpdateWebhook",
          "codebuild:BatchGetBuilds", "codebuild:ListBuildsForProject"
        ]
        Resource = "arn:aws:codebuild:${var.region}:${var.account_id}:project/${var.project_name}-*"
      },
      {
        Sid    = "CodeDeployManagement"
        Effect = "Allow"
        Action = [
          "codedeploy:CreateApplication", "codedeploy:DeleteApplication",
          "codedeploy:GetApplication", "codedeploy:ListApplications",
          "codedeploy:CreateDeploymentGroup", "codedeploy:DeleteDeploymentGroup",
          "codedeploy:UpdateDeploymentGroup", "codedeploy:GetDeploymentGroup",
          "codedeploy:ListDeploymentGroups",
          "codedeploy:GetDeploymentConfig", "codedeploy:ListDeploymentConfigs",
          "codedeploy:TagResource", "codedeploy:UntagResource",
          "codedeploy:ListTagsForResource"
        ]
        Resource = "*"
      },
      {
        Sid    = "CodePipelineManagement"
        Effect = "Allow"
        Action = [
          "codepipeline:CreatePipeline", "codepipeline:DeletePipeline",
          "codepipeline:GetPipeline", "codepipeline:UpdatePipeline",
          "codepipeline:ListPipelines",
          "codepipeline:GetPipelineState", "codepipeline:GetPipelineExecution",
          "codepipeline:StartPipelineExecution", "codepipeline:StopPipelineExecution",
          "codepipeline:PutApprovalResult",
          "codepipeline:TagResource", "codepipeline:UntagResource",
          "codepipeline:ListTagsForResource"
        ]
        Resource = "arn:aws:codepipeline:${var.region}:${var.account_id}:${var.project_name}-*"
      }
    ]
  })
}

# =============================================================================
# POLICY 3 — Platform
# Covers: S3 (state + artifact buckets), IAM (project-scoped roles/policies),
#         CloudWatch Logs, STS (GetCallerIdentity for Terragrunt),
#         ACM certificates, Route53 (DNS for app subdomain),
#         IAM Identity Center (SSO) permission set management
# =============================================================================
resource "aws_iam_policy" "devops_platform" {
  name        = "${var.project_name}-devops-platform"
  path        = "/${var.project_name}/"
  description = "S3, IAM, CloudWatch Logs, STS, ACM, Route53, and SSO for ${var.project_name} devops operators"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3StateBucket"
        Effect = "Allow"
        Action = [
          "s3:CreateBucket", "s3:DeleteBucket", "s3:HeadBucket",
          "s3:GetBucketLocation", "s3:GetBucketVersioning",
          "s3:PutBucketVersioning",
          "s3:GetBucketEncryption", "s3:PutBucketEncryption",
          "s3:GetBucketTagging", "s3:PutBucketTagging",
          "s3:GetBucketPolicy", "s3:PutBucketPolicy", "s3:DeleteBucketPolicy",
          "s3:GetBucketPublicAccessBlock", "s3:PutBucketPublicAccessBlock",
          "s3:GetBucketAcl", "s3:GetBucketObjectLockConfiguration",
          "s3:PutBucketObjectLockConfiguration",
          "s3:ListBucket", "s3:GetObject", "s3:PutObject", "s3:DeleteObject"
        ]
        Resource = [
          "arn:aws:s3:::${var.project_name}-tfstate-${var.account_id}",
          "arn:aws:s3:::${var.project_name}-tfstate-${var.account_id}/*",
          "arn:aws:s3:::${var.project_name}-*-pipeline-artifacts-${var.account_id}",
          "arn:aws:s3:::${var.project_name}-*-pipeline-artifacts-${var.account_id}/*"
        ]
      },
      {
        Sid    = "IAMRolesProjectScoped"
        Effect = "Allow"
        Action = [
          "iam:CreateRole", "iam:DeleteRole",
          "iam:GetRole", "iam:ListRoles",
          "iam:PutRolePolicy", "iam:DeleteRolePolicy",
          "iam:GetRolePolicy", "iam:ListRolePolicies",
          "iam:AttachRolePolicy", "iam:DetachRolePolicy",
          "iam:ListAttachedRolePolicies",
          "iam:TagRole", "iam:UntagRole", "iam:ListRoleTags",
          "iam:UpdateAssumeRolePolicy"
        ]
        Resource = "arn:aws:iam::${var.account_id}:role/${var.project_name}-*"
      },
      {
        Sid    = "IAMPoliciesProjectScoped"
        Effect = "Allow"
        Action = [
          "iam:CreatePolicy", "iam:DeletePolicy",
          "iam:GetPolicy", "iam:GetPolicyVersion",
          "iam:ListPolicies", "iam:ListPolicyVersions",
          "iam:CreatePolicyVersion", "iam:DeletePolicyVersion",
          "iam:SetDefaultPolicyVersion",
          "iam:TagPolicy", "iam:UntagPolicy", "iam:ListPolicyTags"
        ]
        Resource = "arn:aws:iam::${var.account_id}:policy/${var.project_name}/*"
      },
      {
        Sid    = "IAMPassRole"
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = "arn:aws:iam::${var.account_id}:role/${var.project_name}-*"
        Condition = {
          StringLike = {
            "iam:PassedToService" = [
              "ecs-tasks.amazonaws.com",
              "codepipeline.amazonaws.com",
              "codebuild.amazonaws.com",
              "codedeploy.amazonaws.com"
            ]
          }
        }
      },
      {
        Sid    = "IAMGetPolicies"
        Effect = "Allow"
        Action = [
          "iam:GetPolicy", "iam:GetPolicyVersion",
          "iam:ListPolicies", "iam:ListPolicyVersions"
        ]
        Resource = [
          "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy",
          "arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS"
        ]
      },
      {
        Sid    = "CloudWatchLogsDescribe"
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:ListTagsLogGroup",
          "logs:ListTagsForResource"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchLogsManagement"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup", "logs:DeleteLogGroup",
          "logs:PutRetentionPolicy", "logs:DeleteRetentionPolicy",
          "logs:TagLogGroup", "logs:UntagLogGroup",
          "logs:TagResource", "logs:UntagResource"
        ]
        Resource = [
          "arn:aws:logs:${var.region}:${var.account_id}:log-group:/ecs/${var.project_name}-*",
          "arn:aws:logs:${var.region}:${var.account_id}:log-group:/ecs/${var.project_name}-*:*",
          "arn:aws:logs:${var.region}:${var.account_id}:log-group:/aws/codebuild/${var.project_name}-*",
          "arn:aws:logs:${var.region}:${var.account_id}:log-group:/aws/codebuild/${var.project_name}-*:*"
        ]
      },
      {
        Sid    = "STSCallerIdentity"
        Effect = "Allow"
        Action = "sts:GetCallerIdentity"
        Resource = "*"
      },
      {
        Sid    = "ACMManagement"
        Effect = "Allow"
        Action = [
          "acm:RequestCertificate", "acm:DeleteCertificate",
          "acm:DescribeCertificate", "acm:ListCertificates",
          "acm:AddTagsToCertificate", "acm:RemoveTagsFromCertificate",
          "acm:ListTagsForCertificate"
        ]
        Resource = "*"
      },
      {
        Sid    = "Route53Management"
        Effect = "Allow"
        Action = [
          "route53:GetHostedZone", "route53:ListHostedZones",
          "route53:ListHostedZonesByName",
          "route53:ChangeResourceRecordSets",
          "route53:ListResourceRecordSets",
          "route53:GetChange"
        ]
        Resource = "*"
      },
      {
        Sid    = "SNSList"
        Effect = "Allow"
        Action = [
          "sns:ListTopics",
          "sns:ListSubscriptions"
        ]
        Resource = "*"
      },
      {
        Sid    = "SNSManagement"
        Effect = "Allow"
        Action = [
          "sns:CreateTopic", "sns:DeleteTopic",
          "sns:GetTopicAttributes", "sns:SetTopicAttributes",
          "sns:Subscribe", "sns:Unsubscribe",
          "sns:GetSubscriptionAttributes", "sns:SetSubscriptionAttributes",
          "sns:ListSubscriptionsByTopic",
          "sns:TagResource", "sns:UntagResource", "sns:ListTagsForResource"
        ]
        Resource = "arn:aws:sns:${var.region}:${var.account_id}:${var.project_name}-*"
      },
      {
        # Allows devops operators to manage SSO permission sets and account
        # assignments for this project via Terraform (sso module).
        Sid    = "SSOManagement"
        Effect = "Allow"
        Action = [
          "sso:CreatePermissionSet", "sso:DeletePermissionSet",
          "sso:DescribePermissionSet", "sso:ListPermissionSets",
          "sso:UpdatePermissionSet",
          "sso:AttachCustomerManagedPolicyReferenceToPermissionSet",
          "sso:DetachCustomerManagedPolicyReferenceFromPermissionSet",
          "sso:ListCustomerManagedPolicyReferencesInPermissionSet",
          "sso:CreateAccountAssignment", "sso:DeleteAccountAssignment",
          "sso:DescribeAccountAssignmentCreationStatus",
          "sso:ListAccountAssignments",
          "sso:TagResource", "sso:UntagResource", "sso:ListTagsForResource",
          "sso:DescribePermissionSetProvisioningStatus",
          "sso:ProvisionPermissionSet",
          "identitystore:DescribeUser", "identitystore:ListUsers"
        ]
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# OUTPUTS
# Policy ARNs are referenced by the SSO module's
# aws_ssoadmin_customer_managed_policy_attachment resources.
# =============================================================================
output "devops_networking_policy_arn" { value = aws_iam_policy.devops_networking.arn }
output "devops_compute_policy_arn"    { value = aws_iam_policy.devops_compute.arn }
output "devops_platform_policy_arn"   { value = aws_iam_policy.devops_platform.arn }
