terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

locals {
  name_prefix = "${var.devbox_user}-${var.instance_name}"
  common_tags = merge(
    {
      Project    = "devimage"
      ManagedBy  = "terraform"
      DevboxUser = var.devbox_user
    },
    var.extra_tags
  )
}

# --- Security Group ---

resource "aws_security_group" "devbox" {
  name_prefix = "${local.name_prefix}-"
  description = "Security group for devimage instance"
  vpc_id      = var.vpc_id

  # SSH
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # code-server (HTTPS)
  ingress {
    description = "code-server"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # noVNC (HTTPS)
  ingress {
    description = "noVNC"
    from_port   = 6080
    to_port     = 6080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# --- EC2 Instance ---

resource "aws_instance" "devbox" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.devbox.id]
  iam_instance_profile        = var.iam_instance_profile
  associate_public_ip_address = var.associate_public_ip

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = merge(local.common_tags, {
    Name = local.name_prefix
  })
}
