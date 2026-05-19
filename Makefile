.PHONY: help validate build fmt clean packer-init packer-bake \
        start stop status \
        devbox-ssm devbox-port-forward devbox-allowlist-me secrets-show \
        tf-init tf-reinit tf-plan tf-apply tf-auto-apply tf-destroy tf-auto-destroy

# User detection: override with  make <target> DEVBOX_USER=jsmith
DEVBOX_USER ?= $(shell whoami)

# IaC binary: default OpenTofu (canonical per CLAUDE.md §8 — the committed
# terraform/.terraform.lock.hcl is OpenTofu-flavoured). Operator may override to
# `terraform` for compatibility testing, but the lockfile + provider checksums
# will diverge — expect drift.
#   make tf-apply TF_BIN=terraform
TF_BIN ?= tofu

# --- Backend config (derived; Terragrunt-free) ---------------------------------
# Phase 5 (post-v1.0): Terragrunt removed. Backend bucket name derives from the
# caller AWS account; per-operator state key threads DEVBOX_USER.
TF_STATE_REGION ?= us-east-1
TF_STATE_LOCK_TABLE ?= devimage-tfstate-locks
TF_STATE_BUCKET ?= devimage-tfstate-$(shell aws sts get-caller-identity --query Account --output text 2>/dev/null)
TF_STATE_KEY     = users/$(DEVBOX_USER)/devbox.tfstate

# CIDR aggregation: union of CODE_SERVER_ALLOWED_CIDRS + VNC_ALLOWED_CIDRS
# (comma-separated env vars), trimmed, deduped, emitted as a JSON array for
# `tofu -var`. Empty env → []. Operators who prefer file-based config can
# leave the env vars unset and let `make devbox-allowlist-me` write
# allowlist.auto.tfvars (gitignored) instead. The validation block in
# terraform/variables.tf is the gate that rejects an empty result unless
# var.allow_open_ingress = true.
TF_CIDR_LIST = $(shell printf '%s,%s' "$$CODE_SERVER_ALLOWED_CIDRS" "$$VNC_ALLOWED_CIDRS" \
                       | tr ',' '\n' | sed 's/[[:space:]]//g' \
                       | grep -v '^$$' | sort -u \
                       | jq -R . | jq -s -c . 2>/dev/null || echo '[]')

TF_VAR_ARGS = -var "devbox_user=$(DEVBOX_USER)" \
              -var "key_name=$(DEVBOX_USER)-devbox" \
              -var 'allowed_web_cidrs=$(TF_CIDR_LIST)'

TF_BACKEND_ARGS = -backend-config="bucket=$(TF_STATE_BUCKET)" \
                  -backend-config="key=$(TF_STATE_KEY)" \
                  -backend-config="region=$(TF_STATE_REGION)" \
                  -backend-config="dynamodb_table=$(TF_STATE_LOCK_TABLE)"

# ------------------------------------------------------------------------------

help:
	@echo "Usage: make <target> [DEVBOX_USER=username]"
	@echo ""
	@echo "AMI"
	@echo "  packer-init  Install Packer plugins"
	@echo "  validate     Validate Packer and Terraform configs"
	@echo "  build        Build the devimage AMI with Packer (legacy — prefer packer-bake)"
	@echo "  packer-bake  Build AMI + write users/\$$(DEVBOX_USER).auto.tfvars (handoff for tf-apply)"
	@echo "  fmt          Format Packer and Terraform files"
	@echo ""
	@echo "Terraform / OpenTofu (per-operator state at users/\$$DEVBOX_USER/devbox.tfstate)"
	@echo "  tf-init          Init backend for DEVBOX_USER (first-time / after switching user)"
	@echo "  tf-reinit        Re-init with -reconfigure (after backend changes or stale .terraform)"
	@echo "  tf-plan          Plan changes for DEVBOX_USER"
	@echo "  tf-apply         Apply with confirmation prompt"
	@echo "  tf-auto-apply    Apply without prompt"
	@echo "  tf-destroy       Destroy with confirmation prompt"
	@echo "  tf-auto-destroy  Destroy without prompt"
	@echo ""
	@echo "Instance lifecycle (override resolution: INSTANCE_ID=i-... REGION=us-east-1)"
	@echo "  start        Start the devbox EC2 instance"
	@echo "  stop         Stop the devbox EC2 instance"
	@echo "  status       Show instance status and connection info"
	@echo ""
	@echo "SSM access (Phase 2 — replaces public :22 ingress)"
	@echo "  devbox-ssm           Open an SSM Session Manager shell to the devbox"
	@echo "  devbox-port-forward  Forward :8080 from the devbox to localhost over SSM"
	@echo "  devbox-allowlist-me  Resolve your public IP and write allowlist.auto.tfvars"
	@echo ""
	@echo "Secrets"
	@echo "  secrets-show   Print the operator's code-server and VNC passwords from SSM"
	@echo ""
	@echo "Cleanup"
	@echo "  clean        Remove Packer cache and Terraform local state"

