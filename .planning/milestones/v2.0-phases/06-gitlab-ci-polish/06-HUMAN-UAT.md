---
status: partial
phase: 06-gitlab-ci-polish
source: [06-VERIFICATION.md]
started: 2026-05-31T00:00:00Z
updated: 2026-05-31T00:00:00Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. Help text on bash 4+
expected: `./run help` shows BOLD group headers (AMI, Terraform/OpenTofu, Instance lifecycle, SSM access, Secrets, Diagnostics, Cleanup); doctor command listed under Diagnostics
result: [pending]

### 2. CI bake pipeline runtime
expected: GitLab CI with PIPELINE_KIND=bake on protected branch runs `./run build` without bash/packer errors in hashicorp/packer image
result: [pending]

### 3. CI deploy pipeline runtime
expected: GitLab CI with PIPELINE_KIND=deploy + DEVBOX_USER runs `./run tf-init` (with `-lockfile=readonly`) + `./run tf-auto-apply` without errors in opentofu image; requires valid AWS credentials
result: [pending]

## Summary

total: 3
passed: 0
issues: 0
pending: 3
skipped: 0
blocked: 0

## Gaps
