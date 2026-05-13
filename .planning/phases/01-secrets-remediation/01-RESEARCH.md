# Phase 1: Secrets remediation - Research

**Researched:** 2026-05-13
**Domain:** AWS IaC secrets (Ansible password generation, SSM Parameter Store, IAM instance profile, gitleaks)
**Confidence:** HIGH (most sections cite official docs); MEDIUM on code-server `auth: none` posture and the gitleaks-vs-detect-secrets recommendation.

## Summary

Phase 1 closes 2 of 3 CRITICAL findings in `.planning/codebase/CONCERNS.md` by replacing the literal `changeme` passwords for code-server (`ansible/roles/vscode/templates/config.yaml.j2:3`) and VNC (`ansible/roles/desktop/defaults/main.yml:7`) with per-build random secrets, delivering them via AWS SSM Parameter Store under per-user paths, and gating the repo with `gitleaks` before any new secret can land.

The idiomatic Ansible pattern is `lookup('ansible.builtin.password', '/dev/null length=32')` evaluated **once per build** and stored in a fact (`set_fact` with `cacheable: false, no_log: true`), then (a) rendered into `config.yaml.j2` via a `{{ code_server_password }}` variable and (b) piped to `vncpasswd -f` via shell, with the cleartext written to SSM via `community.aws.ssm_parameter` (or a `command: aws ssm put-parameter`) under `/devbox/${devbox_user}/code-server-password` and `/devbox/${devbox_user}/vnc-password` as `SecureString`. The running EC2 fetches them at boot via a systemd-oneshot baked into the AMI, using the EC2 instance profile credentials — secrets never appear in user_data.

**Primary recommendation:** SSM Parameter Store (SecureString, standard tier) over Secrets Manager — `$0` vs `$0.40/secret/month`, identical KMS encryption, sufficient IAM granularity for this use case. No rotation automation needed in v1.

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SEC-01 | code-server password generated per-build, no `changeme`, no committed value | §1 (Ansible password lookup), §2 (code-server config), §10 (verification) |
| SEC-02 | VNC password generated per-build, no `changeme`, no committed value | §1 (Ansible password lookup), §3 (VNC rotation), §10 (verification) |
| SEC-03 | Secrets stored in Secrets Manager or SSM Parameter Store, fetched via EC2 instance profile | §4 (SSM vs Secrets Manager), §5 (IAM instance profile), §6 (boot-time fetch) |
| SEC-04 | Per-operator SSH keypair, documented rotation | §7 (per-operator SSH key) |
| SEC-05 | gitleaks (or equivalent) gates in pre-commit and CI; build fails on any detected secret | §8 (gitleaks), §10 (verification) |

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Per-build random password generation | Image-bake (Ansible) | — | Secrets are generated *once per AMI*, not per launch; the bake host is the only place that holds the cleartext. |
| Secret persistence for operator retrieval | Cloud (AWS SSM Parameter Store) | — | Per-user keyed values must be queryable by the operator's IAM identity after the bake completes. |
| Boot-time secret delivery to services | Deployment runtime (systemd oneshot + AWS CLI) | EC2 instance profile (IAM) | Service configs (`~/.config/code-server/config.yaml`, `~/.vnc/passwd`) are *written at first boot* from SSM, not at bake time. |
| IAM policy + instance profile | Infra-provision (Terraform) | — | Role + policy + profile + attachment are declarative resources scoped per-user. |
| SSH key authorization | Infra-provision (Terraform) | Operator workstation (keypair creation) | `aws_key_pair` is registered out-of-band per operator; Terragrunt only references the name. |
| Secret-leak gate | Operator surface (pre-commit) | CI (GitHub Actions) | Catch leaks before commit, double-check on push; the runtime tier is irrelevant. |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `ansible.builtin.password` lookup | bundled (ansible-core >= 2.10) | Generate + cache random passwords in a file | Idempotent across re-runs because the file is the cache; this is the documented Ansible primitive. [VERIFIED: docs.ansible.com/ansible/latest/collections/ansible/builtin/password_lookup.html] |
| `community.aws.ssm_parameter` | community.aws collection (latest stable line: ~9.x) | Write SecureString parameters from Ansible | Official Ansible collection mirroring `aws ssm put-parameter`. [CITED: docs.ansible.com community.aws] |
| `aws_iam_role` + `aws_iam_role_policy` + `aws_iam_instance_profile` | provider hashicorp/aws >= 5.0 (current at `terraform/main.tf:7`) | Define + attach EC2 instance profile | Native Terraform resources, no external module needed. [VERIFIED: registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile] |
| gitleaks | v8.30.1 (released 2026-03-21) | Secret scanner for pre-commit + CI | Fastest regex-based scanner, MIT-licensed, widely-adopted pre-commit story. [VERIFIED: github.com/gitleaks/gitleaks/releases via WebSearch 2026-05-13] |
| AWS CLI v2 | 2.x (already on AMI via `ansible/roles/base/tasks/main.yml:24-28`) | Fetch SecureString at boot | `aws ssm get-parameter --with-decryption` is the idiomatic call; AWS CLI v2 reads instance profile credentials transparently. [CITED: docs.aws.amazon.com/cli/latest/reference/ssm/get-parameter.html] |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `community.general.random_string` | community.general (already in `ansible/requirements.yml:3`) | Alternative password generator with character-class constraints | If you need to *guarantee* class composition (1 upper, 1 digit, etc.); otherwise `password` lookup is simpler. [CITED: docs.ansible.com community.general.random_string_lookup] |
| `pre-commit` framework | 3.x | Run gitleaks on staged files locally | Standard pre-commit story; already referenced by vendored CIS role's own dev pipeline (`ansible/roles/AMAZON2023-CIS/.pre-commit-config.yaml`). |
| `gitleaks/gitleaks-action` | v2 (SHA-pinned in CI) | Run gitleaks in GitHub Actions | Official action published by gitleaks maintainers. [CITED: github.com/gitleaks/gitleaks-action] |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| SSM Parameter Store SecureString | AWS Secrets Manager | Secrets Manager: $0.40/secret/month + rotation/replication features we don't need; SSM standard tier is free. [VERIFIED: aws.amazon.com pricing pages via WebSearch 2026-05-13] |
| `lookup('password', '/dev/null …')` | `lookup('community.general.random_string', …)` | `password` lookup is idempotent via file cache; `random_string` is *not* idempotent across runs unless you `set_fact` it and persist. [VERIFIED: docs.ansible.com] |
| gitleaks | trufflehog | trufflehog is heavier (live credential verification, S3/Docker scans); over-spec for a personal IaC repo with no commits to scan against. Run trufflehog quarterly on history if desired. [CITED: appsecsanta.com, jit.io comparisons 2026] |
| gitleaks | detect-secrets | detect-secrets has fallen out of favor in 2026 comparisons; gitleaks has better regex coverage and faster scans. [ASSUMED — based on community trend reporting] |
| user_data inline secret fetch | systemd oneshot baked into AMI | user_data is readable via IMDS and persists in instance metadata; oneshot ExecStart runs only on the EC2 with no metadata exposure. [VERIFIED: AWS user-data docs, cluster-api-aws userdata privacy doc] |

