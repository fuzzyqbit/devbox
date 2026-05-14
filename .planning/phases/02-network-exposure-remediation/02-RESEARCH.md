# Phase 2: Network Exposure Remediation — Research

**Researched:** 2026-05-13
**Domain:** AWS EC2 / VPC / SSM Session Manager / Terraform networking
**Confidence:** HIGH

## Summary

**Primary recommendation (one-liner):** Adopt the **hybrid posture** — use AWS SSM Session Manager to eliminate the `:22` ingress entirely, and apply an operator-supplied CIDR allowlist (default `[]`, refuses apply when empty) to code-server `:8080` and noVNC `:6080`; this closes every `0.0.0.0/0` rule while preserving the browser-only operator UX that the project's Core Value already demands.

The devbox is a personal cloud workstation whose Core Value explicitly forbids "exposing a vulnerable host to the public internet." Three security-group rules currently violate that: `:22`, `:8080`, and `:6080` are all `cidr_blocks = ["0.0.0.0/0"]` (`terraform/main.tf:100,109,118`). Phase 1 already built every dependency this phase needs: the EC2 has a per-instance IAM role (`aws_iam_role.devbox`), IMDSv2 is enforced, and AL2023 ships with the SSM Agent preinstalled. Attaching a single AWS-managed policy (`AmazonSSMManagedInstanceCore`) flips on Session Manager without any new infrastructure. The browser-based services (code-server, noVNC) cannot run "through SSM" the same way SSH can — they are HTTPS services the operator opens in a browser — so they must either keep public ingress restricted to operator CIDRs or be tunneled via SSM port forwarding. The hybrid keeps the operator's everyday browser workflow simple while removing the highest-risk surface (SSH brute force) entirely.

The remaining open decisions are mechanical: variable shape, validation pattern, the Makefile target list, the discovery UX for "what's my public IP," and the lockout-recovery script. None of those decisions are technology bets — they're ergonomics. The recommendation below picks one defensible answer for each so the planner can move directly to task breakdown.

## User Constraints (from CONTEXT.md)

> No CONTEXT.md exists yet for Phase 2 — `/gsd-plan-phase` invocation went directly to research per the orchestrator's call. The locked decisions below come from PROJECT.md Key Decisions and ROADMAP.md Phase 2 details; treat them as locked-equivalent.

### Locked Decisions (from PROJECT.md / ROADMAP.md / STATE.md)

- The third remaining CRITICAL finding (`0.0.0.0/0` on `:22`, `:8080`, `:6080`) MUST close in Phase 2.
- Phase 1 IAM groundwork is reusable: `aws_iam_role.devbox` + `aws_iam_instance_profile.devbox` already exist on every devbox.
- IMDSv2 is enforced (`http_tokens = required`).
- The operator surface MUST remain `make <target>` — no new GUI, no new mandatory CLIs beyond what's already required (`aws`, `jq`, `packer`, `tofu`, `terragrunt`, `ansible`).
- AL2023 minimal x86_64 is the base AMI; CIS hardening is applied during bake (`ansible/roles/AMAZON2023-CIS`).
- Default region is `us-east-1`; single region per operator.
- Per-operator SSH key `${devbox_user}-devbox` (Phase 1).
- ROADMAP.md Phase 2 risks/notes states: "Bias toward SSM since the IAM groundwork is already laid."

### Claude's Discretion

- Pick the exact decision (SSM vs CIDR vs hybrid) and justify.
- Choose Terraform variable shape and validation mechanism.
- Choose Makefile target names and operator UX for IP discovery.
- Choose `scripts/devbox-status.sh` rewrite.
- Choose lockout-recovery procedure.

### Deferred Ideas (OUT OF SCOPE)

- TLS certificate hardening for noVNC (self-signed cert with 10-year life is LOW per CONCERNS.md — defer).
- Authenticated reverse proxy (oauth2-proxy + Cognito, CloudFront signed URLs) — out of scope for Milestone 1.
- VPC endpoints for fully-private subnet (the current devbox sits in a subnet with `associate_public_ip = true`; the VPC endpoint path is unneeded for the current topology).
- Replacing `:22` ingress for any non-operator use (no fleet/multi-tenant access patterns exist).

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| NET-01 | SG ingress for SSH (:22) restricted to operator-supplied CIDR list with `[]` default that refuses apply, OR removed entirely via SSM Session Manager | Recommendation §1 below resolves to "remove SSH ingress entirely via SSM"; fallback CIDR pattern documented in §2. |
| NET-02 | SG ingress for code-server (:8080) restricted to operator-supplied CIDR list, default `[]` refuses apply | Variable + validation pattern in §2; `dynamic "ingress"` block in §3. |
| NET-03 | SG ingress for noVNC (:6080) restricted to operator-supplied CIDR list, default `[]` refuses apply | Same pattern as NET-02; can share the same `var.allowed_web_cidrs` list. |
| NET-04 | Decision recorded in PROJECT.md Key Decisions; implement chosen option | Hybrid recommendation in §1; PROJECT.md row template in §11. |

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| SSH shell access to devbox | AWS control plane (SSM Session Manager) | EC2 instance OS (sshd, AL2023) | SSM brokers the shell over WebSocket+TLS; no inbound port required. sshd stays running locally because Phase 1 + CIS already configured it and it's needed for SCP/rsync via the SSM SSH tunnel pattern. |
| code-server browser access | EC2 instance OS (code-server on :8080) | Operator-supplied CIDR (SG ingress) | code-server is an HTTPS server bound to `0.0.0.0:8080`. The browser hits it directly. The SG is the only gatekeeper before TLS terminates inside the host. |
| noVNC browser access | EC2 instance OS (noVNC on :6080) | Operator-supplied CIDR (SG ingress) | Same shape as code-server. noVNC reverse-proxies the localhost-bound VNC server. |
| Operator IP discovery | Operator workstation (`curl checkip.amazonaws.com`) | AWS-published service | The IP must be supplied by the operator before TF runs; AWS provides a free plain-text echo service that returns the caller's source IP. |
| Lockout recovery | AWS control plane (SSM Session Manager) | Terraform (re-apply with updated CIDR) | If the operator's IP changes and they lose web ingress, SSH-over-SSM still works to update tfvars and re-apply. SSM itself never depends on SG ingress. |
| Connection-info surfacing | `scripts/devbox-status.sh` (operator workstation) | Terraform outputs | Status script reads instance ID + region from tfstate and prints the SSM start-session command + the noVNC/code-server URLs. |

## Standard Stack

