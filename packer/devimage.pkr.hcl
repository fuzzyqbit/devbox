packer {
  required_plugins {
    amazon = {
      version = ">= 1.3.0"
      source  = "github.com/hashicorp/amazon"
    }
    ansible = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

locals {
  timestamp = formatdate("YYYYMMDDhhmmss", timestamp())
  ami_name  = "${var.ami_name_prefix}-al2023-${local.timestamp}"
}

# REP-04: pin the source AMI to an AWS-managed SSM Parameter Store entry instead
# of a floating glob filter with `most_recent` enabled. Ideally the literal `name`
# below carries a trailing `:NN` parameter-version suffix (Pattern 4 in
# .planning/phases/03-reproducibility-version-pinning/03-RESEARCH.md:256-290) so
# the resolution is fully deterministic across days. The version pin is currently
# OMITTED — the executor that landed this change did not have AWS credentials to
# resolve the live parameter version. Pin the trailing `:NN` BEFORE running any
# real `packer build` for reproducibility:
#   aws ssm get-parameter-history \
#     --name /aws/service/ami-amazon-linux-latest/al2023-ami-minimal-kernel-default-x86_64 \
#     --region us-east-1 \
#     --query 'Parameters[-1].{Version: Version, LastModifiedDate: LastModifiedDate}'
# Then edit the `name` below to append `:NN` where NN is the integer Version field.
data "amazon-parameterstore" "al2023_minimal" {
  name   = "/aws/service/ami-amazon-linux-latest/al2023-ami-minimal-kernel-default-x86_64"
  region = var.aws_region
}

source "amazon-ebs" "al2023" {
  ami_name      = local.ami_name
  instance_type = var.instance_type
  region        = var.aws_region

  vpc_id    = var.vpc_id != "" ? var.vpc_id : null
  subnet_id = var.subnet_id != "" ? var.subnet_id : null

  source_ami = data.amazon-parameterstore.al2023_minimal.value

  ssh_username = "ec2-user"

  launch_block_device_mappings {
    device_name           = "/dev/xvda"
    volume_size           = var.volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = merge(
    {
      Name      = local.ami_name
      Builder   = "packer"
      BaseOS    = "al2023"
      BuildTime = local.timestamp
    },
    var.extra_tags
  )
}

build {
  sources = ["source.amazon-ebs.al2023"]

  provisioner "ansible" {
    playbook_file = "${path.root}/../ansible/playbook.yml"
    galaxy_file   = "${path.root}/../ansible/requirements.yml"
    extra_arguments = [
      "--extra-vars", "@${path.root}/../ansible/layer_config.yml"
    ]
    ansible_env_vars = [
      "ANSIBLE_HOST_KEY_CHECKING=False",
      "ANSIBLE_SSH_TRANSFER_METHOD=piped",
      "ANSIBLE_SSH_ARGS=-o ForwardAgent=yes -o ControlMaster=auto -o ControlPersist=60s"
    ]
    user = "ec2-user"
  }

  # REP-05: emit packer-manifest.json after each build. `make packer-bake` parses
  # this file with `jq` to extract the built AMI ID and writes it into
  # users/${DEVBOX_USER}.auto.tfvars (Terraform auto-loaded). See Pattern 5 in
  # .planning/phases/03-reproducibility-version-pinning/03-RESEARCH.md:292-346.
  post-processor "manifest" {
    output     = "${path.root}/packer-manifest.json"
    strip_path = true
    custom_data = {
      devbox_user = var.devbox_user
      base_ami_id = data.amazon-parameterstore.al2023_minimal.value
    }
  }
}