**Installation (operator workstation):**
```bash
brew install gitleaks pre-commit          # macOS
# or: dnf/apt install gitleaks; pip install pre-commit
ansible-galaxy collection install community.aws  # if not already present
```

**Version verification (run before locking the plan):**
```bash
# Confirm gitleaks latest stable
curl -s https://api.github.com/repos/gitleaks/gitleaks/releases/latest | jq -r .tag_name
# Confirm community.aws latest
ansible-galaxy collection list community.aws
# Confirm AWS provider version
tofu providers
```

## Architecture Patterns

### System Architecture Diagram

```text
                  ┌────────────────────────────────────────────┐
                  │             Operator workstation           │
                  │  pre-commit (gitleaks)  ──► CI (gitleaks)   │
                  └──────────────────────┬─────────────────────┘
                                         │ git push
                                         ▼
              ┌──────────────────────────────────────────────────┐
              │            Image-bake (Packer + Ansible)         │
              │                                                  │
              │  1. set_fact code_server_password =              │
              │      lookup('password','/dev/null length=32')    │
              │     set_fact vnc_password = (same)               │
              │     (no_log: true on both)                       │
              │                                                  │
              │  2. Template config.yaml.j2 ─► /etc/...          │
              │     vncpasswd -f stdin       ─► ~/.vnc/passwd    │
              │                                                  │
              │  3. community.aws.ssm_parameter:                 │
              │     /devbox/${devbox_user}/code-server-password  │
              │     /devbox/${devbox_user}/vnc-password          │
              │     type=SecureString (default KMS key)          │
              │                                                  │
              │  4. Install systemd-oneshot devbox-secrets       │
              │     into the AMI (do NOT run it here)            │
              └──────────────────────┬───────────────────────────┘
                                     │ AMI snapshot
                                     ▼
              ┌──────────────────────────────────────────────────┐
              │       Infra-provision (Terragrunt + Terraform)    │
              │                                                  │
              │   aws_iam_role.devbox             (trust: ec2)   │
              │   aws_iam_role_policy.ssm_read    (least-priv)   │
              │     Effect:Allow ssm:GetParameter*               │
              │      Resource: arn:aws:ssm:*:*:parameter         │
              │                /devbox/${devbox_user}/*          │
              │     Effect:Allow kms:Decrypt                     │
              │      Resource: <default aws/ssm key alias>       │
              │   aws_iam_instance_profile.devbox                │
              │   aws_instance.devbox                            │
              │     iam_instance_profile = ...                   │
              │     key_name             = "${devbox_user}-devbox" │
              └──────────────────────┬───────────────────────────┘
                                     │ EC2 first boot
                                     ▼
              ┌──────────────────────────────────────────────────┐
              │            Running devbox EC2                    │
              │                                                  │
              │  systemd oneshot: devbox-secrets-bootstrap       │
              │   - aws ssm get-parameter --with-decryption ...  │
              │   - rewrite ~/.config/code-server/config.yaml    │
              │   - echo "$VNC" | vncpasswd -f > ~/.vnc/passwd   │
              │   - restart code-server, vncserver               │
              └──────────────────────────────────────────────────┘
```

### Pattern 1: Per-build password generation in Ansible

**What:** Generate two random secrets *once* at bake time using the `password` lookup, persist them as facts, render into templates, ship to SSM, and discard.

**Why this pattern (not module-level lookup-per-task):**
- `lookup('password', '/dev/null length=32')` with `/dev/null` as the path generates a *new* password every evaluation. Evaluating it inside `set_fact` once binds it for the play.
- Using a real path (e.g. `/tmp/code-server.passwd`) caches to disk — convenient but leaves a cleartext on the builder disk that survives in the AMI unless explicitly wiped. **Use `/dev/null` + `set_fact`.**
- `community.general.random_string` regenerates every evaluation by design; only use it if class composition matters. [CITED: docs.ansible.com community.general.random_string_lookup]

**Example (proposed `ansible/roles/secrets/tasks/main.yml`, new role added before `vscode` and `desktop` in `ansible/playbook.yml`):**
```yaml
---
- name: Generate code-server password (per-build, in-memory only)
  ansible.builtin.set_fact:
    code_server_password: "{{ lookup('ansible.builtin.password',
                                    '/dev/null length=32 chars=ascii_letters,digits') }}"
  no_log: true

- name: Generate VNC password (per-build, in-memory only)
  ansible.builtin.set_fact:
    # VNC truncates to 8 chars internally — generating 8 here is a feature, not a bug.
    desktop_vnc_password: "{{ lookup('ansible.builtin.password',
                                     '/dev/null length=8 chars=ascii_letters,digits') }}"
  no_log: true

- name: Publish code-server password to SSM Parameter Store
  community.aws.ssm_parameter:
    name: "/devbox/{{ devbox_user }}/code-server-password"
    description: "code-server password for {{ devbox_user }} devbox (build {{ ansible_date_time.iso8601 }})"
    string_type: SecureString
    value: "{{ code_server_password }}"
    overwrite_value: always
    region: "{{ aws_region }}"
  no_log: true

- name: Publish VNC password to SSM Parameter Store
  community.aws.ssm_parameter:
    name: "/devbox/{{ devbox_user }}/vnc-password"
    description: "VNC password for {{ devbox_user }} devbox (build {{ ansible_date_time.iso8601 }})"
    string_type: SecureString
    value: "{{ desktop_vnc_password }}"
    overwrite_value: always
    region: "{{ aws_region }}"
  no_log: true
```

**Notes:**
- `no_log: true` on every task touching secret values. **This is mandatory** — Packer streams Ansible stdout to its own log, which Packer may forward to a log host. [CITED: docs.ansible.com logging.html, ansible-lint `no-log-password` rule]
- `devbox_user` must flow into Ansible from Packer extra-vars; today only `layer_config.yml` is passed (`packer/devimage.pkr.hcl:64`). Plan must add `-var devbox_user=...` or wire via packer variables → ansible extra-vars.
- Use `overwrite_value: always` so subsequent builds rotate the secret in-place under the same parameter name. [VERIFIED: community.aws.ssm_parameter docs]

### Pattern 2: code-server password handling on AL2023

**Current state (verified):** `ansible/roles/vscode/templates/config.yaml.j2:1-4`:
```yaml
bind-addr: {{ code_server_bind_addr }}
auth: password
password: changeme
cert: true
```

**Recommendation: keep `auth: password` with the per-build random value, and (optional, defer to Phase 2) consider `auth: none` only behind SSH tunneling.**

Rationale:
- `auth: password` rate-limits to 2 attempts/minute + 12/hour. [CITED: coder.com/docs/code-server/guide]
- `auth: none` *requires* an authenticated reverse proxy or SSH tunnel — code-server docs are explicit: "Never expose code-server directly to the internet without some form of authentication and encryption." [CITED: coder.com/docs/code-server/guide]
- Phase 2 will narrow the SG to an operator CIDR, but until then `auth: password` is the only layer holding the line.

