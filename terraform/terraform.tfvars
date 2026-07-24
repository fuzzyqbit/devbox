# Phase 5: shared per-environment defaults previously held in `terragrunt.hcl`
# `inputs`. Terraform auto-loads `terraform.tfvars` from the module directory.
# `ami_id` is resolved via a `data "aws_ami"` filter (or per-operator tfvars).
# `key_name` flows via `-var` from `./run`.
# `allowed_web_cidrs` is operator-managed externally — supply via your own
# tfvars / `-var` / `TF_VAR_allowed_web_cidrs`.

aws_region       = "us-east-1"
vpc_id           = "vpc-0dafcc61f21dac9cd"
subnet_id        = "subnet-07513680b824b3dbe"
instance_type    = "t3.medium"
instance_name    = "devbox"
root_volume_size = 50

# Shared-runner IAM variant — opt-in, off by default. Attaches the ORG-SUPPLIED
# permissions boundary to the instance role and grants explicit S3/EC2/caged-IAM
# permissions. The boundary policy is never created here — governance owns it.
# Example (fake account id):
# enable_runner_iam               = true
# runner_permissions_boundary_arn = "arn:aws:iam::123456789012:policy/org-boundary"