# --- Packer ---

packer-init:
	cd packer && packer init .

validate: packer-init
	cd packer && packer validate .
	cd terraform && $(TF_BIN) validate

build: packer-init
	cd packer && packer build .

# --- AMI bake + handoff to Terraform (REP-04, REP-05) ---
# Replaces the legacy `make build` for the day-to-day flow.
# 1) Removes any stale manifest (Pitfall 4 in 03-RESEARCH.md).
# 2) Runs `packer build`, which emits packer/packer-manifest.json.
# 3) Extracts the AMI ID from the most-recent build entry (sort_by(.build_time)).
# 4) Writes users/$(DEVBOX_USER).auto.tfvars — auto-loaded by Terraform.
# Operator flow:  make packer-bake DEVBOX_USER=$$(whoami)  &&  make tf-apply
packer-bake: packer-init
	@rm -f packer/packer-manifest.json
	cd packer && DEVBOX_USER=$(DEVBOX_USER) packer build -var "devbox_user=$(DEVBOX_USER)" .
	@AMI_ID=$$(jq -r '.builds | sort_by(.build_time) | .[-1].artifact_id | split(":") | .[1]' packer/packer-manifest.json); \
	  [ -n "$$AMI_ID" ] && [ "$$AMI_ID" != "null" ] || { echo "ERROR: AMI ID missing in packer/packer-manifest.json" >&2; exit 1; }; \
	  mkdir -p users; \
	  printf '# Generated by `make packer-bake` — do not edit, do not commit (gitignored).\nami_id = "%s"\n' "$$AMI_ID" > users/$(DEVBOX_USER).auto.tfvars; \
	  echo "Wrote ami_id=$$AMI_ID to users/$(DEVBOX_USER).auto.tfvars"; \
	  echo "Next: make tf-apply DEVBOX_USER=$(DEVBOX_USER)"

fmt:
	cd packer && packer fmt .
	cd terraform && $(TF_BIN) fmt
	@echo "Format complete"

# --- Terraform / OpenTofu (Terragrunt-free; per-operator state key) ---

# Auto-init guard: re-point the backend whenever .terraform/ is missing or its
# cached backend key doesn't match the current DEVBOX_USER's key. Makes
# tf-plan/apply/destroy + status/start/stop/devbox-ssm self-healing across
# DEVBOX_USER switches and fresh clones.
.PHONY: tf-ensure-init
tf-ensure-init:
	@CACHED=$$(jq -r '.backend.config.key // empty' terraform/.terraform/terraform.tfstate 2>/dev/null || true); \
	if [ "$$CACHED" != "$(TF_STATE_KEY)" ]; then \
	  echo "[tf-ensure-init] backend cache mismatch (cached='$$CACHED', want='$(TF_STATE_KEY)'); reinitializing..."; \
	  $(MAKE) --no-print-directory tf-reinit DEVBOX_USER=$(DEVBOX_USER) TF_BIN=$(TF_BIN); \
	fi

tf-init:
	@[ -n "$(TF_STATE_BUCKET)" ] && [ "$(TF_STATE_BUCKET)" != "devimage-tfstate-" ] || { \
	  echo "ERROR: could not resolve AWS account ID via 'aws sts get-caller-identity'." >&2; \
	  echo "       Check your AWS credentials/profile, or override TF_STATE_BUCKET=... explicitly." >&2; \
	  exit 1; }
	cd terraform && $(TF_BIN) init $(TF_BACKEND_ARGS)

tf-reinit:
	cd terraform && $(TF_BIN) init -reconfigure $(TF_BACKEND_ARGS)

tf-plan: tf-ensure-init
	cd terraform && $(TF_BIN) plan $(TF_VAR_ARGS)

tf-apply: tf-ensure-init
	cd terraform && $(TF_BIN) apply $(TF_VAR_ARGS)

