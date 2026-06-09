# Phase 8: Jupyter + mise AMI Layer - Pattern Map

**Mapped:** 2026-06-02
**Files analyzed:** 11 (new/modified)
**Analogs found:** 11 / 11

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `ansible/roles/jupyter/tasks/main.yml` | role/tasks | batch (install + configure) | `ansible/roles/vscode/tasks/main.yml` | exact |
| `ansible/roles/jupyter/defaults/main.yml` | config | — | `ansible/roles/vscode/defaults/main.yml` | exact |
| `ansible/roles/jupyter/templates/jupyter.service.j2` | template/systemd | event-driven | `ansible/roles/vscode/templates/code-server.service.j2` | exact |
| `ansible/roles/mise/tasks/main.yml` | role/tasks | batch (binary install + profile) | `ansible/roles/golang/tasks/main.yml` + `ansible/roles/certs/tasks/main.yml` | role-match |
| `ansible/roles/mise/defaults/main.yml` | config | — | `ansible/roles/golang/defaults/main.yml` | exact |
| `ansible/roles/secrets/tasks/generate.yml` | task | batch (in-memory secret gen) | self (extend existing) | self |
| `ansible/roles/secrets/tasks/publish.yml` | task | request-response (SSM API) | self (extend existing) | self |
| `ansible/roles/secrets/defaults/main.yml` | config | — | self (extend existing) | self |
| `ansible/roles/secrets/templates/devbox-secrets-bootstrap.sh.j2` | template/script | request-response (SSM fetch + service restart) | self (extend existing) | self |
| `ansible/roles/secrets/templates/devbox-secrets-bootstrap.service.j2` | template/systemd | event-driven | self (extend existing) | self |
| `ansible/playbook.yml` | config/orchestration | — | self (extend existing) | self |
| `ansible/layer_config.yml` | config | — | self (extend existing) | self |

---

## Pattern Assignments

### `ansible/roles/jupyter/tasks/main.yml` (role/tasks, batch)

**Analog:** `ansible/roles/vscode/tasks/main.yml`

**Core task sequence pattern** (lines 1–54 of analog):
```yaml
# Pattern: download → install → config dir → write config template → systemd unit → enable
# Copy the exact task-name convention: "Download X", "Install X", "Create X config directory",
# "Write X config", "Install X systemd service", "Enable X service"

- name: Download code-server RPM
  get_url:
    url: "https://github.com/coder/code-server/releases/download/v{{ code_server_version }}/code-server-{{ code_server_version }}-amd64.rpm"
    dest: /tmp/code-server.rpm
    mode: "0644"

- name: Install code-server
  dnf:
    name: /tmp/code-server.rpm
    state: present
    disable_gpg_check: true

- name: Create code-server config directory
  file:
    path: "{{ dev_home }}/.config/code-server"
    state: directory
    owner: "{{ dev_user }}"
    group: "{{ dev_user }}"
    mode: "0755"

- name: Write code-server config
  template:
    src: config.yaml.j2
    dest: "{{ dev_home }}/.config/code-server/config.yaml"
    owner: "{{ dev_user }}"
    group: "{{ dev_user }}"
    mode: "0600"

- name: Install code-server systemd service
  template:
    src: code-server.service.j2
    dest: /etc/systemd/system/code-server.service
    mode: "0644"
  notify: reload systemd

- name: Enable code-server service
  systemd:
    name: code-server
    enabled: true
    daemon_reload: true
```

