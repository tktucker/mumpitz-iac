# =============================================================================
# ROOT TERRAGRUNT CONFIGURATION
# =============================================================================
#
# This file sits at the root of the iac-repo and is inherited by every child
# terragrunt.hcl via the `include "root"` block.
#
# What Terragrunt does here that plain Terraform cannot:
#   1. GENERATES backend.tf in the working directory before terraform init —
#      no need to commit a backend.tf with a hard-coded account ID.
#   2. AUTO-CREATES the S3 bucket on first run when --backend-bootstrap is
#      passed (Terragrunt v0.67+ requires this flag for explicit opt-in).
#   3. UNIQUE STATE KEYS per environment via path_relative_to_include() —
#      deploy dev and prod from the same Terraform code with separate state.
#   4. DRY VERSION CONSTRAINTS via the generate block — one source of truth
#      for the provider version, shared by every child config.
#
# STATE LOCKING — S3 native locking (use_lockfile = true):
#   The AWS Terraform provider deprecated the dynamodb_table backend parameter.
#   The replacement is use_lockfile = true, which uses S3 conditional writes
#   for locking with no separate DynamoDB table required.
#   Both mechanisms prevent concurrent state writes. DynamoDB locking
#   was the classic pattern; S3 native locking is the current best practice.
#
# FIRST-TIME SETUP:
#   Terragrunt v0.67+ does not auto-create the S3 bucket silently.
#   Pass --backend-bootstrap once to provision the bucket:
#     terragrunt plan --backend-bootstrap
#   Subsequent runs (bucket already exists) need no extra flag:
#     terragrunt plan
#     terragrunt apply
# =============================================================================

# ---------------------------------------------------------------------------
# Locals — shared values referenced throughout this file and child configs
# ---------------------------------------------------------------------------
locals {
  project_name = "mumpitz"
  aws_region   = "us-east-1"

  # get_aws_account_id() calls sts:GetCallerIdentity at plan/apply time.
  # The account ID is resolved at runtime and never committed to the repo.
  account_id = get_aws_account_id()

  # Derive a consistent, globally unique S3 bucket name.
  state_bucket = "${local.project_name}-tfstate-${local.account_id}"
}

# ---------------------------------------------------------------------------
# Remote State — S3 backend with native S3 locking
#
# The `generate` sub-block tells Terragrunt to write backend.tf into the
# Terraform working directory before running terraform init.
# if_exists = "overwrite_terragrunt" ensures it is always refreshed on each
# run; never commit the generated file (it is listed in .gitignore).
#
# Keys written into the generated backend.tf:
#   bucket, key, region, encrypt, use_lockfile
#
# Keys consumed by Terragrunt only (NOT forwarded to backend.tf):
#   s3_bucket_tags, skip_bucket_versioning
#
# State key pattern: <path_relative_to_include>/terraform.tfstate
#   terraform/terragrunt.hcl  → terraform/terraform.tfstate  (stack config)
#   live/dev/terragrunt.hcl   → live/dev/terraform.tfstate   (multi-env pattern)
#   live/prod/terragrunt.hcl  → live/prod/terraform.tfstate
# All child terragrunt.hcl files include this root via:
#   find_in_parent_folders("root.hcl")
# ---------------------------------------------------------------------------
remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    bucket       = local.state_bucket
    key          = "${path_relative_to_include()}/terraform.tfstate"
    region       = local.aws_region
    encrypt      = true

    # use_lockfile replaces the deprecated dynamodb_table parameter.
    # Terraform uses S3 conditional writes (If-None-Match / If-Match) to
    # acquire and release a lock file in the same bucket — no DynamoDB needed.
    use_lockfile = true

    # Terragrunt-only: applied when --backend-bootstrap creates the bucket.
    # These keys are NOT forwarded to the generated backend.tf.
    s3_bucket_tags = {
      Name      = local.state_bucket
      ManagedBy = "terragrunt"
      Purpose   = "terraform-remote-state"
      Project   = local.project_name
    }

    # skip_bucket_versioning = false → Terragrunt enables versioning on the
    # bucket it creates. False is the default; shown here for documentation.
    skip_bucket_versioning = false
  }
}

# ---------------------------------------------------------------------------
# Generate — versions_generated.tf
#
# Writes the terraform { required_version / required_providers } block into
# the working directory at plan/apply time.
# Centralising it here means bumping the provider version is a one-line edit.
# Never commit the generated file (listed in .gitignore).
# ---------------------------------------------------------------------------
generate "versions" {
  path      = "versions_generated.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    # AUTO-GENERATED by root.hcl — do not edit manually.
    terraform {
      required_version = ">= 1.5.0"
      required_providers {
        aws = {
          source  = "hashicorp/aws"
          version = "~> 5.0"
        }
      }
    }
  EOF
}
