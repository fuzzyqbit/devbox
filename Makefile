.PHONY: help validate build fmt clean init start stop status secrets-show tf-init tf-plan tf-apply tf-destroy tg-init tg-reinit tg-plan tg-apply tg-auto-apply tg-destroy tg-auto-destroy

# User detection: override with  make <target> DEVBOX_USER=jsmith
DEVBOX_USER ?= $(shell whoami)

help:
	@echo "Usage: make <target> [DEVBOX_USER=username]"
	@echo ""
	@echo "AMI"
	@echo "  init         Install Packer plugins"
	@echo "  validate     Validate Packer and Terraform configs"
	@echo "  build        Build the devimage AMI with Packer"
	@echo "  fmt          Format Packer, Terraform, and Terragrunt files"
	@echo ""
	@echo "Terragrunt (default — auto-creates S3 backend + DynamoDB locks)"
	@echo "  tg-init          Init backend for DEVBOX_USER (first-time setup)"
	@echo "  tg-reinit        Re-init with -reconfigure (after backend changes)"
	@echo "  tg-plan          Plan changes for DEVBOX_USER"
	@echo "  tg-apply         Apply with confirmation prompt"
	@echo "  tg-auto-apply    Apply without prompt"
	@echo "  tg-destroy       Destroy with confirmation prompt"
	@echo "  tg-auto-destroy  Destroy without prompt"
	@echo ""
	@echo "Instance lifecycle"
	@echo "  start        Start the devbox EC2 instance"
	@echo "  stop         Stop the devbox EC2 instance"
	@echo "  status       Show instance status and connection info"
	@echo ""
	@echo "Secrets"
	@echo "  secrets-show   Print the operator's code-server and VNC passwords from SSM"
	@echo ""
	@echo "Cleanup"
	@echo "  clean        Remove Packer cache and Terraform local state"

# --- Packer ---

init:
	cd packer && packer init .

validate: init
	cd packer && packer validate .
	DEVBOX_USER=$(DEVBOX_USER) terragrunt validate

build: init
	cd packer && packer build .

fmt:
	cd packer && packer fmt .
	cd terraform && terraform fmt
	terragrunt hclfmt
	@echo "Format complete"

# --- Terragrunt (user-scoped via DEVBOX_USER, auto-creates S3 backend) ---

tg-init:
	DEVBOX_USER=$(DEVBOX_USER) terragrunt init

tg-reinit:
	DEVBOX_USER=$(DEVBOX_USER) terragrunt init -reconfigure

tg-plan:
	DEVBOX_USER=$(DEVBOX_USER) terragrunt plan

tg-apply:
	DEVBOX_USER=$(DEVBOX_USER) terragrunt apply

tg-auto-apply:
	DEVBOX_USER=$(DEVBOX_USER) terragrunt apply -auto-approve

tg-destroy:
	DEVBOX_USER=$(DEVBOX_USER) terragrunt destroy

tg-auto-destroy:
	DEVBOX_USER=$(DEVBOX_USER) terragrunt destroy -auto-approve

# --- Terraform direct (legacy, user-scoped via workspaces) ---

tf-init:
	cd terraform && terraform init

tf-workspace:
	@cd terraform && \
		(terraform workspace select $(DEVBOX_USER) 2>/dev/null || \
		 terraform workspace new $(DEVBOX_USER))

tf-plan: tf-workspace
	cd terraform && terraform plan -var="devbox_user=$(DEVBOX_USER)"

tf-apply: tf-workspace
	cd terraform && terraform apply -var="devbox_user=$(DEVBOX_USER)"

tf-destroy: tf-workspace
	cd terraform && terraform destroy -var="devbox_user=$(DEVBOX_USER)"

# --- Instance lifecycle ---

start:
	DEVBOX_USER=$(DEVBOX_USER) ./scripts/devbox-start.sh

stop:
	DEVBOX_USER=$(DEVBOX_USER) ./scripts/devbox-stop.sh

status:
	DEVBOX_USER=$(DEVBOX_USER) ./scripts/devbox-status.sh

# --- Secrets (per-user, SSM Parameter Store) ---

secrets-show:
	@set -euo pipefail; \
	echo "Resolving secrets for DEVBOX_USER=$(DEVBOX_USER)..."; \
	cs_pwd=$$(aws ssm get-parameter \
	    --name "/devbox/$(DEVBOX_USER)/code-server-password" \
	    --with-decryption --query 'Parameter.Value' --output text 2>/dev/null) \
	  || { echo "ERROR: code-server password not found at /devbox/$(DEVBOX_USER)/code-server-password" >&2; \
	       echo "       Run 'make build' first to publish secrets to SSM, or check your DEVBOX_USER." >&2; \
	       exit 1; }; \
	vnc_pwd=$$(aws ssm get-parameter \
	    --name "/devbox/$(DEVBOX_USER)/vnc-password" \
	    --with-decryption --query 'Parameter.Value' --output text 2>/dev/null) \
	  || { echo "ERROR: VNC password not found at /devbox/$(DEVBOX_USER)/vnc-password" >&2; exit 1; }; \
	echo ""; \
	echo "code-server (https://<host>:8080) password:  $$cs_pwd"; \
	echo "VNC / noVNC  (https://<host>:6080) password:  $$vnc_pwd"; \
	echo ""; \
	echo "(Secrets are stored as SSM SecureStrings; rotated on every \`make build\`.)"

# --- Cleanup ---

clean:
	rm -rf packer/packer_cache
	rm -rf terraform/.terraform terraform/.terraform.lock.hcl
