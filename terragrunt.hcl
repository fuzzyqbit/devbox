locals {
  user       = get_env("DEVBOX_USER", get_env("USER", "default"))
  account_id = get_aws_account_id()
}

terraform_binary = "tofu"

terraform {
  source = "./terraform"
}

remote_state {
  backend = "s3"
  generate = {
    path      = "terraform/backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    bucket         = "devimage-tfstate-${local.account_id}"
    key            = "users/${local.user}/devbox.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "devimage-tfstate-locks"
  }
}

# Phase 3 (REP-05): ami_id is intentionally not set in `inputs` below. It is
# supplied by users/${local.user}.auto.tfvars, which `make packer-bake` writes
# after a successful Packer build and which Terraform auto-loads from the
# module directory. If the file is missing, var.ami_id has no default (see
# terraform/variables.tf) so `terragrunt plan` errors loudly — exactly the
# loud-failure mode the handoff design wants. See Pattern 5 in
# .planning/phases/03-reproducibility-version-pinning/03-RESEARCH.md:292-346.
inputs = {
  devbox_user      = local.user
  key_name         = "me"
  subnet_id        = "subnet-07513680b824b3dbe"
  vpc_id           = "vpc-0dafcc61f21dac9cd"
  instance_type    = "t3.medium"
  root_volume_size = 50
  instance_name    = "devbox"
  aws_region       = "us-east-1"
}