**Adaptation notes for `jupyter/tasks/main.yml`:**
- Replace `dnf` install with venv creation + pip install sequence (use `command` module, not `pip` module, to invoke the venv's pip directly: `{{ jupyter_venv_path }}/bin/pip`)
- Insert TLS cert generation tasks between install and config (copy from `desktop/tasks/main.yml` lines 152–175 — see TLS cert pattern below)
- Config dir is `{{ dev_home }}/.jupyter` not `{{ dev_home }}/.config/jupyter`; config file is `jupyter_server_config.py` (Python, not YAML)
- The bake-time config MUST be a placeholder only — no password value at bake time (see Anti-Patterns in RESEARCH.md)
- Add `After=devbox-secrets-bootstrap.service` to the systemd unit (see Pitfall 4 in RESEARCH.md)
- ipykernel install task goes after venv pip install, before config dir

**TLS cert generation pattern** (`ansible/roles/desktop/tasks/main.yml` lines 152–175):
```yaml
- name: Create noVNC TLS cert directory
  file:
    path: /etc/novnc
    state: directory
    mode: "0755"

- name: Generate self-signed TLS cert for noVNC
  command: >
    openssl req -x509 -nodes -newkey rsa:2048
    -keyout /etc/novnc/novnc-key.pem
    -out /etc/novnc/novnc-cert.pem
    -days 3650 -subj '/CN=devbox'
  args:
    creates: /etc/novnc/novnc-cert.pem

- name: Set noVNC cert/key permissions
  file:
    path: "{{ item.path }}"
    owner: root
    group: "{{ dev_user }}"
    mode: "{{ item.mode }}"
  loop:
    - { path: /etc/novnc/novnc-cert.pem, mode: "0644" }
    - { path: /etc/novnc/novnc-key.pem,  mode: "0640" }
```

Substitute `/etc/novnc` with `{{ jupyter_cert_dir }}` (e.g. `/etc/jupyter`) and adjust filenames to `jupyter-cert.pem` / `jupyter-key.pem`.

---

### `ansible/roles/jupyter/defaults/main.yml` (config)

**Analog:** `ansible/roles/vscode/defaults/main.yml` (lines 1–15)
```yaml
---
code_server_version: "4.93.1"
code_server_port: 8080
code_server_bind_addr: "0.0.0.0:8080"

code_server_extensions:
  - ms-python.python
  ...

dev_user: ec2-user
dev_home: /home/ec2-user
```

**Copy this layout verbatim, substituting:**
```yaml
---
# [VERIFIED: pypi.org — 2026-06-02]
jupyterlab_version: "4.5.7"
ipykernel_version: "7.2.0"
jupyter_venv_path: /opt/jupyter
jupyter_bind_ip: "0.0.0.0"
jupyter_port: 8888
jupyter_cert_dir: /etc/jupyter
jupyter_notebook_dir: "{{ dev_home }}"

dev_user: ec2-user
dev_home: /home/ec2-user
```

Quoting convention: string versions always quoted (matches `code_server_version: "4.93.1"` and `go_version: "1.22.5"` patterns throughout the codebase).

---

### `ansible/roles/jupyter/templates/jupyter.service.j2` (template/systemd)

**Analog:** `ansible/roles/vscode/templates/code-server.service.j2` (lines 1–16, full file)
```ini
[Unit]
Description=code-server
After=network.target

[Service]
Type=simple
User={{ dev_user }}
Group={{ dev_user }}
ExecStart=/usr/bin/code-server --bind-addr {{ code_server_bind_addr }}
Restart=on-failure
RestartSec=5
Environment=HOME={{ dev_home }}

[Install]
WantedBy=multi-user.target
```

**Adaptation notes:**
- `After=` must include `devbox-secrets-bootstrap.service` in addition to `network.target` (Pitfall 4 in RESEARCH.md)
- `ExecStart` uses venv binary directly: `{{ jupyter_venv_path }}/bin/jupyter lab` with `--ip` and `--port` flags separately (not `--bind-addr`)
- Add `--certfile` and `--keyfile` CLI flags (no `cert: true` shorthand — that is a code-server-ism)
- Add `--no-browser` and `--notebook-dir={{ jupyter_notebook_dir }}`
- Keep `Type=simple`, `User/Group={{ dev_user }}`, `Restart=on-failure`, `RestartSec=5`, `Environment=HOME={{ dev_home }}` unchanged

---

### `ansible/roles/mise/tasks/main.yml` (role/tasks, batch)

**Primary analog:** `ansible/roles/golang/tasks/main.yml` (binary download + PATH setup via `/etc/profile.d`) + `ansible/roles/certs/tasks/main.yml` lines 23–34 (`/etc/profile.d` write pattern)

**Binary download pattern** (`golang/tasks/main.yml` lines 1–7):
```yaml
- name: Download Go {{ go_version }}
  get_url:
    url: "https://go.dev/dl/go{{ go_version }}.linux-amd64.tar.gz"
    dest: /tmp/go.tar.gz
    mode: "0644"
```

For mise, adapt to direct binary (no archive) with checksum verification:
```yaml
- name: Download mise v{{ mise_version }} binary
  get_url:
    url: "https://github.com/jdx/mise/releases/download/v{{ mise_version }}/mise-v{{ mise_version }}-linux-x64"
    dest: "{{ mise_install_dir }}/mise"
    mode: "0755"
    checksum: "sha256:{{ mise_checksum_sha256 }}"
```

**profile.d write pattern** (`certs/tasks/main.yml` lines 23–34):
```yaml
- name: Write /etc/profile.d/ca-trust.sh
  when: ca_cert_env_vars
  copy:
    dest: /etc/profile.d/ca-trust.sh
    mode: "0644"
    content: |
      # Point SSL tools at the system CA bundle
      export SSL_CERT_FILE=/etc/pki/tls/certs/ca-bundle.crt
      ...
```

Also compare with `golang/tasks/main.yml` lines 19–23:
```yaml
- name: Add Go to system PATH
  copy:
    content: |
      export PATH={{ go_bin }}:$PATH
    dest: /etc/profile.d/golang.sh
    mode: "0644"
```

For mise, adapt:
```yaml
- name: Write mise system-wide bash activation
  copy:
    dest: /etc/profile.d/mise.sh
    mode: "0644"
    content: |
      # mise version manager — system-wide bash activation (Phase 8 MISE-02)
      eval "$(mise activate bash)"
```

**Full task order for `mise/tasks/main.yml`:**
1. `get_url` — download binary to `{{ mise_install_dir }}/mise` with checksum
2. `copy` — write `/etc/profile.d/mise.sh`

No cleanup needed (binary is installed in-place, not extracted from archive).

---

### `ansible/roles/mise/defaults/main.yml` (config)

**Analog:** `ansible/roles/golang/defaults/main.yml` (lines 1–7, full file)
```yaml
---
go_version: "1.22.5"

go_install_dir: /usr/local
go_bin: /usr/local/go/bin

dev_user: ec2-user
dev_home: /home/ec2-user
```

**Adaptation:**
```yaml
---
# [VERIFIED: github.com/jdx/mise/releases — 2026-06-02]
mise_version: "2026.5.18"
# SHA-256 of mise-v2026.5.18-linux-x64 — fetch from SHASUMS256.txt (Wave 0 task)
mise_checksum_sha256: "<fill from SHASUMS256.txt>"
mise_install_dir: /usr/local/bin

dev_user: ec2-user
dev_home: /home/ec2-user
```

Note: no `dev_user`/`dev_home` usage in the mise role tasks (system-wide install), but include them per convention so the role can reference them if needed.

---

### `ansible/roles/secrets/tasks/generate.yml` (extend existing)

**Source:** `ansible/roles/secrets/tasks/generate.yml` (lines 1–34, full file)

**Pattern to replicate for Jupyter** (copy the code-server block, lines 1–24, and adapt):
```yaml
- name: Generate code-server password (per-build, in-memory only)
  ansible.builtin.set_fact:
    code_server_password: "{{ lookup('ansible.builtin.password',
                                    '/dev/null length=' ~ secrets_code_server_password_length
                                    ~ ' chars=ascii_letters,digits') }}"
  no_log: true

- name: Assert code-server password is non-empty
  ansible.builtin.assert:
    that:
      - code_server_password is defined
      - code_server_password | length >= secrets_code_server_password_length
      - code_server_password != "changeme"
    fail_msg: "code_server_password generation failed or produced a forbidden value"
    quiet: true
  no_log: true
```

**Add two tasks at the end of generate.yml** (generate + assert), naming the variable `jupyter_password` and the length var `secrets_jupyter_password_length`. Copy the `no_log: true` on both tasks — this is mandatory.

---

### `ansible/roles/secrets/tasks/publish.yml` (extend existing)

**Source:** `ansible/roles/secrets/tasks/publish.yml` (lines 21–39)

**Pattern to replicate for Jupyter** (copy the code-server publish block, lines 21–29):
```yaml
- name: Publish code-server password to SSM Parameter Store (SecureString)
  community.aws.ssm_parameter:
    name: "{{ secrets_ssm_code_server_param }}"
    description: "code-server password for {{ devbox_user }} devbox (build {{ ansible_date_time.iso8601 }})"
    string_type: SecureString
    value: "{{ code_server_password }}"
    overwrite_value: always
    region: "{{ aws_region }}"
  no_log: true
```

**Add one task at end of publish.yml:** substitute `secrets_ssm_jupyter_param` for `secrets_ssm_code_server_param`, `jupyter_password` for `code_server_password`, and update the description string to "JupyterLab password for...". Keep `no_log: true`.

---

### `ansible/roles/secrets/defaults/main.yml` (extend existing)

**Source:** `ansible/roles/secrets/defaults/main.yml` (lines 1–11, full file)
```yaml
---
# Password lengths (chars=ascii_letters,digits enforced in generate.yml).
secrets_code_server_password_length: 32
# VNC's wire protocol truncates to 8 chars regardless. See RESEARCH.md §1 Assumption A7.
secrets_vnc_password_length: 8

# SSM Parameter Store layout. Per-user keyed; matches the Terraform IAM policy ARN
# (arn:aws:ssm:<region>:<account>:parameter/devbox/<devbox_user>/*).
secrets_ssm_prefix: "/devbox/{{ devbox_user }}"
secrets_ssm_code_server_param: "{{ secrets_ssm_prefix }}/code-server-password"
secrets_ssm_vnc_param: "{{ secrets_ssm_prefix }}/vnc-password"
```

**Append two lines** following the existing `secrets_ssm_vnc_param` line:
```yaml
secrets_jupyter_password_length: 32
secrets_ssm_jupyter_param: "{{ secrets_ssm_prefix }}/jupyter-password"
```

The password length 32 matches the code-server convention (no protocol truncation constraint unlike VNC's 8-char limit).

---

### `ansible/roles/secrets/templates/devbox-secrets-bootstrap.sh.j2` (extend existing)

**Source:** `ansible/roles/secrets/templates/devbox-secrets-bootstrap.sh.j2` (lines 1–73, full file)

**Critical structure to preserve:**
- Lines 1–9: idempotency guard (`/var/lib/devbox/secrets-applied` check) — do not touch
- Lines 12–26: IMDSv2 token + region + DEVBOX_USER fetch — do not touch
- Lines 29–38: existing CS_PWD / VNC_PWD SSM fetches — extend after these
- Lines 41–58: config application blocks — add Jupyter block after VNC block
- Lines 63–64: guard file creation — do not touch (marker written BEFORE service restart)
- Lines 67–72: service restart loop — extend the `for svc in` list

**Extension point 1 — SSM fetch** (after line 38, after the empty-password guard):
```bash
JUPYTER_PWD=$(aws ssm get-parameter --region "$REGION" \
    --name "/devbox/$DEVBOX_USER/jupyter-password" \
    --with-decryption --query 'Parameter.Value' --output text)
```

**Extension point 2 — empty check** (extend the existing guard on lines 36–39):
```bash
if [[ -z "$CS_PWD" || -z "$VNC_PWD" || -z "$JUPYTER_PWD" ]]; then
    echo "Empty password returned from SSM; refusing to write empty config" >&2
    exit 1
fi
```

**Extension point 3 — config application block** (after the VNC block ending at line 58):
```bash
# Hash Jupyter password using venv Python (argon2 by default; FIPS fallback to sha256).
JUPYTER_HASH=$(/opt/jupyter/bin/python3 -c \
    "from jupyter_server.auth import passwd; print(passwd('${JUPYTER_PWD}'))" 2>/dev/null) \
    || JUPYTER_HASH=$(/opt/jupyter/bin/python3 -c \
    "from jupyter_server.auth import passwd; print(passwd('${JUPYTER_PWD}', algorithm='sha256'))")

if [[ -z "$JUPYTER_HASH" ]]; then
    echo "Failed to hash jupyter password; refusing to write empty config" >&2
    exit 1
fi

# Write Jupyter config (jupyter-server 2.x key — NOT c.ServerApp.password which is deprecated).
install -d -o ec2-user -g ec2-user -m 0700 /home/ec2-user/.jupyter
cat > /home/ec2-user/.jupyter/jupyter_server_config.py <<EOF
# Written by devbox-secrets-bootstrap at boot. Do not edit manually.
# WARNING: Do NOT create jupyter_server_config.json — JSON takes precedence over .py
#          and will silently override this password setting.
c.PasswordIdentityProvider.hashed_password = '${JUPYTER_HASH}'
EOF
chown ec2-user:ec2-user /home/ec2-user/.jupyter/jupyter_server_config.py
chmod 0600 /home/ec2-user/.jupyter/jupyter_server_config.py
```

**Extension point 4 — service restart loop** (line 68, extend existing list):
```bash
# Before (line 68):
for svc in code-server.service vncserver.service novnc.service; do
# After:
for svc in code-server.service vncserver.service novnc.service jupyter.service; do
```

The existing loop already handles missing units gracefully (`systemctl list-unit-files "$svc" >/dev/null 2>&1` guard on line 69) — no change needed to the loop body.

---

### `ansible/roles/secrets/templates/devbox-secrets-bootstrap.service.j2` (extend existing)

**Source:** `ansible/roles/secrets/templates/devbox-secrets-bootstrap.service.j2` (lines 1–14, full file)
```ini
[Unit]
Description=Fetch devbox secrets from SSM and apply to code-server / VNC
Wants=network-online.target
After=network-online.target cloud-final.service
Before=code-server.service vncserver.service novnc.service
ConditionPathExists=!/var/lib/devbox/secrets-applied
...
```

**Change required:** Extend the `Before=` line to include `jupyter.service`:
```ini
# Before:
Before=code-server.service vncserver.service novnc.service
# After:
Before=code-server.service vncserver.service novnc.service jupyter.service
```

Also update the `Description=` to mention JupyterLab:
```ini
Description=Fetch devbox secrets from SSM and apply to code-server / VNC / JupyterLab
```

---

### `ansible/playbook.yml` (extend existing)

**Source:** `ansible/playbook.yml` (lines 48–58, the secrets/vscode/desktop/hardening block)
```yaml
    - role: secrets
      when: (layers.vscode | default(false)) or (layers.desktop | default(false))

    - role: vscode
      when: layers.vscode | default(false)

    - role: desktop
      when: layers.desktop | default(false)

    - role: hardening
      when: layers.hardening | default(false)
```

**Required edits** — two insertions, one modification:

1. Extend the `secrets` role `when:` condition to include `layers.jupyter`:
```yaml
    - role: secrets
      when: >-
        (layers.vscode | default(false)) or
        (layers.desktop | default(false)) or
        (layers.jupyter | default(false))
```

2. Insert `jupyter` and `mise` roles after `desktop` and before `hardening`:
```yaml
    - role: jupyter
      when: layers.jupyter | default(false)

    - role: mise
      when: layers.mise | default(false)

    - role: hardening          # MUST remain last — invariant (JUP-08 / CLAUDE.md §8)
      when: layers.hardening | default(false)
```

The `mise` role near language/devtools roles is the stated convention (CONTEXT.md); positioning after `jupyter` and before `hardening` satisfies both "near devtools" and "before hardening".

---

### `ansible/layer_config.yml` (extend existing)

**Source:** `ansible/layer_config.yml` (lines 1–22, full file)
```yaml
# Layer Configuration
# Toggle layers on/off to customize the image build.
# To add a new layer: create ansible/roles/<name>/, then add it here.

layers:
  base: true
  certs: true
  ...
  desktop: true
  hardening: true
```

**Append two entries** before `hardening:`:
```yaml
  jupyter: true
  mise: true
```

Place them after `desktop: true` and before `hardening: true`, following the same ordering as `playbook.yml`.

---

## Shared Patterns

### `no_log: true` on all secret-touching tasks
**Source:** `ansible/roles/secrets/tasks/generate.yml` lines 3–7, 17–24; `publish.yml` lines 22–29, 32–39
**Apply to:** Every `set_fact` and `ssm_parameter` task that touches `jupyter_password`
```yaml
  no_log: true   # mandatory on every task that reads/writes a secret value
```

### Binary version-pinning in defaults
**Source:** `ansible/roles/golang/defaults/main.yml` line 2; `ansible/roles/vscode/defaults/main.yml` line 2
```yaml
go_version: "1.22.5"
code_server_version: "4.93.1"
```
Both are quoted strings. Apply the same convention to `jupyterlab_version`, `ipykernel_version`, and `mise_version`. Never use floating `latest`.

### `systemd` enable task with `daemon_reload: true`
**Source:** `ansible/roles/vscode/tasks/main.yml` lines 43–46
```yaml
- name: Enable code-server service
  systemd:
    name: code-server
    enabled: true
    daemon_reload: true
```
Copy verbatim for `jupyter` (name: `jupyter`) and pair with `notify: reload systemd` on the template install task above it.

### `notify: reload systemd` on systemd unit template installs
**Source:** `ansible/roles/vscode/tasks/main.yml` lines 35–40
```yaml
- name: Install code-server systemd service
  template:
    src: code-server.service.j2
    dest: /etc/systemd/system/code-server.service
    mode: "0644"
  notify: reload systemd
```
The `reload systemd` handler is defined per-role. The `vscode` role has `ansible/roles/vscode/handlers/main.yml`. The `jupyter` role needs its own `handlers/main.yml` with the same content, OR the `notify` target must match a handler in scope.

### `ansible.builtin.` FQCN prefix on core modules
**Source:** `ansible/roles/secrets/tasks/generate.yml` line 3, `ansible/roles/secrets/tasks/publish.yml` line 1, `ansible/roles/secrets/tasks/install-oneshot.yml` line 2
```yaml
ansible.builtin.set_fact:
ansible.builtin.assert:
ansible.builtin.template:
ansible.builtin.file:
ansible.builtin.systemd:
```
The `secrets` role consistently uses FQCN for `ansible.builtin.*` modules. Match this in new `jupyter` and `mise` role tasks. The `vscode` role uses short names — follow the `secrets` role's more explicit convention for new roles.

### IMDSv2 + SSM fetch structure in bootstrap script
**Source:** `ansible/roles/secrets/templates/devbox-secrets-bootstrap.sh.j2` lines 12–38

The fetch pattern is:
1. IMDSv2 token → REGION → DEVBOX_USER from instance metadata tags
2. `aws ssm get-parameter --with-decryption` for each SecureString
3. Single empty-string guard covering all fetched values before any writes

Do not split the empty-string guard — keep all SSM-fetched passwords in one `if [[ -z "$A" || -z "$B" || -z "$C" ]]` block.

---

## No Analog Found

All files have analogs in the codebase. No files require falling back to RESEARCH.md patterns exclusively, though the Jupyter role's venv+pip install sequence and the password-hashing block in the bootstrap script are net-new logic with no direct task-level analog (the RESEARCH.md code examples are the authoritative source for those specific snippets).

---

## Metadata

**Analog search scope:** `ansible/roles/vscode/`, `ansible/roles/secrets/`, `ansible/roles/desktop/`, `ansible/roles/certs/`, `ansible/roles/golang/`, `ansible/roles/python/`, `ansible/roles/rust/`, `ansible/playbook.yml`, `ansible/layer_config.yml`
**Files scanned:** 23
**Pattern extraction date:** 2026-06-02