### Core
| Library / Service | Version | Purpose | Why Standard |
|---|---|---|---|
| AWS SSM Session Manager | service (no version pin) | Brokered shell access without SG ingress; logged in CloudTrail | Zero-cost for EC2; AWS-recommended replacement for ad-hoc SSH; no inbound port required `[CITED: docs.aws.amazon.com/systems-manager]`. |
| `AmazonSSMManagedInstanceCore` managed policy | ARN `arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore` | Grants SSM Agent on the EC2 the permissions needed for Session Manager (ssmmessages, ec2messages, ssm channels) | AWS-managed; sole policy needed to enable core SSM functions `[CITED: docs.aws.amazon.com/aws-managed-policy/.../AmazonSSMManagedInstanceCore.html]`. |
| `amazon-ssm-agent` | preinstalled in AL2023 | The agent that maintains the WebSocket channel to SSM | Preinstalled on AL2023 AMIs by AWS `[CITED: docs.aws.amazon.com/systems-manager/.../ami-preinstalled-agent.html]`. Version may not be latest — agent self-updates if Default Host Management Configuration is on, or via SSM Patch Manager; for this project, the bundled version is sufficient. |
| `session-manager-plugin` (operator workstation) | latest stable via Homebrew cask | AWS CLI plugin that the `aws ssm start-session` command shells out to | Required on every operator workstation that wants to use Session Manager `[CITED: docs.aws.amazon.com/systems-manager/.../session-manager-working-with-install-plugin.html]`. Installable via `brew install --cask session-manager-plugin` on macOS. |
| Terraform `hashicorp/aws` provider | 6.45.0 (already locked) | `aws_iam_role_policy_attachment`, `aws_security_group` with `dynamic "ingress"`, variable validation | Already in use; no new provider needed. |
| Terraform variable validation | language feature ≥ 0.13 | Refuse `apply` if `allowed_web_cidrs == []` | Built into the language; runs before plan generation `[CITED: developer.hashicorp.com/terraform/language/validate]`. |

### Supporting
| Library / Tool | Version | Purpose | When to Use |
|---|---|---|---|
| `curl https://checkip.amazonaws.com` | n/a | Discover operator's current public IP from AWS-hosted echo service | In `make devbox-allowlist-me` helper that auto-writes the operator's `/32` into a tfvars file. `[CITED: per AWS-hosted checkip endpoint, returns plain-text caller IP]`. |
| `aws-ssm-tools` (`mludvig/aws-ssm-tools`) | latest | Optional: `ssm-ssh`, `ssm-tunnel` Python helpers wrapping SSM | NOT recommended as a hard dependency — adds Python install to operator surface. Documented only as a "convenience if you want it" option `[VERIFIED: github.com/mludvig/aws-ssm-tools]`. |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|---|---|---|
| SSM Session Manager for SSH | CIDR allowlist on :22 (`var.allowed_admin_cidrs`) | Simpler tooling story (any SSH client works without extra plugin), but operator-IP-change pain returns; doesn't leverage Phase 1's IAM role; doesn't get CloudTrail audit out of the box. |
| Hybrid (SSM + CIDR on web ports) | All-SSM (close :8080 / :6080 too; use SSM port forwarding) | All-SSM closes 100% of public ingress (better security posture) but requires the operator to run `aws ssm start-session ... --document-name AWS-StartPortForwardingSession` every time they want to use code-server or noVNC — heavy daily UX tax. |
| Hybrid (SSM + CIDR on web ports) | All-CIDR (keep :22 + tighten :8080 / :6080) | Simpler mental model (one mechanism), but keeps SSH brute-force surface and forces a Terraform re-apply every time the operator's IP changes (coffee shops, hotel WiFi, mobile tether). |

**Installation (operator one-time setup):**

```bash
# macOS
brew install --cask session-manager-plugin

# Verify
session-manager-plugin
# Expected: "The Session Manager plugin was installed successfully. Use the AWS CLI..."
```

**Version verification:**

```bash
# AmazonSSMManagedInstanceCore policy ARN is stable / AWS-managed
aws iam get-policy --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore --query 'Policy.{Version:DefaultVersionId,Updated:UpdateDate}'

# SSM agent on a running AL2023 instance
sudo systemctl status amazon-ssm-agent
```

## Architecture Patterns

### System Architecture Diagram

```
Operator workstation                                    AWS account (us-east-1)
========================                                =====================================

  $ make devbox-ssm                                       aws_iam_role.devbox (Phase 1)
        |                                                       |
        v                                                       | + AmazonSSMManagedInstanceCore (Phase 2)
  aws ssm start-session --target i-xxxx ----+                  v
  (session-manager-plugin)                  |             aws_iam_instance_profile.devbox
        |                                   |                  |
        |  WebSocket over TLS:443           |                  v
        +------------------------- AWS SSM Service ---->  aws_instance.devbox
                                                              | (amazon-ssm-agent already running)
                                                              v
                                                          interactive shell
                                                          (no inbound port 22 needed)

  Browser                                                 aws_security_group.devbox
  ===========                                             ==========================
  https://<pub-ip>:8080  ---------- TCP 8080 ----->  ingress { 8080 from var.allowed_web_cidrs }
  https://<pub-ip>:6080  ---------- TCP 6080 ----->  ingress { 6080 from var.allowed_web_cidrs }
                                                          (NO ingress on 22 — SSM handles it)
                                                          egress { all -> 0.0.0.0/0 }
```

Two independent paths:
1. **Shell access** uses Session Manager exclusively. No SG rule. Operator runs `make devbox-ssm` which expands to `aws ssm start-session --target <instance-id>`.
2. **Browser access** still uses public ingress, but locked to `var.allowed_web_cidrs` — typically `["${operator_ip}/32"]`. The operator writes this into a per-operator tfvars file (gitignored) or sets it via the `make devbox-allowlist-me` helper.

### Recommended Project Structure (Phase 2 deltas)

```
terraform/
├── main.tf              # Modified: add aws_iam_role_policy_attachment; replace static ingress with dynamic
├── variables.tf         # Modified: add var.allowed_web_cidrs (list, [] default, validation)
└── outputs.tf           # Modified: add ssm_start_session_command output
scripts/
├── devbox-status.sh     # Modified: print SSM start-session command + browser URLs
├── devbox-ssm.sh        # NEW: thin wrapper for `aws ssm start-session --target $(instance_id)`
└── devbox-allowlist-me.sh  # NEW: curl checkip.amazonaws.com -> writes tfvars
Makefile                 # Modified: add devbox-ssm, devbox-allowlist-me targets
.planning/PROJECT.md     # Modified: Key Decisions row for NET-04 marked ✓ Phase 2
.gitignore               # Modified: add allowlist.auto.tfvars or per-user tfvars file
```

### Pattern 1: `dynamic "ingress"` over a validated CIDR list

```hcl
# terraform/variables.tf
variable "allowed_web_cidrs" {
  type        = list(string)
  default     = []
  description = "CIDR blocks permitted to reach code-server (:8080) and noVNC (:6080). Empty = refuse apply (intentional friction)."

  validation {
    condition     = length(var.allowed_web_cidrs) > 0
    error_message = "allowed_web_cidrs must contain at least one CIDR. Run `make devbox-allowlist-me` to auto-populate your current public IP, or set it explicitly in your tfvars file."
  }

  validation {
    condition     = alltrue([for c in var.allowed_web_cidrs : can(cidrhost(c, 0))])
    error_message = "allowed_web_cidrs entries must be valid CIDR blocks (e.g. 203.0.113.42/32). cidrhost() returned an error for at least one entry."
  }
}

# terraform/main.tf — replaces lines 89-136
resource "aws_security_group" "devbox" {
  name_prefix = "${local.name_prefix}-"
  description = "Security group for devimage instance"
  vpc_id      = var.vpc_id

  # NO ingress on :22 — SSH access is brokered by SSM Session Manager.
  # See Phase 2 RESEARCH.md and PROJECT.md Key Decisions (NET-04).

  dynamic "ingress" {
    for_each = toset(["code-server-8080", "noVNC-6080"])
    content {
      description = ingress.key
      from_port   = ingress.key == "code-server-8080" ? 8080 : 6080
      to_port     = ingress.key == "code-server-8080" ? 8080 : 6080
      protocol    = "tcp"
      cidr_blocks = var.allowed_web_cidrs
    }
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-sg" })

  lifecycle {
    create_before_destroy = true
  }
}
```

