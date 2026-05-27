---
status: partial
phase: 05-run-script-core
source: [05-VERIFICATION.md]
started: 2026-05-27T14:30:00Z
updated: 2026-05-27T14:30:00Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. End-to-end help output
expected: `./run help` prints all 20 commands in 6 groups (AMI, Terraform, Lifecycle, SSM, Secrets, Cleanup)
result: [pending]

### 2. DEVBOX_USER guard end-to-end
expected: `DEVBOX_USER= ./run tf-plan` exits 1 with "DEVBOX_USER" in stderr; `DEVBOX_USER=UPPER ./run tf-plan` exits 1 with "invalid" in stderr
result: [pending]

### 3. Live AWS integration
expected: `./run tf-init` with valid AWS creds derives TF_STATE_BUCKET correctly and passes through to tofu
result: [pending]

## Summary

total: 3
passed: 0
issues: 0
pending: 3
skipped: 0
blocked: 0

## Gaps