tf-auto-apply: tf-ensure-init
	cd terraform && $(TF_BIN) apply -auto-approve $(TF_VAR_ARGS)

tf-destroy: tf-ensure-init
	cd terraform && $(TF_BIN) destroy $(TF_VAR_ARGS)

tf-auto-destroy: tf-ensure-init
	cd terraform && $(TF_BIN) destroy -auto-approve $(TF_VAR_ARGS)

# --- Instance lifecycle ---
#
# Override INSTANCE_ID / REGION to bypass `tofu output` resolution:
#   make status INSTANCE_ID=i-0abc123 REGION=us-east-1
# (Useful before first apply, or when state is unavailable.)

INSTANCE_ID ?=
REGION ?=

start: tf-ensure-init
	DEVBOX_USER=$(DEVBOX_USER) INSTANCE_ID=$(INSTANCE_ID) REGION=$(REGION) ./scripts/devbox-start.sh

stop: tf-ensure-init
	DEVBOX_USER=$(DEVBOX_USER) INSTANCE_ID=$(INSTANCE_ID) REGION=$(REGION) ./scripts/devbox-stop.sh

status: tf-ensure-init
	DEVBOX_USER=$(DEVBOX_USER) INSTANCE_ID=$(INSTANCE_ID) REGION=$(REGION) ./scripts/devbox-status.sh

# --- SSM access (Phase 2) ---

devbox-ssm: tf-ensure-init
	DEVBOX_USER=$(DEVBOX_USER) INSTANCE_ID=$(INSTANCE_ID) REGION=$(REGION) ./scripts/devbox-ssm.sh

# Forwards :8080 (code-server) only. For :6080 (noVNC), either add your IP to
# allowed_web_cidrs (make devbox-allowlist-me) or run a second port-forward
# session manually with portNumber=6080.
devbox-port-forward:
	@set -euo pipefail; \
	command -v session-manager-plugin >/dev/null 2>&1 || { \
	  echo "ERROR: session-manager-plugin not installed. brew install --cask session-manager-plugin" >&2; \
	  exit 1; \
	}; \
	INSTANCE_ID=$$(cd terraform && $(TF_BIN) output -raw instance_id); \
	REGION=$$(cd terraform && $(TF_BIN) output -raw aws_region); \
	echo "Forwarding :8080 from $$INSTANCE_ID to localhost..."; \
	echo "Browse to https://localhost:8080 (code-server)."; \
	echo "For noVNC :6080, run 'make devbox-allowlist-me' or open a second forwarding session."; \
	echo "Ctrl-C to stop forwarding."; \
	exec aws ssm start-session \
	  --target "$$INSTANCE_ID" \
	  --region "$$REGION" \
	  --document-name AWS-StartPortForwardingSession \
	  --parameters '{"portNumber":["8080"],"localPortNumber":["8080"]}'

devbox-allowlist-me:
	@./scripts/devbox-allowlist-me.sh

# --- Secrets (per-user, SSM Parameter Store) ---

secrets-show:
	@set -euo pipefail; \
	echo "Resolving secrets for DEVBOX_USER=$(DEVBOX_USER)..."; \
	cs_pwd=$$(aws ssm get-parameter \
	    --name "/devbox/$(DEVBOX_USER)/code-server-password" \
	    --with-decryption --query 'Parameter.Value' --output text 2>/dev/null) \
	  || { echo "ERROR: code-server password not found at /devbox/$(DEVBOX_USER)/code-server-password" >&2; \
	       echo "       Run 'make packer-bake' first to publish secrets to SSM, or check your DEVBOX_USER." >&2; \
	       exit 1; }; \
	vnc_pwd=$$(aws ssm get-parameter \
	    --name "/devbox/$(DEVBOX_USER)/vnc-password" \
	    --with-decryption --query 'Parameter.Value' --output text 2>/dev/null) \
	  || { echo "ERROR: VNC password not found at /devbox/$(DEVBOX_USER)/vnc-password" >&2; exit 1; }; \
	echo ""; \
	echo "code-server (https://<host>:8080) password:  $$cs_pwd"; \
	echo "VNC / noVNC  (https://<host>:6080) password:  $$vnc_pwd"; \
	echo ""; \
	echo "(Secrets are stored as SSM SecureStrings; rotated on every \`make packer-bake\`.)"

# --- Cleanup ---

clean:
	rm -rf packer/packer_cache
	rm -f packer/packer-manifest.json
	rm -rf terraform/.terraform
	rm -f users/*.auto.tfvars