Source: `[CITED: developer.hashicorp.com/terraform/language/validate]` for variable validation; `[CITED: registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group]` for `dynamic "ingress"` syntax.

Two-validation pattern: the first asserts non-empty (the security gate); the second asserts each entry parses as a CIDR (catches `203.0.113.42` typed without `/32`). Multiple validation blocks on the same variable are supported since Terraform 1.9 `[CITED: spacelift.io/blog/terraform-variable-validation]`.

### Pattern 2: SSM policy attachment (3 lines)

```hcl
# terraform/main.tf — append after line 85 (aws_iam_instance_profile.devbox)

resource "aws_iam_role_policy_attachment" "devbox_ssm_core" {
  role       = aws_iam_role.devbox.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
```

That's it. The role already exists, the agent is already preinstalled on AL2023, IMDSv2 is already enforced (SSM Agent uses IMDSv2 fine). No additional security group rule needed because SSM is brokered over the **outbound** WebSocket the agent opens to AWS, which the existing `egress { 0.0.0.0/0 }` rule already permits.

Source: `[CITED: docs.aws.amazon.com/aws-managed-policy/latest/reference/AmazonSSMManagedInstanceCore.html]`.

### Pattern 3: Allowlist-me helper (operator workstation script)

```bash
#!/usr/bin/env bash
# scripts/devbox-allowlist-me.sh
set -euo pipefail

# Discover operator's current public IP from AWS-hosted echo service
PUBLIC_IP=$(curl -sS --max-time 5 https://checkip.amazonaws.com | tr -d '[:space:]')

# Sanity-check the response looks like an IPv4 address (defense against captive-portal HTML)
if [[ ! "$PUBLIC_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "ERROR: checkip.amazonaws.com returned unexpected payload: '$PUBLIC_IP'" >&2
  echo "       Are you behind a captive portal? Override manually:" >&2
  echo "       echo 'allowed_web_cidrs = [\"YOUR.IP.HERE/32\"]' > allowlist.auto.tfvars" >&2
  exit 1
fi

# Write to a gitignored auto.tfvars file picked up by Terragrunt
TFVARS_PATH="${TFVARS_PATH:-allowlist.auto.tfvars}"
cat > "$TFVARS_PATH" <<EOF
# AUTO-GENERATED by make devbox-allowlist-me on $(date -u +%Y-%m-%dT%H:%M:%SZ)
# Operator: ${USER}
# Public IP at time of write: ${PUBLIC_IP}
# Refresh by re-running make devbox-allowlist-me after IP changes.
allowed_web_cidrs = ["${PUBLIC_IP}/32"]
EOF

echo "Wrote ${TFVARS_PATH}:"
cat "$TFVARS_PATH"
echo ""
echo "Next: make tg-apply"
```

Source: `[CITED: checkip.amazonaws.com is AWS-hosted, returns plain-text IP, recommended in AWS user guidance]`.

### Pattern 4: Status script post-Phase-2

`scripts/devbox-status.sh` connection-info block (replacing lines 47-53) should print:

```bash
if [[ "$STATE" == "running" ]]; then
  echo ""
  echo "=== Connection Info ==="
  # SSH access is brokered by SSM — no public IP needed for shell.
  echo "Shell (SSM):       aws ssm start-session --target ${INSTANCE_ID} --region ${REGION}"
  echo "                   (or: make devbox-ssm DEVBOX_USER=${DEVBOX_USER})"
  if [[ "$PUBLIC_IP" != "N/A" ]]; then
    echo "code-server:       https://${PUBLIC_IP}:8080   (requires your IP in allowed_web_cidrs)"
    echo "noVNC:             https://${PUBLIC_IP}:6080   (requires your IP in allowed_web_cidrs)"
  fi
  echo ""
  echo "If browser access fails: your public IP probably changed."
  echo "Run 'make devbox-allowlist-me && make tg-apply' to refresh the allowlist."
fi
```

### Pattern 5: `make devbox-ssm` Makefile target

```make
.PHONY: devbox-ssm devbox-allowlist-me

# --- Shell access via SSM Session Manager ---

devbox-ssm:
	@set -euo pipefail; \
	command -v session-manager-plugin >/dev/null 2>&1 || { \
	  echo "ERROR: session-manager-plugin not installed." >&2; \
	  echo "       macOS: brew install --cask session-manager-plugin" >&2; \
	  echo "       Linux: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html" >&2; \
	  exit 1; \
	}; \
	cd terraform && \
	  INSTANCE_ID=$$(DEVBOX_USER=$(DEVBOX_USER) terragrunt output -raw instance_id 2>/dev/null); \
	  REGION=$$(DEVBOX_USER=$(DEVBOX_USER) terragrunt output -raw aws_region 2>/dev/null || echo us-east-1); \
	  test -n "$$INSTANCE_ID" || { echo "ERROR: no instance_id in tfstate for DEVBOX_USER=$(DEVBOX_USER)" >&2; exit 1; }; \
	  exec aws ssm start-session --target "$$INSTANCE_ID" --region "$$REGION"

# --- CIDR allowlist for web ports ---

devbox-allowlist-me:
	@./scripts/devbox-allowlist-me.sh
```

### Anti-Patterns to Avoid

