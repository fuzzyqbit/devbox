# Phase 5: shared per-environment defaults previously held in `terragrunt.hcl`
# `inputs`. Terraform auto-loads `terraform.tfvars` from the module directory.
# Per-operator values (`ami_id`, `key_name`, `allowed_web_cidrs`) flow via
# `users/${USER}.auto.tfvars` (gitignored, written by `make packer-bake` /
# `make devbox-allowlist-me`) or via `-var` flags from the Makefile.

aws_region       = "us-east-1"
vpc_id           = "vpc-0dafcc61f21dac9cd"
subnet_id        = "subnet-07513680b824b3dbe"
instance_type    = "t3.medium"
instance_name    = "devbox"
root_volume_size = 50
