# Phase 5 (post-v1.0): Terragrunt removed. Backend wired directly with a partial
# S3 config — bucket + key supplied at init time via `-backend-config` flags.
# See Makefile `tf-init` target for the canonical invocation.
#
# Why partial: bucket name varies per AWS account (derived from
# `aws sts get-caller-identity`); key varies per operator
# (`users/${DEVBOX_USER}/devbox.tfstate`). The remaining fields are
# per-account constants.

terraform {
  backend "s3" {
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "devimage-tfstate-locks"
  }
}
