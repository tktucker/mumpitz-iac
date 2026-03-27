# mumpitz — IaC Repository

Terraform infrastructure managed by **Terragrunt** for the AWS CI/CD Demo project.
Provisions CodeCommit, CodeBuild, CodePipeline, CodeDeploy, ECS Fargate, ECR, VPC, and IAM.

Remote state is stored in **S3** with **native S3 locking** (`use_lockfile = true`).
No DynamoDB table is needed. Create the S3 bucket manually once, then run `terragrunt plan`.

> **Two-repo model:** This repo manages infrastructure only.
> Application source code lives in the companion **app-repo** (`mumpitz-app`).

---

## Why Terragrunt?

| Problem with plain Terraform | How Terragrunt solves it |
|---|---|
| `backend.tf` requires hard-coded account IDs → can't be safely committed | `remote_state` generates `backend.tf` at run time using `get_aws_account_id()` |
| State bucket must be created before `terraform init` | Pass `--backend-bootstrap` once — Terragrunt creates and configures the S3 bucket |
| Every environment needs its own copy of backend config | `path_relative_to_include()` gives each env a unique state key automatically |
| Repeating `provider` + version constraints across stacks | Root `generate "versions"` block is the single source of truth |
| `terraform.tfvars` files often get committed with secrets | `inputs` block reads secrets from env vars via `get_env()` |

---

## Repository Structure

```
iac-repo/
├── terragrunt.hcl                 # ROOT: remote_state (S3+DynamoDB) + generate "versions"
├── terraform/
│   ├── terragrunt.hcl             # STACK: include "root" + all variable inputs
│   ├── main.tf                    # Root module wiring all sub-modules
│   ├── variables.tf               # Variable declarations (no defaults required — inputs supplies them)
│   ├── outputs.tf                 # Stack outputs
│   ├── provider.tf                # AWS provider config (no backend block — Terragrunt generates it)
│   └── modules/
│       ├── iam/          main.tf  # IAM roles for Pipeline, Build, Deploy, ECS
│       ├── ecr/          main.tf  # ECR repository + lifecycle policy
│       ├── vpc/          main.tf  # VPC, subnets, NAT gateway, security groups
│       ├── ecs/          main.tf  # ECS Cluster, Task Def, ALB (blue/green target groups)
│       ├── codecommit/   main.tf  # app-repo + iac-repo CodeCommit repositories
│       ├── codebuild/    main.tf  # One CodeBuild project per pipeline stage
│       ├── codedeploy/   main.tf  # ECS blue/green app + deployment group
│       └── codepipeline/ main.tf  # CodePipeline + S3 artifact bucket
└── README.md
```

### Files Terragrunt writes at run time (never committed)

| Generated file | Written by | Purpose |
|---|---|---|
| `terraform/backend.tf` | `remote_state.generate` in root `terragrunt.hcl` | S3 backend config with auto-resolved account ID and state key |
| `terraform/versions_generated.tf` | `generate "versions"` in root `terragrunt.hcl` | `terraform {}` block with `required_version` and `required_providers` |
| `terraform/.terragrunt-cache/` | Terragrunt internal | Local module cache — safe to delete at any time |

---

## Prerequisites

```bash
# Install Terraform
brew install terraform        # macOS
# or: https://developer.hashicorp.com/terraform/install

# Install Terragrunt
brew install terragrunt       # macOS
# or: https://terragrunt.gruntwork.io/docs/getting-started/install/

# Authenticate AWS CLI
aws configure
# Minimum IAM permissions needed: see modules/iam/main.tf for the full list
```

---

## Deployment

### First deploy

Terragrunt v0.67+ requires `--backend-bootstrap` the first time to create the S3 bucket.

```bash
cd iac-repo/terraform

# First run only — provisions the S3 state bucket and runs the plan
terragrunt plan --backend-bootstrap

# Apply
terragrunt apply --backend-bootstrap
```

On first run with `--backend-bootstrap`, Terragrunt will:
1. Call `sts:GetCallerIdentity` to resolve `get_aws_account_id()`
2. Create S3 bucket `mumpitz-tfstate-<account_id>` with versioning + SSE-S3
3. Write `backend.tf` (with `use_lockfile = true`) and `versions_generated.tf` into `terraform/`
4. Run `terraform init` with the generated backend
5. Run `terraform plan` / `terraform apply`

### Subsequent deploys

Once the bucket exists the flag is not needed:

```bash
cd iac-repo/terraform
terragrunt plan
terragrunt apply
```

### Push app code to trigger the pipeline

```bash
# Get the app-repo clone URL from Terragrunt outputs
terragrunt output app_repo_clone_url_http

git clone <url> app-repo-local
cd app-repo-local
# Copy contents of the companion app-repo/ directory here
git add . && git commit -m "Initial commit" && git push origin main
# → Triggers CodePipeline automatically via EventBridge
```

---

## Multi-Environment Pattern

To deploy to `prod` with isolated state and different capacity settings,
create `live/prod/terragrunt.hcl` inheriting the same root config:

```
iac-repo/
├── terragrunt.hcl            # Root config (shared)
├── live/
│   ├── dev/
│   │   └── terragrunt.hcl   # include root + dev inputs
│   └── prod/
│       └── terragrunt.hcl   # include root + prod inputs (larger tasks, canary deploy)
└── terraform/
    └── ...
```

```hcl
# live/prod/terragrunt.hcl
include "root" {
  path   = find_in_parent_folders()
  expose = true
}

inputs = {
  aws_region        = include.root.locals.aws_region
  project_name      = include.root.locals.project_name
  environment       = "prod"
  app_desired_count = 4
  app_cpu           = 512
  app_memory        = 1024
  deployment_config = "CodeDeployDefault.ECSCanary10Percent15Minutes"
}
```

State keys are automatically isolated:
- `live/dev/terraform.tfstate`
- `live/prod/terraform.tfstate`

Deploy either environment:
```bash
cd iac-repo/live/dev  && terragrunt apply
cd iac-repo/live/prod && terragrunt apply
```

---

## Key Variables (set in `terraform/terragrunt.hcl` inputs block)

| Variable | Dev default | Notes |
|---|---|---|
| `app_repo_name` | `mumpitz-app` | CodeCommit repo that triggers CodePipeline |
| `iac_repo_name` | `mumpitz-iac` | CodeCommit repo for this IaC (not pipeline source) |
| `deployment_config` | `ECSAllAtOnce` | Change to canary/linear to study traffic shifting |
| `termination_wait_time` | `5` | Minutes before blue task set is terminated post-deploy |
| `app_desired_count` | `2` | ECS task count; increase for prod HA |

---

## Useful Commands

```bash
# First-time only — creates the S3 state bucket
terragrunt plan --backend-bootstrap

# Plan without applying (bucket already exists)
terragrunt plan

# Apply with auto-approve (CI use only)
terragrunt apply --auto-approve

# Destroy all resources (use with caution)
terragrunt destroy

# Show current outputs
terragrunt output

# Force re-initialize (useful after .terraform.lock.hcl changes)
terragrunt init --reconfigure

# Clear Terragrunt's local module cache
rm -rf terraform/.terragrunt-cache/
```