- **Defaulting `allowed_web_cidrs` to the operator's IP automatically inside Terraform.** Don't. Terraform should not call `http_data_source` or `external` provider to fetch the operator's IP during plan — that hides the security-critical value behind opaque magic and surprises team members. The auto-tfvars-write pattern in §3 keeps the value visible in a file the operator can read and version (if they want).
- **Setting `default = ["0.0.0.0/0"]` "for development."** Defeats the whole phase. The default of `[]` + failing validation is the security control.
- **Using `aws_security_group_rule` resources for inline ports.** Adds resource fragmentation without buying anything for a fixed three-port SG. Stick with the inline-`ingress`/dynamic-block pattern in §3. (HashiCorp's newer `aws_vpc_security_group_ingress_rule` resource is preferred for module-style multi-rule cases — `[CITED: registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule]` — but for two ports controlled by one CIDR list, the simpler form is correct.)
- **Removing sshd from the AMI.** The CIS-hardened sshd stays running. SCP and rsync still work via the SSH-over-SSM tunnel (`ProxyCommand` config) for operators who want file transfer. Only the **inbound** SG rule on :22 is removed; the sshd daemon listening on the instance is untouched.
- **Forwarding noVNC and code-server through SSM port forwarding "for security."** Possible but heavy. The hybrid posture deliberately accepts CIDR-allowlisted HTTPS ingress because the operator UX (browser bookmark) is the project's deliberate workflow. SSM port forwarding (`AWS-StartPortForwardingSession`, `[CITED: aws.amazon.com/blogs/aws/new-port-forwarding-using-aws-system-manager-sessions-manager/]`) is documented as an option below for operators who want to close all public ingress, but the default flow uses CIDR.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---|---|---|---|
| Brokered shell access without inbound ports | A custom WebSocket relay or "jump box" EC2 | AWS SSM Session Manager + `AmazonSSMManagedInstanceCore` | Free, AWS-maintained, CloudTrail-audited, no extra hop, no extra IAM permissions beyond one managed policy attachment. `[CITED: aws.amazon.com/blogs/aws/new-port-forwarding-using-aws-system-manager-sessions-manager/]` |
| Operator IP discovery | A Lambda + API Gateway that echoes the caller IP | `curl https://checkip.amazonaws.com` | AWS-hosted, plain-text, free, no auth, no rate limits in practice. |
| Variable validation on empty list | A `null_resource` with a `local-exec` shell check | `validation { condition = length(...) > 0 }` block on the variable | Built into Terraform language; runs before plan, not before apply; clearer error. `[CITED: developer.hashicorp.com/terraform/language/validate]` |
| SSH for file transfer when SG :22 is closed | A custom rsync-over-HTTPS protocol | Standard `scp`/`rsync` over SSH-via-SSM-tunnel using a `ProxyCommand` block in `~/.ssh/config` | AWS-documented pattern; standard SSH tooling works unchanged. `[CITED: docs.aws.amazon.com/systems-manager/.../session-manager-getting-started-enable-ssh-connections.html]` |
| Audit logging of operator shell sessions | A custom auditd shipper | Enable Session Manager session logging to CloudWatch Logs or S3 | Built into SSM; one-checkbox configuration. (Deferred to Phase 4 / future observability work — not blocking for Milestone 1, but the option exists for free if turned on.) |

**Key insight:** Every component this phase needs is already in AWS-managed building blocks. Phase 1 built the half that matters (IAM role + IMDSv2 + per-operator key). Phase 2 is a 5-line Terraform diff + one new shell script + two Makefile targets.

## Runtime State Inventory

> Phase 2 is primarily a configuration change (SG ingress + IAM policy attachment) rather than a rename/refactor. Most runtime-state categories are not applicable, but documenting explicitly per the protocol.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — no databases or datastores reference SSH/security-group state. SSM SecureStrings from Phase 1 unaffected by SG changes. | None. |
| Live service config | **Running EC2 instances** with the old SG attached will need a `terragrunt apply` to pick up the new rules. The apply will modify (or replace) the SG. Existing in-flight SSH sessions stay open (TCP state is preserved by AWS — `[CITED: docs.aws.amazon.com/cli/latest/reference/ec2/revoke-security-group-ingress.html]` and stateful-SG semantics). New SSH connections will fail until the operator runs `aws ssm start-session` or sets up SSH-over-SSM. | One-shot `terragrunt apply` per operator. Document migration step (§ Migration). |
| OS-registered state | None — no Windows Task Scheduler, no systemd unit references SG IDs. `amazon-ssm-agent.service` is already enabled in AL2023 and registers with SSM automatically when the instance profile gains `AmazonSSMManagedInstanceCore`. | Verify after apply: `aws ssm describe-instance-information --filters Key=InstanceIds,Values=$INSTANCE_ID --query 'InstanceInformationList[0].PingStatus'` returns `Online`. |
| Secrets / env vars | None — no env var names change. The Phase 1 SSM SecureString paths (`/devbox/${devbox_user}/code-server-password`, `/vnc-password`) are unaffected. | None. |
| Build artifacts / installed packages | None on the bake side — SSM Agent is already preinstalled in AL2023. On the **operator workstation**, the `session-manager-plugin` must be installed once. | Add `session-manager-plugin` to Phase 4 DOC-01 quickstart / required tools list. The `make devbox-ssm` target detects absence and prints the install command. |

## Common Pitfalls

### Pitfall 1: VPC endpoints aren't needed for a public-subnet devbox — but operators may think they are

**What goes wrong:** Phase 2 docs / blog posts about SSM in private subnets emphasize `com.amazonaws.region.{ssm,ssmmessages,ec2messages}` VPC endpoints. Operators copy that pattern into their tfvars and create three Interface Endpoints they don't need — each costs $0.01/hour ≈ $7/month per endpoint per AZ.

**Why it happens:** AWS docs cover both topologies (public subnet with IGW vs. private subnet without IGW) but most blogs focus on the private case `[CITED: docs.aws.amazon.com/systems-manager/.../setup-create-vpc.html]`.

**How to avoid:** This devbox sits in a subnet with `associate_public_ip_address = true` and the existing `egress { 0.0.0.0/0 }`. The agent reaches `ssmmessages.us-east-1.amazonaws.com` via the IGW. No VPC endpoint needed. Document this explicitly in PROJECT.md / CLAUDE.md.

**Warning signs:** Operator tries to create `aws_vpc_endpoint.ssm` resources, or complains "SSM doesn't work" while having NACLs/SGs that block egress.

### Pitfall 2: Operator's IP changes mid-day; Terraform apply lock prevents quick refresh

**What goes wrong:** Operator is on hotel WiFi at 09:00 (IP X), goes to coffee shop at 13:00 (IP Y). code-server stops loading. They run `make devbox-allowlist-me && make tg-apply`. If a colleague is also `terragrunt apply`-ing in parallel, they hit the DynamoDB lock and wait. Worse — if the operator's network drops mid-apply, the partial state may need `force-unlock`.

**Why it happens:** Each operator has their own tfstate (`users/${devbox_user}/devbox.tfstate`), so cross-operator lock contention is **not actually a concern** for this project — the per-user state isolation makes this self-blocking only.

**How to avoid:** Single-operator lock contention is "you waited 30 seconds." Document that re-applying is the expected response to an IP change. The `make devbox-allowlist-me` helper exists specifically so the refresh is a one-liner.

**Warning signs:** Operator sees `Error: Error acquiring the state lock` — `terragrunt force-unlock <lock-id>` is the recovery, but is rarely needed in practice.

### Pitfall 3: CIS sshd hardening conflicts with SSM (it doesn't)

**What goes wrong:** Phase 2 closes :22 in the SG and operator panics that the CIS-hardened sshd is now unreachable. They consider disabling sshd entirely "to reduce attack surface further."

**Why it happens:** Mental model confuses "no inbound port 22 at the SG layer" with "no sshd on the host." They are independent — SSM sessions land directly into the OS as a `ssm-user` shell (or via SSH-over-SSM that uses the local sshd over an SSM-brokered tunnel).

**How to avoid:** Leave sshd running. CIS rules tightened it (PermitRootLogin no, key-based auth, etc.) `[CITED: complianceascode.github.io/content-pages/guides/ssg-al2023-guide-cis_server_l1.html]`. The local sshd is now reachable **only** over the SSM-brokered tunnel — which is more restrictive than the previous "open to internet with key auth" posture, not less.

**Warning signs:** A plan diff that adds `systemctl disable sshd` to an Ansible task. Reject.

### Pitfall 4: SSM Agent installed but `ec2messages`/`ssmmessages` egress blocked

**What goes wrong:** A subsequent operator tightens the `egress` rule (e.g., to a specific CIDR for cost-control or compliance) and breaks Session Manager silently. Instance shows up as "ConnectionLost" in SSM.

**Why it happens:** Egress to `ssmmessages.${region}.amazonaws.com:443` is required. The current `egress { 0.0.0.0/0 }` covers it; a narrower rule may not.

**How to avoid:** Document that egress must remain open to `:443` AWS service endpoints at minimum. Phase 2 does NOT narrow egress.

**Warning signs:** `aws ssm describe-instance-information` returns empty for an instance the operator believes is "managed." Check with `sudo journalctl -u amazon-ssm-agent -n 50` over EC2 Serial Console (last resort recovery).

### Pitfall 5: Empty list default + variable validation = `tg-init` fails too

**What goes wrong:** Operator clones the repo, runs `make tg-init`, hits the validation error before they've had a chance to read the docs.

**Why it happens:** Terraform runs variable validation on every operation that reads variables, including `init` in some cases (depends on whether Terragrunt triggers `terraform init` with vars context).

**How to avoid:** Make the `error_message` actionable. The validation block's error_message tells the operator exactly which command to run (`make devbox-allowlist-me`). That's the design — failing loudly is the security control.

**Warning signs:** Helpdesk tickets that say "make tg-init is broken." Response: read the error message; run `make devbox-allowlist-me`.

### Pitfall 6: `session-manager-plugin` not installed on operator workstation

**What goes wrong:** `aws ssm start-session` returns `SessionManagerPlugin is not found`. Operator concludes SSM is broken.

**Why it happens:** The plugin is separate from the AWS CLI itself `[CITED: docs.aws.amazon.com/systems-manager/.../session-manager-working-with-install-plugin.html]`.

**How to avoid:** `make devbox-ssm` does `command -v session-manager-plugin` first and prints the `brew install --cask session-manager-plugin` recipe if missing. Phase 4 DOC-01 lists it as a required tool.

**Warning signs:** Empty session output, or `Unable to start session` immediately. Run `session-manager-plugin` standalone — it should print version info.

## Code Examples

### Example 1: Full Terraform diff (Phase 2 deltas)

```hcl
# terraform/variables.tf — APPEND

variable "allowed_web_cidrs" {
  type        = list(string)
  default     = []
  description = "CIDR blocks permitted to reach code-server (:8080) and noVNC (:6080). Empty list refuses apply — populate via `make devbox-allowlist-me` or set explicitly."

  validation {
    condition     = length(var.allowed_web_cidrs) > 0
    error_message = "allowed_web_cidrs must contain at least one CIDR. Run `make devbox-allowlist-me` (auto-resolves your public IP) or set the value explicitly in an allowlist.auto.tfvars file."
  }

  validation {
    condition     = alltrue([for c in var.allowed_web_cidrs : can(cidrhost(c, 0))])
    error_message = "Each entry in allowed_web_cidrs must be a valid CIDR block (e.g. 203.0.113.42/32, 198.51.100.0/24)."
  }
}
```

```hcl
# terraform/main.tf — REPLACE lines 87-136 (the aws_security_group.devbox block)

# --- Security Group ---
# SSH (:22) ingress intentionally absent. Shell access is brokered by AWS SSM
# Session Manager — see PROJECT.md Key Decisions (NET-04) and Phase 2 RESEARCH.md.

resource "aws_security_group" "devbox" {
  name_prefix = "${local.name_prefix}-"
  description = "Security group for devimage instance"
  vpc_id      = var.vpc_id

  ingress {
    description = "code-server (HTTPS) — restricted to operator CIDR list"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = var.allowed_web_cidrs
  }

  ingress {
    description = "noVNC (HTTPS) — restricted to operator CIDR list"
    from_port   = 6080
    to_port     = 6080
    protocol    = "tcp"
    cidr_blocks = var.allowed_web_cidrs
  }

  egress {
    description = "All outbound — required for SSM agent + SSM messages channels"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

# --- SSM Session Manager: attach the AWS-managed core policy to Phase 1's role ---

resource "aws_iam_role_policy_attachment" "devbox_ssm_core" {
  role       = aws_iam_role.devbox.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
```

```hcl
# terraform/outputs.tf — APPEND

output "ssm_start_session_command" {
  value       = "aws ssm start-session --target ${aws_instance.devbox.id} --region ${data.aws_region.current.region}"
  description = "Operator shell access: copy/paste to start a Session Manager shell. Run `make devbox-ssm` for the same effect."
}

output "instance_id" {
  value       = aws_instance.devbox.id
  description = "EC2 instance ID — consumed by scripts/devbox-ssm.sh"
}
```

### Example 2: SSH-over-SSM `~/.ssh/config` block (for operators who want scp/rsync)

```
Host devbox-ssm
  ProxyCommand sh -c "aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters portNumber=%p --region us-east-1"
  HostName i-xxxxxxxxxxxxxxxxx
  User ec2-user
  IdentityFile ~/.ssh/me-devbox
```

Then `scp`, `rsync`, `git push` via agent forwarding all work unchanged:

```bash
scp file.tar.gz devbox-ssm:~/                  # works
rsync -avP src/ devbox-ssm:/home/ec2-user/src/  # works
```

Source: `[CITED: docs.aws.amazon.com/systems-manager/.../session-manager-getting-started-enable-ssh-connections.html]` and `[CITED: aws.amazon.com/about-aws/whats-new/2019/07/session-manager-launches-tunneling-support-for-ssh-and-scp/]`.

Documenting this pattern in CLAUDE.md (Phase 4 DOC-01) is sufficient — no automation needed in Phase 2. The `make devbox-ssm` target gives operators the simple shell; SSH-over-SSM is an advanced path for those who need it.

### Example 3: SSM port forwarding for the web ports (escape hatch, NOT default)

```bash
# Open code-server locally via SSM port forwarding (no SG ingress on :8080 needed)
aws ssm start-session \
  --target i-xxxxxxxxxxxxxxxxx \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8080"],"localPortNumber":["8080"]}' \
  --region us-east-1
# Then browse to https://localhost:8080
```

Source: `[CITED: aws.amazon.com/blogs/aws/new-port-forwarding-using-aws-system-manager-sessions-manager/]`.

This is documented as an escape hatch — if an operator's network blocks them from setting their CIDR (corp VPN with rotating IPs, etc.), they can leave `allowed_web_cidrs` non-empty (e.g., `["127.0.0.1/32"]` to satisfy the validation) and tunnel via SSM port forwarding. Not the recommended daily UX, but available.

## State of the Art

| Old Approach | Current Approach (2026) | When Changed | Impact |
|---|---|---|---|
| Bastion / jump host EC2 with SSH agent forwarding | SSM Session Manager + `AmazonSSMManagedInstanceCore` | 2018 (Session Manager GA) | Removes bastion cost, removes one more box to patch, removes the SSH key sprawl problem. |
| Inline static `ingress` blocks with hardcoded `["0.0.0.0/0"]` | `dynamic "ingress"` over a validated variable, default `[]` | Terraform 0.12 onwards (dynamic blocks); validation in 0.13 | Reviewable, lintable (tfsec catches `0.0.0.0/0`), self-documenting. |
| Lambda + API Gateway "what's my IP" service | `curl https://checkip.amazonaws.com` | AWS has hosted this for years | Free, simpler, no maintenance. |
| Per-operator NACL rules / Network Firewall rules | SG ingress with operator CIDR list | n/a — SG has always been the right layer | Stays simple; reserves Network Firewall for future fleet-level work. |

**Deprecated / outdated:**
- `data.aws_region.current.name` was deprecated under `hashicorp/aws` 6.x — use `data.aws_region.current.region`. (Already migrated in Phase 1 — see `01-02-SUMMARY.md` deviations.) Phase 2 reuses the migrated form.
- `0.0.0.0/0` as a literal in any production-adjacent SG rule is universally treated as a tfsec/checkov HIGH finding. Phase 4 will gate on this; Phase 2 removes the literal so the gate has nothing to flag.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|---|---|---|
| A1 | The current devbox subnet (`subnet-07513680b824b3dbe`) is a public subnet (has an IGW route). SSM Agent's outbound channel to `ssmmessages.${region}.amazonaws.com` will succeed without VPC endpoints. | Pattern 2 / Pitfall 1 | If the subnet is private + no NAT, SSM never registers. Mitigation: verify with `aws ec2 describe-subnets` + `describe-route-tables` before applying. The `terraform/variables.tf` has `associate_public_ip = true` by default which strongly implies the subnet is public-routed. |
| A2 | The operator's AWS principal already has `ssm:StartSession`, `ssm:TerminateSession`, `ssm:DescribeSessions`, and `ssm:DescribeInstanceInformation` IAM permissions (or admin equivalent). | `make devbox-ssm` | The plan should NOT modify operator IAM — operator-side IAM is managed outside this repo. If the operator's IAM is too narrow, document the minimum policy in Phase 4 CLAUDE.md (template: AWS-managed `AmazonSSMReadOnlyAccess` is too narrow for StartSession; the operator needs `AmazonSSMFullAccess` or a custom policy with `ssm:StartSession` on the target instance ARN). |
| A3 | No existing devbox is in a region where SSM Session Manager has been disabled at the account level (org SCP, etc.). | All sections | SCP that denies `ssm:StartSession` would silently break the new posture. Mitigation: operator-tier test in the validation script — `aws ssm describe-instance-information` smoke check after apply. |
| A4 | `var.allowed_web_cidrs` shared between :8080 and :6080 is acceptable. (Alternative: separate vars per port.) | Pattern 1 | Operator wants different audiences for code-server vs. noVNC — unlikely for a personal devbox, but possible. If needed, split into `allowed_code_server_cidrs` and `allowed_vnc_cidrs`. Recommend single shared variable for simplicity until a use case appears. |
| A5 | `make devbox-allowlist-me` writing to `allowlist.auto.tfvars` at the repo root is consumed correctly by Terragrunt. (Terragrunt picks up `*.auto.tfvars` files from the Terraform module dir, not the Terragrunt root by default.) | Pattern 3 / Migration | If Terragrunt doesn't auto-pick it up, the script must instead inject via `TF_VAR_allowed_web_cidrs` env var, or write to `terraform/allowlist.auto.tfvars` (next to other tf files). Mitigation: the planner should verify the target path during plan-write by running `terragrunt apply -auto-approve` against a test value in a smoke test. |
| A6 | The migration impact on an in-flight devbox is "existing TCP connections survive; new connections fail." (AWS SG semantics, but unverified for this specific code-path.) | Migration / Pitfall 2 | Operator's current code-server browser tab might NOT survive — long-lived HTTP(S) connections might be cut. Mitigation: warn in CLAUDE.md that operators should `make tg-apply` between sessions, not mid-session. |

## Open Questions

1. **Should `make devbox-ssm` default to `--document-name AWS-StartInteractiveCommand` for a specific user shell, or accept the default `SSM-SessionManagerRunShell` (which lands as `ssm-user` not `ec2-user`)?**
   - What we know: Default lands as `ssm-user` (the SSM-managed user). Most operator muscle memory expects `ec2-user`.
   - What's unclear: Whether to switch with `sudo -iu ec2-user` automatically.
   - Recommendation: Keep default for first cut; document the `sudo -iu ec2-user` step in CLAUDE.md. SSH-over-SSM (`AWS-StartSSHSession`) lands as `ec2-user` for operators who prefer that.

2. **Variable name: `allowed_web_cidrs` (current proposal), `allowed_admin_cidrs` (from ROADMAP.md "Risks / Notes"), or `operator_cidrs` (more generic)?**
   - What we know: ROADMAP.md uses `allowed_admin_cidr` (singular, list type). The phrase "admin" implies elevated access — which `:8080` / `:6080` don't really represent; they're operator-facing dev tools.
   - What's unclear: Whether to bikeshed.
   - Recommendation: `allowed_web_cidrs`. It describes what the list controls (web ports) without implying privilege levels.

3. **Should Phase 2 also add `session_logging` to S3 / CloudWatch for SSM audit trail?**
   - What we know: Session Manager can log to CloudWatch Logs or S3 with one preference-document setting. Free or near-free.
   - What's unclear: Whether to scope-creep into observability now.
   - Recommendation: Defer to v2 OBS-02 ("SSH and code-server login events shipped to CloudWatch Logs"). Phase 2 stays focused on closing ingress; observability flows naturally from this groundwork in a later milestone.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `aws` CLI (operator workstation) | `make devbox-ssm`, `make devbox-allowlist-me` | Assumed YES (already required by `make build`, `make secrets-show`) | ≥ 1.16.12 needed for plugin support | None — already a hard dependency. |
| `session-manager-plugin` (operator workstation) | `aws ssm start-session` invocations | Likely NO on a fresh workstation; check `command -v` | latest stable | `brew install --cask session-manager-plugin` (macOS) / docs link for Linux. The `make devbox-ssm` recipe detects absence and prints recipe. |
| `amazon-ssm-agent` (on the AMI) | Session Manager channel | YES — preinstalled in AL2023 `[CITED: docs.aws.amazon.com/systems-manager/.../ami-preinstalled-agent.html]` | Whatever AL2023 ships | None needed for Phase 2. Phase 3 may add an explicit `dnf update amazon-ssm-agent` in the bake to pin a known-good version. |
| `curl` (operator workstation) | `make devbox-allowlist-me` | YES on macOS + Linux | any | None needed. Script uses `--max-time 5` to bound failures. |
| `jq` (operator workstation) | `devbox-status.sh` | YES — already a required tool (`scripts/devbox-status.sh:30`) | any | None — pre-existing requirement. |
| HashiCorp AWS provider | `aws_iam_role_policy_attachment`, `dynamic "ingress"`, variable validation | YES — pinned to 6.45.0 in lockfile (Phase 1) | 6.45.0 | None. |
| OpenTofu | `tofu validate` for Phase 2 changes | YES — Phase 1 verified `tofu validate` passes | 1.9+ | None. |

**Missing dependencies with no fallback:** None.

**Missing dependencies with fallback:**
- `session-manager-plugin` is missing by default on most operator workstations; the `make devbox-ssm` target prints the install command. Phase 4 DOC-01 will add it to the required tools list.

## Migration (for an in-flight pre-Phase-2 devbox)

Operator with a running devbox built before Phase 2:

```bash
# 1. Install session-manager-plugin (one-time)
brew install --cask session-manager-plugin   # macOS

# 2. Discover your current public IP and write the tfvars
make devbox-allowlist-me

# 3. Apply: this attaches the SSM managed policy, replaces the SG (create_before_destroy)
make tg-apply DEVBOX_USER=$USER

# 4. Verify SSM registration (may take 30-60s after policy attach)
INSTANCE_ID=$(cd terraform && DEVBOX_USER=$USER terragrunt output -raw instance_id)
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
  --query 'InstanceInformationList[0].PingStatus' --output text
# Expected: Online

# 5. Test shell access
make devbox-ssm DEVBOX_USER=$USER

# 6. Test browser access (code-server / noVNC)
make status DEVBOX_USER=$USER   # prints the URLs

# 7. (Optional) Set up SSH-over-SSM in ~/.ssh/config — see CLAUDE.md / Example 2 above
```

**What breaks during apply:**
- Existing inbound SSH connections to `:22`: AWS preserves stateful connections through SG modifications, so an active SSH session at apply time **typically** survives. New SSH connections to `:22` will be rejected immediately after the SG rules update.
- Existing browser tabs to code-server/noVNC: if the operator's current public IP is in `allowed_web_cidrs`, no impact. If not (the variable is being populated for the first time), the tab loses connection on the next request.
- `terragrunt apply` cost: ~30 seconds; the SG modification is in-place because the SG keeps the same name_prefix and existing rules are diffed.

**Lockout recovery:**
- If operator's IP becomes wrong AND they didn't install `session-manager-plugin`: stop the instance, fix `allowed_web_cidrs`, start. Web access returns. SSM still works once the plugin is installed on any of the operator's workstations.
- If the operator's AWS IAM is missing `ssm:StartSession`: this is recoverable via the AWS Console (which has its own Session Manager browser-based shell at "Connect" → "Session Manager"). Document this fallback in CLAUDE.md.
- Worst case (everything broken): the EBS volume can be detached and mounted on a different instance to recover work. Not a Phase 2 concern; it's the same recovery path as any other EC2 lockout.

## Verification Approach

### Pre-merge (in `tofu plan`)

```bash
# 1. No 0.0.0.0/0 remains in any ingress rule
cd terraform && tofu plan -out=phase2.tfplan
tofu show -json phase2.tfplan | jq -r '
  .resource_changes[]
  | select(.type == "aws_security_group")
  | .change.after.ingress[]?.cidr_blocks[]
' | grep -F '0.0.0.0/0' && { echo "FAIL: open ingress still present"; exit 1; } || echo "PASS: no open ingress"

# 2. Variable validation rejects empty list
echo 'allowed_web_cidrs = []' > /tmp/empty.tfvars
cd terraform && tofu plan -var-file=/tmp/empty.tfvars
# Expected exit code: non-zero, with error message referencing devbox-allowlist-me

# 3. tofu validate clean
cd terraform && tofu validate
# Expected: Success! The configuration is valid.
```

### Post-apply (live AWS calls)

```bash
# 4. SSM Agent registered + Online
INSTANCE_ID=$(cd terraform && DEVBOX_USER=$USER terragrunt output -raw instance_id)
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
  --query 'InstanceInformationList[0].PingStatus' --output text
# Expected: Online

# 5. Start session smoke test
echo "exit" | aws ssm start-session --target "$INSTANCE_ID" --region us-east-1
# Expected: session opens, runs exit, terminates cleanly

# 6. Port forwarding smoke test (optional)
aws ssm start-session \
  --target "$INSTANCE_ID" \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8080"],"localPortNumber":["18080"]}' \
  --region us-east-1 &
SSM_PID=$!
sleep 3
curl -k -s -o /dev/null -w "%{http_code}\n" https://localhost:18080
# Expected: 200 (or 401 for the login page) — confirms the tunnel reached code-server
kill $SSM_PID

# 7. SG no longer permits :22 from internet
SG_ID=$(cd terraform && DEVBOX_USER=$USER terragrunt output -raw security_group_id)
aws ec2 describe-security-groups --group-ids "$SG_ID" \
  --query 'SecurityGroups[0].IpPermissions[?FromPort==`22`]' \
  --output text
# Expected: empty output (no ingress rule for :22)

# 8. SG :8080 / :6080 restricted to operator CIDR
aws ec2 describe-security-groups --group-ids "$SG_ID" \
  --query 'SecurityGroups[0].IpPermissions[].{Port:FromPort,CIDRs:IpRanges[].CidrIp}' \
  --output table
# Expected: 8080 and 6080 rows; CIDRs column contains operator IP/32, not 0.0.0.0/0
```

### CI-friendly (Phase 4 hook-in)

Phase 2 leaves the door open for Phase 4 tfsec/checkov gating:
- `tfsec` rule `aws-vpc-no-public-ingress-sgr` / `AVD-AWS-0107`: no `0.0.0.0/0` in SG ingress → will pass after Phase 2.
- `checkov` rule `CKV_AWS_24`: ensure no SSH from `0.0.0.0/0` → will pass after Phase 2 (rule is moot: no SSH ingress at all).
- `checkov` rule `CKV_AWS_260`: ensure no HTTP from `0.0.0.0/0` → passes if `allowed_web_cidrs` excludes `0.0.0.0/0`.

## Project Constraints (from CLAUDE.md)

`/Users/me/Documents/code/devbox/CLAUDE.md` exists but is empty (Phase 4 DOC-01 will populate it). No project-level directives present yet.

User's global rules (`~/.claude/rules/`) apply transitively:
- `coding-style.md` — immutability, KISS, DRY, YAGNI; many small files; explicit error handling.
- `security.md` — no hardcoded secrets (none introduced this phase); validate all inputs (CIDR validation block satisfies this); rate limiting / auth (out of scope for infra phase).
- `git-workflow.md` — conventional commits, `feat(phase-02-XX): ...` pattern matching Phase 1's commit style.
- `testing.md` — Phase 2 modifies infra; testing model is `tofu plan` / `tofu validate` / smoke test against AWS, not unit tests. The Nyquist validation section is omitted below because `workflow.nyquist_validation` is `false` in `.planning/config.json`.

## Security Domain

`security_enforcement` is not explicitly set in `.planning/config.json` (absent → enabled).

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---|---|---|
| V1 Architecture | yes | Defense in depth: SSM removes one attack surface (SSH brute force) entirely; CIDR allowlist narrows two others; IMDSv2 / instance profile / SSM Agent already in place from Phase 1. |
| V2 Authentication | yes | IAM role + Session Manager replaces SSH-password-or-key auth for the shell path. code-server / noVNC still use generated passwords (Phase 1) plus CIDR allowlist (Phase 2). |
| V3 Session Management | partial | Session Manager sessions are bounded by `ssm:StartSession` IAM and auto-terminate per `MaxSessionDuration` (default 20 min idle, configurable via preference document). Web sessions still managed by code-server / noVNC themselves. |
| V4 Access Control | yes | `allowed_web_cidrs` enforces network-layer authZ. `AmazonSSMManagedInstanceCore` is the instance-side policy; operator-side `ssm:StartSession` is what gates shell access. |
| V5 Input Validation | yes | Terraform `validation { ... }` blocks on `var.allowed_web_cidrs`: non-empty + valid CIDR shape. Bash script validates `checkip.amazonaws.com` response shape (defends against captive-portal HTML payload). |
| V6 Cryptography | n/a (no new crypto introduced; existing TLS on noVNC + code-server preserved) | n/a |
| V12 Files / Resources | partial | tfvars file `allowlist.auto.tfvars` must be in `.gitignore` to prevent operator IP / org IP range from leaking into git history. |

### Known Threat Patterns for AWS-SG + SSM stack

| Pattern | STRIDE | Standard Mitigation |
|---|---|---|
| SSH brute-force against `:22` exposed to internet | Spoofing / Elevation | Eliminated — no `:22` ingress. SSM replaces the path entirely. |
| Credential-stuffing against code-server `/` | Spoofing | Per-build random password (Phase 1) + CIDR-restricted ingress (Phase 2). Rate-limiting at app layer not in scope. |
| Operator's tfvars file with org public-IP range committed to git | Information Disclosure | `.gitignore` entry for `allowlist.auto.tfvars` and `*.auto.tfvars`. Gitleaks pattern doesn't cover IP ranges; rely on the gitignore. |
| Operator's IAM principal compromised → attacker StartsSession | Elevation | Out of scope for Phase 2 (operator IAM is per-workstation). Phase 4 CLAUDE.md to recommend MFA-required role assumption for the operator's AWS profile. |
| Lateral movement: instance profile lets the box `StartSession` against other boxes | Elevation | NOT possible — `AmazonSSMManagedInstanceCore` does NOT grant `ssm:StartSession`; it only grants what the **agent** needs (`ssmmessages:*` channel messages, `ssm:UpdateInstanceInformation`, etc.). Verified by reading the policy doc. `[CITED: docs.aws.amazon.com/aws-managed-policy/.../AmazonSSMManagedInstanceCore.html]` |
| VPC endpoint exposure | Information Disclosure | None — we do NOT add VPC endpoints. The current public-subnet topology covers it via IGW + SG egress. |
| Session Manager session not logged | Repudiation | Default Session Manager sessions ARE recorded in CloudTrail (start/stop events with caller identity). Full session-stream logging to S3 / CloudWatch deferred to v2 (OBS-02). |

## Sources

### Primary (HIGH confidence)

- `[CITED]` AWS Managed Policy: AmazonSSMManagedInstanceCore — https://docs.aws.amazon.com/aws-managed-policy/latest/reference/AmazonSSMManagedInstanceCore.html — confirms ARN `arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore` and scope (agent-side permissions only, not `ssm:StartSession`).
- `[CITED]` SSM Agent preinstalled in AL2023 — https://docs.aws.amazon.com/systems-manager/latest/userguide/ami-preinstalled-agent.html — confirms AL2023 AMIs ship `amazon-ssm-agent`.
- `[CITED]` AWS Systems Manager Pricing — https://aws.amazon.com/systems-manager/pricing/ — confirms Session Manager is free for EC2 instances.
- `[CITED]` Install Session Manager plugin — https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html — confirms plugin is separate from AWS CLI and `brew install --cask session-manager-plugin` works on macOS.
- `[CITED]` SSM port forwarding (AWS-StartPortForwardingSession) — https://aws.amazon.com/blogs/aws/new-port-forwarding-using-aws-system-manager-sessions-manager/ — confirms tunnel-arbitrary-port pattern.
- `[CITED]` Enable SSH over Session Manager — https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-getting-started-enable-ssh-connections.html — confirms scp/rsync/SSH-tooling continues to work via SSM-brokered tunnel using `ProxyCommand`.
- `[CITED]` Terraform variable validation — https://developer.hashicorp.com/terraform/language/validate — confirms `validation { condition / error_message }` runs before plan, multiple validation blocks supported in 1.9+.
- `[CITED]` AWS revoke-security-group-ingress — https://docs.aws.amazon.com/cli/latest/reference/ec2/revoke-security-group-ingress.html — confirms rule changes propagate quickly but stateful connections persist briefly.
- `[CITED]` AL2023 SSH default config — https://docs.aws.amazon.com/linux/al2023/ug/ssh-host-key.html — confirms `UseDNS=no` and default sshd settings; sshd stays running for SSM-over-SSH tunnel use.
- `[CITED]` CIS Amazon Linux 2023 guide (sshd hardening) — https://complianceascode.github.io/content-pages/guides/ssg-al2023-guide-cis_server_l1.html — confirms CIS sshd settings (PermitRootLogin no, key auth) are independent of SG ingress; no conflict with closing :22 at the SG layer.

### Secondary (MEDIUM confidence — cross-verified)

- `[VERIFIED]` checkip.amazonaws.com returns plain-text public IP — verified via search; widely-used pattern in AWS user guidance.
- `[VERIFIED]` `aws_vpc_security_group_ingress_rule` (newer resource type) — https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule — noted as alternative pattern; classic inline `ingress` is sufficient for this phase.
- `[VERIFIED]` `mludvig/aws-ssm-tools` — https://github.com/mludvig/aws-ssm-tools — convenience helpers; documented but not required.
- `[VERIFIED]` Session Manager port forwarding to remote host (`AWS-StartPortForwardingSessionToRemoteHost`) — exists but not used by this phase (current topology has the services on the same instance, not a remote DB).

### Tertiary (LOW confidence — informational)

- Cloud Glance, Tripwire, Medium blog posts on SSM workflows — referenced for cross-validation of SCP/rsync-via-SSM patterns; primary AWS docs above are authoritative.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — Every recommended component is AWS-official + already half-installed by Phase 1.
- Architecture: HIGH — Pattern is the AWS-documented Session Manager + restricted-SG combo, applied to a topology the project already runs.
- Pitfalls: HIGH — Pitfalls listed are common-in-the-wild and verifiable via AWS docs.
- Operator UX (`make devbox-ssm`, `make devbox-allowlist-me`, `scripts/devbox-status.sh`): MEDIUM — design is sound, but the exact Terragrunt output wiring (instance_id, security_group_id, aws_region outputs) needs the planner to confirm during plan-write.

**Research date:** 2026-05-13
**Valid until:** 2026-06-12 (30 days — AWS Session Manager and SG resources are stable; managed policy ARNs do not change)
