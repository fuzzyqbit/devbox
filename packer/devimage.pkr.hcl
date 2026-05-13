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

source "amazon-ebs" "al2023" {
  ami_name      = local.ami_name
  instance_type = var.instance_type
  region        = var.aws_region

  vpc_id    = var.vpc_id != "" ? var.vpc_id : null
  subnet_id = var.subnet_id != "" ? var.subnet_id : null

  source_ami_filter {
    filters = {
      name                = "al2023-ami-minimal-*-x86_64"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["amazon"]
  }

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
      "--extra-vars", "@${path.root}/../ansible/layer_config.yml",
      "--extra-vars", "devbox_user=${var.devbox_user}",
      "--extra-vars", "aws_region=${var.aws_region}",
    ]
    ansible_env_vars = [
      "ANSIBLE_HOST_KEY_CHECKING=False",
      "ANSIBLE_SSH_TRANSFER_METHOD=piped",
      "ANSIBLE_SSH_ARGS=-o ForwardAgent=yes -o ControlMaster=auto -o ControlPersist=60s"
    ]
    user = "ec2-user"
  }
}
