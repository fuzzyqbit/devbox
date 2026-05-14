locals {
  user       = get_env("DEVBOX_USER", get_env("USER", "default"))
  account_id = get_aws_account_id()

  # Phase 2: aggregate CIDRs from two env vars (CODE_SERVER_ALLOWED_CIDRS and
  # VNC_ALLOWED_CIDRS). Each is a comma-separated list of CIDRs; empty/unset
  # produces []. Operators who prefer a file can ignore these env vars and
  # let `make devbox-allowlist-me` write allowlist.auto.tfvars (gitignored).
  # The Terraform validation block in terraform/variables.tf is the gate that
  # rejects an empty result unless var.allow_open_ingress = true.
  code_server_cidrs_raw = get_env("CODE_SERVER_ALLOWED_CIDRS", "")
  vnc_cidrs_raw         = get_env("VNC_ALLOWED_CIDRS", "")
  code_server_cidrs     = local.code_server_cidrs_raw == "" ? [] : split(",", local.code_server_cidrs_raw)
  vnc_cidrs             = local.vnc_cidrs_raw == "" ? [] : split(",", local.vnc_cidrs_raw)
  # Union, deduped, whitespace-trimmed.
  allowed_web_cidrs = distinct([
    for c in concat(local.code_server_cidrs, local.vnc_cidrs) :
    trimspace(c) if trimspace(c) != ""
  ])
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

inputs = {
  devbox_user = local.user
  ami_id      = "ami-0b7cfe2135f319a55"
  # Per-operator SSH key. Operator must `aws ec2 import-key-pair` once before tg-apply.
  # See `make secrets-show` and Phase 1 docs for the rotation procedure.
  key_name         = "${local.user}-devbox"
  subnet_id        = "subnet-07513680b824b3dbe"
  vpc_id           = "vpc-0dafcc61f21dac9cd"
  instance_type    = "t3.medium"
  root_volume_size = 50
  instance_name    = "devbox"
  aws_region       = "us-east-1"

  # Phase 2: CIDR allowlist for code-server (:8080) and noVNC (:6080).
  # Sourced from CODE_SERVER_ALLOWED_CIDRS / VNC_ALLOWED_CIDRS env vars
  # (comma-separated). If both are unset, this stays [] and Terraform's
  # validation block rejects apply (unless var.allow_open_ingress = true).
  # The file-based path is `make devbox-allowlist-me` which writes
  # allowlist.auto.tfvars (gitignored).
  allowed_web_cidrs = local.allowed_web_cidrs
}
