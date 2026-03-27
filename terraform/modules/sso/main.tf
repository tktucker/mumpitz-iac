# =============================================================================
# SSO MODULE — AWS IAM Identity Center (formerly SSO)
# =============================================================================
#
# Replaces the devops-user IAM access keys with federated access via
# IAM Identity Center. After apply:
#
#   1. The user must exist in IAM Identity Center (create via Console or
#      aws sso-admin create-user if using an internal identity store).
#   2. Users log in at: https://<sso-start-url>.awsapps.com/start
#   3. CLI access: `aws configure sso` with the start URL and region.
#   4. Profile example (~/.aws/config):
#        [profile mumpitz-dev]
#        sso_start_url = https://<your-sso-start-url>.awsapps.com/start
#        sso_region    = us-east-1
#        sso_account_id = 537252853137
#        sso_role_name = mumpitz-devops
#
# The three customer-managed policies attached here are created in
# iac-repo/terraform/modules/iam/main.tf:
#   - mumpitz-devops-networking
#   - mumpitz-devops-compute
#   - mumpitz-devops-platform
# =============================================================================

variable "project_name"  { type = string }
variable "environment"   { type = string }
variable "sso_username"  { type = string }  # IAM Identity Center username (email), e.g. "tktucker@gmail.com"

# -----------------------------------------------------------------------------
# Discover the SSO instance (only one per AWS account/region is supported)
# This data source reads the existing IAM Identity Center instance —
# it does NOT create one. SSO must be enabled in the account first.
# -----------------------------------------------------------------------------
data "aws_ssoadmin_instances" "main" {}

locals {
  sso_instance_arn  = tolist(data.aws_ssoadmin_instances.main.arns)[0]
  identity_store_id = tolist(data.aws_ssoadmin_instances.main.identity_store_ids)[0]
}

# -----------------------------------------------------------------------------
# Permission Set — mumpitz-devops
#
# Session duration of 8 hours balances security (shorter than the 12-hour max)
# with developer convenience (avoids re-auth mid-workday).
# No AWS-managed policies are attached — only customer-managed policies.
# -----------------------------------------------------------------------------
resource "aws_ssoadmin_permission_set" "devops" {
  name             = "${var.project_name}-devops"
  description      = "DevOps access for ${var.project_name} infrastructure operators"
  instance_arn     = local.sso_instance_arn
  session_duration = "PT8H"

  tags = {
    Name    = "${var.project_name}-devops"
    Project = var.project_name
  }
}

# -----------------------------------------------------------------------------
# Attach the three customer-managed policies to the permission set.
#
# These policies are defined in modules/iam/main.tf and must be applied
# (terraform apply on the iam module) before this module can attach them.
# If applying for the first time, apply iam first, then sso.
# -----------------------------------------------------------------------------
resource "aws_ssoadmin_customer_managed_policy_attachment" "networking" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.devops.arn

  customer_managed_policy_reference {
    name = "${var.project_name}-devops-networking"
    path = "/mumpitz/"
  }
}

resource "aws_ssoadmin_customer_managed_policy_attachment" "compute" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.devops.arn

  customer_managed_policy_reference {
    name = "${var.project_name}-devops-compute"
    path = "/mumpitz/"
  }
}

resource "aws_ssoadmin_customer_managed_policy_attachment" "platform" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.devops.arn

  customer_managed_policy_reference {
    name = "${var.project_name}-devops-platform"
    path = "/mumpitz/"
  }
}

# -----------------------------------------------------------------------------
# Look up the IAM Identity Center user by username (email address).
#
# The user must already exist in the Identity Store — either synced from
# an external IdP (Okta, Azure AD) or created manually in the IAM
# Identity Center console.
# -----------------------------------------------------------------------------
data "aws_identitystore_user" "devops" {
  identity_store_id = local.identity_store_id

  alternate_identifier {
    unique_attribute {
      attribute_path  = "UserName"
      attribute_value = var.sso_username
    }
  }
}

# -----------------------------------------------------------------------------
# Account Assignment — grant the user the devops permission set
# in the current AWS account.
# -----------------------------------------------------------------------------
resource "aws_ssoadmin_account_assignment" "devops" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.devops.arn

  principal_type = "USER"
  principal_id   = data.aws_identitystore_user.devops.user_id

  target_type = "AWS_ACCOUNT"
  target_id   = data.aws_caller_identity.current.account_id
}

data "aws_caller_identity" "current" {}

# =============================================================================
# OUTPUTS
# =============================================================================
output "permission_set_arn" { value = aws_ssoadmin_permission_set.devops.arn }
output "sso_instance_arn"   { value = local.sso_instance_arn }