**Template change (proposed):**
```yaml
bind-addr: {{ code_server_bind_addr }}
auth: password
password: "{{ code_server_password }}"   # rendered at AMI bake; rotated at first-boot by oneshot
cert: true
```

**Note on hashed-password:** code-server *does* support `hashed-password: <argon2>` as an alternative, generated via `echo -n "yourpassword" | npx argon2-cli -e`. [CITED: github.com/coder/code-server discussions #7378, #4382] **Not recommended for v1** — adds a build dependency (`npx` / argon2-cli) on the bake host for a security gain that the runtime SSM fetch already provides (cleartext only ever lives in memory on the bake host and in encrypted SSM storage).

### Pattern 3: VNC password rotation on AL2023

**Current state (verified):** `ansible/roles/desktop/tasks/main.yml:29-33`:
```yaml
- name: Set VNC password
  shell: |
    echo "{{ desktop_vnc_password }}" | vncpasswd -f > {{ dev_home }}/.vnc/passwd
  args:
    creates: "{{ dev_home }}/.vnc/passwd"   # BROKEN: rotation never fires
```

**Problems:**
1. `creates: ~/.vnc/passwd` short-circuits the task once the file exists — so a rebuild with a new `desktop_vnc_password` does *not* rotate. [CONFIRMED: CONCERNS.md "creates: guard on VNC password is order-dependent (HIGH)"]
2. The task leaks the password to stdout/stderr if Ansible verbosity is high. No `no_log: true`.

**Fix (proposed):**
```yaml
- name: Set VNC password (always rotates per build)
  ansible.builtin.shell:
    # vncpasswd -f reads cleartext from stdin and writes the obfuscated form to stdout.
    # Pipe stdin via the `stdin` arg rather than a shell heredoc so the cleartext
    # never appears in `ps` or process tree.
    cmd: "vncpasswd -f > {{ dev_home }}/.vnc/passwd"
    stdin: "{{ desktop_vnc_password }}"
  changed_when: true   # rotation is the intent; declare the change explicitly
  no_log: true

- name: Fix VNC password file permissions
  ansible.builtin.file:
    path: "{{ dev_home }}/.vnc/passwd"
    owner: "{{ dev_user }}"
    group: "{{ dev_user }}"
    mode: "0600"
```

[CITED: tigervnc.org/doc/vncpasswd.html — `-f` reads from stdin, writes obfuscated bytes to stdout.]

**Operator-override pathway (optional, for break-glass):**
- Allow `desktop_vnc_password` to be set via Packer `--extra-vars` or env var; the `set_fact` task in §1 should only fire if `desktop_vnc_password is not defined`. This preserves the "per-build random by default, operator-override if specified" contract.

### Pattern 4: SSM Parameter Store vs Secrets Manager (DECISION)

**Recommendation: SSM Parameter Store, SecureString type, standard tier.**

| Dimension | SSM Parameter Store (SecureString, standard) | AWS Secrets Manager |
|-----------|----------------------------------------------|--------------------|
| Cost per secret | $0.00 (standard, up to 10k params free) | $0.40/secret/month |
| Cost per ~5 devbox secrets/month | $0.00 | ~$2.00/month/operator |
| API call cost | $0.05 per 10,000 standard interactions | $0.05 per 10,000 API calls |
| Encryption | AWS-managed KMS (default key `alias/aws/ssm`) or CMK | AWS-managed KMS or CMK |
| IAM granularity | `ssm:GetParameter[s]` + resource ARN paths (supports path prefix `/devbox/${user}/*`) | `secretsmanager:GetSecretValue` + ARN |
| Automatic rotation | None (manual) | Built-in, schedule + Lambda |
| Versioning | Yes (up to 100 per parameter) | Yes |
| Audit | CloudTrail | CloudTrail + per-resource policy |
| CLI ergonomics | `aws ssm get-parameter --name X --with-decryption` | `aws secretsmanager get-secret-value --secret-id X` |

[VERIFIED: aws.amazon.com/blogs/security/how-to-choose-the-right-aws-service-for-managing-secrets-and-configurations, viprasol.com/blog/aws-parameter-store 2026 via WebSearch 2026-05-13]

**For this project:**
- 2-3 secrets per devbox per operator. Even at 10 operators, Secrets Manager would cost ~$8-12/month for zero functional benefit.
- No rotation requirement (rotation happens at AMI rebuild — built-in).
- IAM scoping via path prefix `/devbox/${devbox_user}/*` is straightforward.
- Decision goes in `PROJECT.md → Key Decisions`, replacing the "Pending" row with "SSM Parameter Store SecureString".

### Pattern 5: EC2 instance profile in Terraform (least privilege)

**Proposed addition to `terraform/main.tf`** (between current line 26 and the SG at line 30):

```hcl
# --- IAM: EC2 instance profile for SSM Parameter Store read ---

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_iam_role" "devbox" {
  name_prefix = "${local.name_prefix}-"
  description = "EC2 role granting ${var.devbox_user}'s devbox read access to its own SSM secrets"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "devbox_ssm_read" {
  name = "${local.name_prefix}-ssm-read"
  role = aws_iam_role.devbox.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadOwnSecrets"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/devbox/${var.devbox_user}/*"
      },
      {
        Sid    = "DecryptSecureStrings"
        Effect = "Allow"
        Action = ["kms:Decrypt"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "ssm.${data.aws_region.current.name}.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_instance_profile" "devbox" {
  name_prefix = "${local.name_prefix}-"
  role        = aws_iam_role.devbox.name
  tags        = local.common_tags
}
```

**Wire into `aws_instance.devbox` (replace current line 87):**
```hcl
iam_instance_profile = aws_iam_instance_profile.devbox.name
```

**Then drop `var.iam_instance_profile` from `terraform/variables.tf:51-55`** — it is now managed inline, no longer a per-deploy input.

**Terragrunt input change in `terragrunt.hcl:27-37`:**
- Remove `iam_instance_profile` if present (it currently is not — `terragrunt.hcl:27-37` doesn't set it).
- No change needed; the new resources are wired internally.

[CITED: registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role, …/iam_instance_profile, …/iam_role_policy; docs.aws.amazon.com/systems-manager/latest/userguide/setup-instance-permissions.html]

**Why the `kms:Decrypt` condition matters:** SecureString decryption goes through KMS *via* SSM. Without the `kms:ViaService` condition, the policy would grant blanket `kms:Decrypt` against `*` — too broad. The condition pins the decrypt to only requests that come from SSM. [CITED: docs.aws.amazon.com/systems-manager/latest/userguide/secure-string-parameter-kms-encryption.html]

### Pattern 6: Boot-time secret retrieval (systemd oneshot baked into AMI)

**Decision: systemd oneshot service installed by Ansible, NOT user_data, NOT cloud-init runcmd.**

**Why:**
- user_data is **readable from inside the instance** (`curl http://169.254.169.254/latest/user-data`) and is **persistent metadata** until the instance is terminated. Any secret in user_data is a long-lived leak. [VERIFIED: cluster-api-aws.sigs.k8s.io/topics/userdata-privacy, wafatech.sa/blog/linux best practices for cloud-init]
- cloud-init `runcmd` runs once at first boot but the script body is in user_data → same problem.
- A systemd-oneshot that calls `aws ssm get-parameter` at boot **never embeds the secret anywhere** — the secret travels memory-only from IMDSv2-protected STS → AWS CLI → environment of a child process.

**Proposed `ansible/roles/secrets/templates/devbox-secrets-bootstrap.service.j2`:**
```ini
[Unit]
Description=Fetch devbox secrets from SSM and apply to code-server / VNC
Wants=network-online.target
After=network-online.target cloud-final.service
Before=code-server.service vncserver.service novnc.service
ConditionPathExists=!/var/lib/devbox/secrets-applied

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/devbox-secrets-bootstrap.sh
# Refuse to start any dependent service if the bootstrap failed.
SuccessExitStatus=0

[Install]
WantedBy=multi-user.target
```

**Proposed `ansible/roles/secrets/templates/devbox-secrets-bootstrap.sh.j2`:**
```bash
#!/usr/bin/env bash
set -euo pipefail

# Read identity from instance tags (DevboxUser tag is set at TF apply time).
TOKEN=$(curl -s -X PUT 'http://169.254.169.254/latest/api/token' \
    -H 'X-aws-ec2-metadata-token-ttl-seconds: 60')
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/placement/region)

# Resolve user from tag (single API call, instance-profile-authorized).
DEVBOX_USER=$(aws ec2 describe-tags --region "$REGION" \
    --filters "Name=resource-id,Values=$INSTANCE_ID" "Name=key,Values=DevboxUser" \
    --query 'Tags[0].Value' --output text)

if [[ -z "$DEVBOX_USER" || "$DEVBOX_USER" == "None" ]]; then
    echo "DevboxUser tag missing; refusing to bootstrap" >&2
    exit 1
fi

# Fetch secrets.
CS_PWD=$(aws ssm get-parameter --region "$REGION" \
    --name "/devbox/$DEVBOX_USER/code-server-password" \
    --with-decryption --query 'Parameter.Value' --output text)
VNC_PWD=$(aws ssm get-parameter --region "$REGION" \
    --name "/devbox/$DEVBOX_USER/vnc-password" \
    --with-decryption --query 'Parameter.Value' --output text)

# Apply.
install -o ec2-user -g ec2-user -m 0600 /dev/null /home/ec2-user/.config/code-server/config.yaml
cat > /home/ec2-user/.config/code-server/config.yaml <<EOF
bind-addr: 0.0.0.0:8080
auth: password
password: ${CS_PWD}
cert: true
EOF
chown ec2-user:ec2-user /home/ec2-user/.config/code-server/config.yaml

echo "${VNC_PWD}" | sudo -u ec2-user vncpasswd -f > /home/ec2-user/.vnc/passwd
chown ec2-user:ec2-user /home/ec2-user/.vnc/passwd
chmod 0600 /home/ec2-user/.vnc/passwd

# Mark complete so the service does not re-run (ConditionPathExists guard).
mkdir -p /var/lib/devbox
touch /var/lib/devbox/secrets-applied

# Restart dependent services to pick up the new config.
systemctl restart code-server.service vncserver.service novnc.service
```

**Notes:**
- Uses IMDSv2 (`X-aws-ec2-metadata-token`). Phase 2 should enforce IMDSv2-only on the instance via `metadata_options` in `aws_instance.devbox`.
- `--with-decryption` is the SecureString fetch flag. [CITED: docs.aws.amazon.com/cli/latest/reference/ssm/get-parameter.html]
- `ConditionPathExists=!/var/lib/devbox/secrets-applied` makes this a one-shot per instance — re-applying the AMI to a *new* instance reruns; rebooting an existing one does not.
- The bootstrap script becomes part of the AMI; the running EC2 reads secrets from SSM at first boot.

**Alternative pattern considered:** Pass `DEVBOX_USER` via the EC2 `Name` tag prefix (`${user}-devbox`) and parse it. Rejected — the `DevboxUser` tag is already set explicitly at `terraform/main.tf:22` and `:96-98`, no parsing needed.

### Pattern 7: Per-operator SSH key

**Current state (verified):** `terragrunt.hcl:30` — `key_name = "me"` (hardcoded).

**Proposed change to `terragrunt.hcl:30`:**
```hcl
inputs = {
  devbox_user      = local.user
  # …
  key_name         = "${local.user}-devbox"
  # …
}
```

**Rotation procedure (to document in `CLAUDE.md` in Phase 4, but designed here):**
1. Operator generates a new local keypair:
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/${DEVBOX_USER}-devbox -C "${DEVBOX_USER}@devbox-$(date +%Y%m%d)"
   ```
2. Operator imports the public key to AWS:
   ```bash
   aws ec2 import-key-pair \
       --key-name "${DEVBOX_USER}-devbox" \
       --public-key-material "fileb://$HOME/.ssh/${DEVBOX_USER}-devbox.pub" \
       --region "$AWS_REGION"
   ```
3. On rotation, delete the old AWS key and re-import:
   ```bash
   aws ec2 delete-key-pair --key-name "${DEVBOX_USER}-devbox" --region "$AWS_REGION"
   # then re-import (step 2)
   ```
4. The running EC2 instance must be *replaced* (terraform destroy + apply) — AWS does not push the new public key to a running instance. Document this trade-off.

**Why import (not `aws_key_pair` resource):** Managing the keypair in Terraform would mean the *public key file* lives in the state file. Better: keep the keypair *outside* the IaC (operator's `~/.ssh/`), only reference by name. [CITED: registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/key_pair — "the aws_key_pair resource requires an existing user-supplied key pair"]

**Update `terraform/outputs.tf:18`** (ssh_command): keep as-is — it already templates `${var.key_name}.pem`, which after the rename resolves to `${local.user}-devbox.pem`. Operators store their key at `~/.ssh/${DEVBOX_USER}-devbox.pem` (or use `ssh-keygen`'s default `ed25519` format and update the output to elide the extension).

**Pre-commit/CI interaction:** Keys live in AWS, **not in the repo**. Pre-commit and CI never see them. Document explicitly to prevent operators from PR-ing public keys.

### Pattern 8: gitleaks pre-commit + CI

**Latest stable: gitleaks v8.30.1** (released 2026-03-21). [VERIFIED: github.com/gitleaks/gitleaks/releases via WebSearch 2026-05-13]

**Proposed `.pre-commit-config.yaml` (new file at repo root, will be extended in Phase 4):**
```yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.30.1
    hooks:
      - id: gitleaks

  # Belt-and-braces guard against literal weak defaults
  - repo: local
    hooks:
      - id: no-changeme
        name: Block literal "changeme" in any tracked file
        entry: bash -c 'if git grep -nIE "changeme" -- ":!*.md" ":!.planning/**"; then echo "Found literal changeme — generate per-build secrets via Ansible password lookup"; exit 1; fi'
        language: system
        pass_filenames: false
```

[CITED: github.com/gitleaks/gitleaks/blob/master/.pre-commit-hooks.yaml]

**Proposed `.github/workflows/gitleaks.yml` (CI stub; Phase 4 expands with fmt/validate/lint/etc.):**
```yaml
name: gitleaks

on:
  push:
  pull_request:

jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      # SHA-pinned per the SHA-pinning best practice (Phase 4 invariant).
      - name: Checkout
        uses: actions/checkout@692973e3d937129bcbf40652eb9f2f61becf3332  # v4.1.7
        with:
          fetch-depth: 0   # full history for gitleaks to scan all commits

      - name: Run gitleaks
        uses: gitleaks/gitleaks-action@ff98106e4c7b2bc287b24eaf42907196329070c7  # v2.3.7
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          # GITLEAKS_LICENSE not required for public/personal repos.
```

[CITED: github.com/gitleaks/gitleaks-action; github.com/marketplace/actions/gitleaks; stepsecurity.io/blog/pinning-github-actions]

**Optional `.gitleaks.toml`** to extend default rules with project-specific allowances (e.g. permit example AWS account IDs in `.planning/` notes). Defer; default ruleset is sufficient for v1.

**Smoke test for Phase 1.3:**
1. Create a feature branch.
2. Add a fake AWS key to a temp file: `AKIAIOSFODNN7EXAMPLE`.
3. `git commit -m "test"` — pre-commit must fail.
4. Force-push (`--no-verify`) to the branch — GitHub Actions gitleaks run must fail and block merge.

### Anti-Patterns to Avoid

- **Secret in user_data:** Reading user_data is a single curl from inside the instance. Use the SSM fetch pattern in §6.
- **Secret in Packer `extra_arguments`:** Visible in `ps`, in Packer logs, in shell history.
- **Caching the `password` lookup to a real file** (e.g. `lookup('password','/tmp/cs.passwd length=32')`): leaves cleartext on the bake host that persists into the snapshot. Use `/dev/null` + `set_fact`.
- **Skipping `no_log: true` on secret-bearing tasks:** Ansible default verbosity prints variables and module results. Even `set_fact` will print the value at `-v`. Always `no_log: true`. [CITED: ansible.com no-log-password rule]
- **Hand-rolling argon2 hashing for code-server in v1:** `hashed-password` is supported but adds a build-time dep (`npx argon2-cli`). The SSM-delivered cleartext + in-memory bootstrap covers the threat model.
- **Granting `kms:Decrypt` on `*` without `kms:ViaService`:** Over-broad. Always condition on the calling service.
- **Trusting `iam_instance_profile` to be set externally:** Today `terraform/variables.tf:51-55` makes it optional. Plan should make it internally managed and remove the variable.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Random password generation in Ansible | Custom `shell: openssl rand …` task | `lookup('ansible.builtin.password', '/dev/null length=N')` | Built-in, idempotent semantics, well-understood. [CITED: docs.ansible.com password_lookup.html] |
| Writing SecureString to SSM | `command: aws ssm put-parameter …` | `community.aws.ssm_parameter` | Module handles overwrite semantics, returns idempotent change state, supports `no_log` cleanly. |
| Reading SecureString at boot | Custom Python / Node SDK boot script | `aws ssm get-parameter --with-decryption` (AWS CLI v2 already on AMI) | Already installed at `ansible/roles/base/tasks/main.yml:24-28`; no new deps. |
| IAM role + policy + instance profile | Hand-attaching managed policies post-hoc | Three native Terraform resources in `terraform/main.tf` | Reviewable in plan, scoped by per-user `var.devbox_user`. |
| Secret scanning | Hand-rolled regex grep | gitleaks | 200+ built-in rules covering AWS, GCP, GitHub, Slack, Stripe, etc. |
| VNC password hashing | Re-implementing the obfuscation | `vncpasswd -f` | Bundled with `tigervnc-server` already installed (`ansible/roles/desktop/tasks/main.yml:13`). |
| Per-operator key pair management | `aws_key_pair` resource holding public-key bytes | Out-of-band `aws ec2 import-key-pair` keyed by name | Keeps public-key file out of tfstate; rotation is a single CLI call. |

**Key insight:** Every wheel above has a documented, idempotent, audited solution already on the AMI or in the standard Ansible/Terraform/AWS stack. Custom code in this domain is a maintenance + leak risk.

## Runtime State Inventory

Phase 1 changes *what gets written* to SSM and *what gets generated* per build. It introduces no rename of existing live state. The categories below confirm that explicitly.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — SSM Parameter Store path `/devbox/${devbox_user}/*` is **new**; no existing parameters to migrate. Verified via reading `terraform/main.tf`, `terragrunt.hcl`, and `.planning/codebase/INTEGRATIONS.md` — only S3 (`devimage-tfstate-…`) and DynamoDB (`devimage-tfstate-locks`) currently used by this project, both unaffected. | None — new parameters created by the bake. |
| Live service config | code-server password lives in `~/.config/code-server/config.yaml` and VNC password lives in `~/.vnc/passwd` on every already-deployed devbox. After Phase 1 ships, **existing devboxes will keep running with their `changeme` config until they are rebuilt and re-launched** (the systemd-oneshot only runs on AMIs baked with Phase 1's `secrets` role). | Operator must: (a) bake a new AMI, (b) update `terragrunt.hcl:29` to the new AMI ID, (c) `tg-apply` to trigger instance replacement. Document this in CLAUDE.md (Phase 4 work). |
| OS-registered state | None — no systemd unit names, Task Scheduler entries, or OS-level identifiers being renamed. The new `devbox-secrets-bootstrap.service` is brand-new. | None. |
| Secrets/env vars | The `DEVBOX_USER` env var continues to flow as before (`Makefile:4`, `terragrunt.hcl:2`, `scripts/_common.sh:30-34`). Phase 1 adds *new* SSM parameter names — no env var renames. | None. |
| Build artifacts / installed packages | None — no installed package is renamed. AWS CLI v2 already present (`/usr/local/bin/aws` via `ansible/roles/base/tasks/main.yml:24-28`). | None. |

**Migration of in-flight devboxes:** Out of scope for Phase 1's *code* changes. **Document in the milestone changelog** that any operator with an existing devbox running on the pre-Phase-1 AMI must rebuild + redeploy to pick up the new posture. Acceptable for a personal IaC project; would need a coordinated cutover for a team.

## Common Pitfalls

### Pitfall 1: Secrets leak via Packer log

**What goes wrong:** Packer streams Ansible's stdout to the operator's terminal and (optionally) to a log file. Without `no_log: true`, any task that touches the secret variable prints it.

**Why it happens:** Ansible's default verbosity at `-v` prints module args. The `set_fact` of `code_server_password = "{{ lookup('password', …) }}"` prints the resolved value.

**How to avoid:** `no_log: true` on every task that touches a secret — generation, templating, SSM publish, file write. Verify by running the playbook with `-vvv` against a test target and grepping the log for the secret value.

**Warning signs:** Operator says "I can see the password in the Packer output."

### Pitfall 2: Secret persists in user_data / cloud-init logs

**What goes wrong:** Operator passes a secret via Packer `user_data` or `--extra-vars` on the launched instance. The user_data is queryable from inside the instance via IMDS forever; cloud-init logs the runcmd to `/var/log/cloud-init-output.log` which ends up in the AMI snapshot.

**Why it happens:** It's the most obvious way to "send a value to the instance." It's wrong.

**How to avoid:** Always use the IAM-instance-profile-mediated SSM fetch from a systemd oneshot baked into the AMI. The secret value never leaves AWS until the EC2 fetches it via IAM. [VERIFIED: cluster-api-aws userdata privacy doc, AWS user-data docs]

**Warning signs:** Anyone proposes a `user_data` block in Terraform, or any `extra_arguments` containing a secret in Packer.

### Pitfall 3: `creates:` guard silently disables rotation

**What goes wrong:** Today's `ansible/roles/desktop/tasks/main.yml:29-33` uses `creates: ~/.vnc/passwd`. The first build sets it; every subsequent build sees the file and skips the task, even with a new value.

**Why it happens:** `creates:` is for *truly idempotent* tasks (e.g., "install this binary if missing"). It is wrong for *rotation* semantics.

**How to avoid:** See §3 — drop `creates:`, set `changed_when: true`, add `no_log: true`, pipe stdin instead of shell heredoc.

**Warning signs:** Re-run of the playbook with a different password value reports "OK" instead of "CHANGED" on the VNC task.

### Pitfall 4: Hand-copied AMI lags secret rotation

**What goes wrong:** Operator bakes a new AMI (which rotates the SSM parameter to a new value), forgets to update `terragrunt.hcl:29`, and `tg-apply` re-uses the old AMI — but the SSM parameter is now the *new* value. The boot script writes the new password to `config.yaml`, but the old AMI's pre-bake artifacts (if any leaked through the AMI build) are stale.

**Why it happens:** Manual AMI promotion is fragile (`.planning/codebase/CONCERNS.md` HIGH "Built AMI ID is manually copied").

**How to avoid:** Not Phase 1's problem — Phase 3 (REP-05) fixes AMI-ID handoff. Phase 1 must, however, *always* write to the SSM parameter at bake time (`overwrite_value: always`), so the SSM value is always the value that the most-recent AMI's bootstrap script expects to fetch.

**Warning signs:** Operator reports "my devbox uses the old password after a rebuild" — usually means stale AMI ID in `terragrunt.hcl`.

### Pitfall 5: Over-broad KMS Decrypt permission

**What goes wrong:** A simple `kms:Decrypt` on `*` lets the EC2 decrypt *any* SecureString in the account that uses the default `alias/aws/ssm` key — including other teams' secrets.

**Why it happens:** Tutorial-grade IAM policies often omit the condition.

**How to avoid:** Use the `kms:ViaService` condition (see §5 example). This pins the decrypt to requests *brokered by SSM* — the EC2 cannot directly call KMS with this permission. [CITED: docs.aws.amazon.com/systems-manager/latest/userguide/secure-string-parameter-kms-encryption.html]

**Warning signs:** `tfsec` will flag overly-broad KMS `Resource: *` without condition.

### Pitfall 6: `password` lookup with a path = persistent cleartext

**What goes wrong:** `lookup('password', '/tmp/cs.passwd length=32')` caches to `/tmp/cs.passwd` on the bake host. If the role doesn't clean up *and* the path is on a partition that ends up in the snapshot, the cleartext survives into every running devbox.

**Why it happens:** Path-form is convenient for re-use across plays.

**How to avoid:** Always use `/dev/null` as the path, then `set_fact` to bind the value for the play. No file is written. [VERIFIED: docs.ansible.com — `/dev/null` is the documented "generate, don't persist" pattern.]

**Warning signs:** Any `/tmp/*.passwd` or `~/.cache/*` referenced in a `lookup('password', …)` call.

### Pitfall 7: Per-operator key collides on AWS

**What goes wrong:** Two operators with the same `${user}-devbox` name (e.g., both named `me`) clobber each other's keypair in AWS.

**Why it happens:** AWS key pair names are unique per region per account.

**How to avoid:** Pair the `DEVBOX_USER` validation in `Makefile:4` (CONCERNS.md LOW finding) with a check that the operator's `DEVBOX_USER` is the AWS IAM identity's user-name (or a fingerprint of it). Defer to Phase 4 docs; Phase 1 just makes the key name *parametric*, not yet *enforced unique*.

**Warning signs:** Two operators reporting their SSH connection works for the *other* person's devbox.

## Code Examples

### Example 1: AWS CLI smoke test that the SSM read works from the EC2

After the EC2 is up, SSH in and run:
```bash
# Should succeed (instance profile is attached, path matches policy):
aws ssm get-parameter \
    --name "/devbox/$(curl -s http://169.254.169.254/latest/meta-data/tags/instance/DevboxUser)/code-server-password" \
    --with-decryption \
    --query 'Parameter.Value' --output text

# Should FAIL (no permission to other users' paths):
aws ssm get-parameter --name "/devbox/other-user/code-server-password" --with-decryption
# Expected: AccessDeniedException
```

[CITED: docs.aws.amazon.com/cli/latest/reference/ssm/get-parameter.html]

### Example 2: Verify gitleaks gates a fake AWS key

```bash
echo "AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE" >> test-secret.txt
git add test-secret.txt
git commit -m "test"
# Expected: pre-commit hook fails with gitleaks output identifying the AWS key.
```

[VERIFIED: gitleaks default ruleset includes `aws-access-token` rule via github.com/gitleaks/gitleaks]

### Example 3: Operator retrieves their password after bake

```bash
DEVBOX_USER=${DEVBOX_USER:-$(whoami)}
aws ssm get-parameter \
    --name "/devbox/$DEVBOX_USER/code-server-password" \
    --with-decryption \
    --query 'Parameter.Value' --output text
```

Document this as `make get-passwords` target in Phase 4 docs work.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Bake secrets into AMI via `password: changeme` literal | Generate per-build, store in SSM, fetch at boot | This phase | Eliminates committed default; rotation is automatic per AMI build. |
| Pass secrets via user_data | Systemd oneshot reading SSM with IAM | AWS best practice since ~2018, reinforced by IMDSv2 (2019) | user_data is metadata-readable; oneshot+SSM is memory-only. |
| `auth: none` with no proxy on code-server | `auth: password` with random secret + (later) network restriction | code-server docs as of v4.x | "Never expose code-server directly to the internet without auth." [CITED: coder.com] |
| `gitleaks v7` (pre-2022) without action wrappers | `gitleaks v8.30.x` + `gitleaks-action@v2` | gitleaks-action v2 stable since ~2023 | Rule coverage expanded ~3x; v8 has built-in `protect`/`detect` modes. |

**Deprecated/outdated:**
- `password` lookup with `seed` parameter for reproducibility — non-secure RNG; do not use. [CITED: github.com/ansible/ansible/issues/78079]
- IMDSv1 — deprecated in favor of IMDSv2; the bootstrap script in §6 uses IMDSv2 exclusively.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `community.aws` collection is acceptable to add to `ansible/requirements.yml` | §1 Standard Stack, §1 Pattern code | If the operator doesn't want a fourth Galaxy collection, use `command: aws ssm put-parameter --overwrite …` with `no_log: true`. Functional equivalence; slightly less idempotent reporting. |
| A2 | The operator's AWS credentials at bake time can `ssm:PutParameter` against `/devbox/*` | §1 Pattern code | If not, add an IAM gap to the bake-time user. This is a build-user-IAM concern parallel to Phase 3's "Packer needs SSM write for AMI handoff." |
| A3 | gitleaks is preferred over detect-secrets | §8 alternatives table | LOW — both work; gitleaks is more current in 2026 ecosystem reporting. The vendored CIS role uses both (`ansible/roles/AMAZON2023-CIS/.pre-commit-config.yaml`) — Phase 4 may add `detect-secrets` belt-and-braces. |
| A4 | The DevboxUser tag is reliably present at boot for the bootstrap script to read | §6 Pattern code | The tag is set in `terraform/main.tf:22, 96-98` — verified. But the EC2 must have IAM permission to call `ec2:DescribeTags`; the policy in §5 currently lacks this. **Plan must add** `ec2:DescribeTags` (or use IMDSv2 tag-in-metadata if enabled). |
| A5 | code-server reads `~/.config/code-server/config.yaml` and not `/etc/code-server/config.yaml` on AL2023 | §6 bootstrap script | If the install path differs, the bootstrap script writes to the wrong file and the new password never takes effect. **Plan must verify** by inspecting `ansible/roles/vscode/tasks/main.yml` and `ansible/roles/vscode/templates/code-server.service.j2` for the actual path. |
| A6 | The systemd-oneshot's `Before=code-server.service vncserver.service` ordering is sufficient to keep services from starting with the old config | §6 Pattern | If services start before the oneshot completes (race on `network-online.target`), they read the old config. Mitigation: `Before=` + `Wants=` on the services side, plus explicit `systemctl restart` at the end of the oneshot. |
| A7 | "Per-build random VNC password truncated to 8 chars by vncpasswd" is acceptable | §1 Pattern code | VNC's wire protocol truncates the password to 8 chars regardless. Generating an 8-char random ASCII-letters-digits password is the standard. [CITED: tigervnc.org/doc/vncpasswd.html] |
| A8 | SHAs for `actions/checkout@v4.1.7` and `gitleaks/gitleaks-action@v2.3.7` in §8 are correct | §8 CI workflow stub | LOW — **Plan must resolve the actual current SHA** before merging the workflow. Provided values are illustrative. |

## Open Questions

1. **Should `ssm:PutParameter` permission for the bake user live in this repo or in a separate bootstrap module?**
   - What we know: The bake user (operator's AWS credentials) needs write access to `/devbox/*` SSM. Today the operator has whatever their IAM identity allows; this is implicit.
   - What's unclear: Whether to add a `terraform/bootstrap/` module that manages the bake-user policy.
   - Recommendation: Defer to Phase 3 (REP-04 / REP-05 already touches Packer post-processor IAM). Phase 1 documents the bake-user permission requirement in CLAUDE.md.

2. **Should we add `ec2:DescribeTags` to the EC2 runtime role, or fetch `DEVBOX_USER` from IMDSv2 tag metadata?**
   - What we know: IMDSv2 supports tag-in-metadata if `aws_instance.devbox` sets `metadata_options { instance_metadata_tags = "enabled" }`. [CITED: docs.aws.amazon.com EC2 metadata]
   - What's unclear: Whether enabling tag-in-metadata has any downside (it's purely additive).
   - Recommendation: Enable `instance_metadata_tags = "enabled"` in Terraform; drop `ec2:DescribeTags` from the IAM policy. Smaller policy surface. **Verify in Phase 2** when SG/IMDSv2 work happens.

3. **Should `desktop_vnc_password` accept operator override, or be strictly per-build random?**
   - What we know: ROADMAP.md flags an operator-override pathway via Packer `--extra-vars`.
   - What's unclear: Whether the override pathway is worth the complexity (operator must remember a value they typed in).
   - Recommendation: Generate per-build random by default; do *not* support operator override in v1. Operator retrieves via `aws ssm get-parameter`. Simpler contract.

4. **Does removing the `iam_instance_profile` variable from `terraform/variables.tf` break any consumer?**
   - What we know: `terragrunt.hcl:27-37` does not currently set it. Default at `terraform/variables.tf:51-55` is `null`. Replacing with a managed profile changes the type from "optional input" to "internally managed."
   - What's unclear: Whether any operator outside this repo consumes the `terraform/` module.
   - Recommendation: Drop the variable; the project is single-consumer (per PROJECT.md "Multi-tenant / shared infrastructure — out of scope"). Document the breaking change in the milestone changelog.

## Environment Availability

| Dependency | Required By | Available on bake host (AL2023 minimal) | Available on operator workstation | Version | Fallback |
|------------|------------|-----------------------------------------|-----------------------------------|---------|----------|
| `ansible.builtin.password` lookup | §1 password generation | ✓ (bundled with ansible-core) | n/a (runs in Packer's ansible plugin) | bundled | None needed |
| `community.aws` collection | §1 SSM publish | ✗ — must add to `ansible/requirements.yml` | n/a | latest (~9.x) | `command: aws ssm put-parameter` with `no_log: true` |
| AWS CLI v2 | §6 boot-time fetch | ✓ (installed by `ansible/roles/base/tasks/main.yml:24-28`) | ✓ (assumed; required by Makefile already) | 2.x | None — already a hard dep per `.planning/codebase/STACK.md` |
| `vncpasswd` | §3 VNC password | ✓ (installed by `ansible/roles/desktop/tasks/main.yml:13` via `tigervnc-server` package) | n/a | bundled with tigervnc-server | None needed |
| `gitleaks` | §8 secret scanning | n/a (runs only on operator + CI) | ✗ — must install (`brew install gitleaks` or `dnf install gitleaks`) | v8.30.1 | `detect-secrets` (the vendored CIS role's pre-commit uses both) |
| `pre-commit` framework | §8 hook orchestration | n/a | ✗ — must install (`brew install pre-commit` or `pip install pre-commit`) | 3.x | Local shell git-hooks |
| `aws_iam_role` / `aws_iam_role_policy` / `aws_iam_instance_profile` | §5 Terraform | n/a | ✓ (provider hashicorp/aws >= 5.0, `terraform/main.tf:7`) | — | None needed |

**Missing dependencies with no fallback:** None.

**Missing dependencies with fallback:**
- `community.aws` collection (use `command: aws ssm put-parameter` direct call)
- `gitleaks` (use `detect-secrets`)
- `pre-commit` framework (use raw `.git/hooks/pre-commit` shell script per d4b.dev pattern)

## Project Constraints (from CLAUDE.md)

`/Users/me/Documents/code/devbox/CLAUDE.md` is **empty** (0 bytes — confirmed in CONCERNS.md "CLAUDE.md is empty (LOW)" and STACK.md). Phase 4 (DOC-01) will populate it. **No CLAUDE.md directives constrain Phase 1.**

The user's global `~/.claude/rules/*.md` (visible in the agent's context) supply the following directives that apply to Phase 1's deliverables:

- **`security.md`:** No hardcoded secrets, validate all user inputs, never silently swallow errors. → Aligns directly with SEC-01..SEC-05.
- **`coding-style.md`:** Many small files > few large files (200-400 lines typical, 800 max). → The proposed new `ansible/roles/secrets/` role should split bake-time generation tasks (`tasks/generate.yml`), SSM publishing (`tasks/publish.yml`), and oneshot installation (`tasks/install-oneshot.yml`), wired from `tasks/main.yml`.
- **`testing.md`:** 80% coverage minimum, AAA pattern. → `nyquist_validation: false` in `.planning/config.json` so the Validation Architecture section is **omitted**. Phase 4 will add `ansible-lint` and `tfsec` as the standing quality gates. Phase 1 includes the gitleaks smoke test as a verification step but does not bring a unit test framework.
- **`git-workflow.md`:** Conventional commits (`feat:`, `fix:`, etc.). → Plan tasks should write commit messages in conventional-commits format.
- **`agents.md`:** Use `security-reviewer` agent for security-sensitive changes. → Plan should invoke it during code review of the Ansible secrets role and the IAM policy.

## Sources

### Primary (HIGH confidence)
- [Ansible password lookup docs](https://docs.ansible.com/projects/ansible/latest/collections/ansible/builtin/password_lookup.html) — idempotency semantics, `/dev/null` pattern, no_log guidance
- [Ansible random_string lookup docs](https://docs.ansible.com/projects/ansible/latest/collections/community/general/random_string_lookup.html) — non-idempotency disclaimer
- [Ansible logging.html](https://docs.ansible.com/ansible/latest/reference_appendices/logging.html) — `no_log` directive
- [code-server guide](https://coder.com/docs/code-server/guide) — auth posture (`auth: password` vs `auth: none`)
- [TigerVNC vncpasswd manpage](https://tigervnc.org/doc/vncpasswd.html) — `-f` filter mode, stdin-to-stdout obfuscation
- [AWS SSM put-parameter CLI reference](https://docs.aws.amazon.com/cli/latest/reference/ssm/put-parameter.html) — SecureString type, `--overwrite`
- [AWS SSM get-parameter CLI reference](https://docs.aws.amazon.com/cli/latest/reference/ssm/get-parameter.html) — `--with-decryption`
- [AWS SecureString KMS encryption docs](https://docs.aws.amazon.com/systems-manager/latest/userguide/secure-string-parameter-kms-encryption.html) — `kms:ViaService` condition pattern
- [AWS Systems Manager parameter store userguide](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-parameter-store.html)
- [AWS configure instance permissions for Systems Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/setup-instance-permissions.html) — instance profile setup
- [AWS user-data docs (EC2 user guide)](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/user-data.html) — user_data readability via IMDS
- [Terraform aws_iam_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role)
- [Terraform aws_iam_instance_profile](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile)
- [Terraform aws_key_pair](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/key_pair)
- [Gitleaks GitHub repo](https://github.com/gitleaks/gitleaks) — current version, pre-commit config
- [Gitleaks GitHub Action](https://github.com/gitleaks/gitleaks-action) — CI integration
- [Gitleaks releases](https://github.com/gitleaks/gitleaks/releases) — v8.30.1 confirmation

### Secondary (MEDIUM confidence)
- [AWS blog: how to choose secrets vs parameter store](https://aws.amazon.com/blogs/security/how-to-choose-the-right-aws-service-for-managing-secrets-and-configurations/) — official guidance on the decision
- [cluster-api-aws userdata privacy doc](https://cluster-api-aws.sigs.k8s.io/topics/userdata-privacy) — user_data exposure semantics
- [AWS Parameter Store vs Secrets Manager pricing 2026 (viprasol)](https://viprasol.com/blog/aws-parameter-store/) — pricing breakdown at small scale
- [StratusGrid terraform-aws-ec2-instance-profile-builder iam-policy-ssm.tf](https://github.com/StratusGrid/terraform-aws-ec2-instance-profile-builder/blob/main/iam-policy-ssm.tf) — least-privilege IAM example
- [CloudPosse terraform-aws-ssm-iam-role](https://github.com/cloudposse/terraform-aws-ssm-iam-role) — module-level pattern reference
- [appsecsanta gitleaks vs trufflehog 2026](https://appsecsanta.com/sast-tools/gitleaks-vs-trufflehog) — scanner comparison

### Tertiary (LOW confidence)
- [d4b.dev local gitleaks pre-commit hook](https://www.d4b.dev/blog/2026-02-01-gitleaks-pre-commit-hook/) — framework-free fallback
- [icicimov LUKS+SSM+systemd article](https://icicimov.github.io/blog/server/LUKS-with-AWS-SSM-and-KMS-in-Systemd/) — systemd-oneshot pattern reference
- [code-server hashed-password discussion #7378](https://github.com/coder/code-server/discussions/7378) — argon2 alternative (not recommended for v1)
- [StepSecurity pinning GitHub Actions](https://www.stepsecurity.io/blog/pinning-github-actions-for-enhanced-security-a-complete-guide) — SHA-pinning best practice

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all primitives verified against official docs.
- SSM vs Secrets Manager decision: HIGH — pricing + use-case fit are unambiguous.
- IAM policy shape: HIGH — direct from AWS docs and Terraform registry.
- Ansible password pattern: HIGH — primary doc cited.
- VNC rotation fix: HIGH — CONCERNS.md already diagnosed the bug; vncpasswd manpage confirms `-f` semantics.
- Boot-time secret retrieval: MEDIUM — systemd oneshot pattern is canonical but not in a single AWS official doc; cross-referenced from multiple sources.
- code-server `auth` posture: MEDIUM — official docs are clear about `auth: none` requiring proxy, but the project's Phase 2 will narrow SG, so the recommendation is conditional.
- gitleaks vs alternatives: MEDIUM — strong 2026 ecosystem signal; tertiary on detect-secrets fade.

**Research date:** 2026-05-13
**Valid until:** 2026-06-13 (30 days; AWS SSM/IAM are stable; revisit gitleaks version pin at 30-day mark).
