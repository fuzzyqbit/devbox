terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
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
          "ssm:GetParametersByPath",
        ]
        Resource = "arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter/devbox/${var.devbox_user}/*"
      },
      {
        Sid      = "DecryptSecureStrings"
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "ssm.${data.aws_region.current.region}.amazonaws.com"
          }
        }
      },
    ]
  })
}

resource "aws_iam_instance_profile" "devbox" {
  name_prefix = "${local.name_prefix}-"
  role        = aws_iam_role.devbox.name
  tags        = local.common_tags
}

# --- SSM Session Manager: attach the AWS-managed core policy to the Phase 1 role ---
# Enables `aws ssm start-session` to reach this instance. The agent (amazon-ssm-agent)
# is preinstalled in AL2023 and only needs this managed policy to come Online.
# See .planning/phases/02-network-exposure-remediation/02-RESEARCH.md:71 (managed policy ARN)
# and Pattern 2 at 02-RESEARCH.md:220-233.
resource "aws_iam_role_policy_attachment" "devbox_ssm_core" {
  role       = aws_iam_role.devbox.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# --- Security Group ---

# SSH (:22) ingress intentionally absent. Shell access is brokered by AWS SSM
# Session Manager — see PROJECT.md Key Decisions (NET-04) and
# .planning/phases/02-network-exposure-remediation/02-RESEARCH.md.
# Web ports (:8080, :6080) are gated by var.allowed_web_cidrs (default
# ["10.0.0.0/8"]). Operator-managed externally — supply via per-operator
# tfvars / `-var` / `TF_VAR_allowed_web_cidrs` and run `./run tf-apply`.

resource "aws_security_group" "devbox" {
  name_prefix = "${local.name_prefix}-"
  description = "Security group for devimage instance"
  vpc_id      = var.vpc_id

  ingress {
    description = "code-server (HTTPS) restricted to operator CIDR allowlist"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = var.allowed_web_cidrs
  }

  ingress {
    description = "noVNC (HTTPS) restricted to operator CIDR allowlist"
    from_port   = 6080
    to_port     = 6080
    protocol    = "tcp"
    cidr_blocks = var.allowed_web_cidrs
  }

  egress {
    description = "All outbound (required for SSM agent channels: ssmmessages, ec2messages, ssm)"
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
  iam_instance_profile        = aws_iam_instance_profile.devbox.name
  associate_public_ip_address = var.associate_public_ip

  metadata_options {
    http_tokens                 = "required" # IMDSv2-only; rejects IMDSv1
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled" # exposes DevboxUser tag via IMDS
  }

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = merge(local.common_tags, {
    Name = local.name_prefix
  })
}
