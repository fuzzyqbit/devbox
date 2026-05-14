variable "ami_id" {
  type        = string
  description = "AMI ID of the devimage to launch"
}

variable "instance_type" {
  type        = string
  default     = "t3.medium"
  description = "EC2 instance type"
}

variable "key_name" {
  type        = string
  description = "Name of the SSH key pair"
}

variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID to launch the instance in"
}

variable "subnet_id" {
  type        = string
  description = "Subnet ID to launch the instance in"
}


variable "root_volume_size" {
  type        = number
  default     = 50
  description = "Root EBS volume size in GB"
}

variable "instance_name" {
  type        = string
  default     = "devbox"
  description = "Base name for the instance (user will be prepended)"
}

variable "devbox_user" {
  type        = string
  description = "Username that owns this devbox (used for resource naming and tags)"
}

variable "associate_public_ip" {
  type        = bool
  default     = true
  description = "Whether to associate a public IP address"
}

variable "extra_tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags to apply to all resources"
}

variable "allowed_web_cidrs" {
  type        = list(string)
  default     = []
  description = "CIDR blocks permitted to reach code-server (:8080) and noVNC (:6080). Empty list refuses apply unless var.allow_open_ingress = true. Populate via `make devbox-allowlist-me` or set explicitly in an allowlist.auto.tfvars file. SSH (:22) ingress is intentionally absent — shell access is brokered by AWS SSM Session Manager."

  validation {
    condition     = length(var.allowed_web_cidrs) > 0 || var.allow_open_ingress
    error_message = "allowed_web_cidrs must contain at least one CIDR (e.g. 203.0.113.42/32). Run `make devbox-allowlist-me` to auto-populate your current public IP, or set the value explicitly in an allowlist.auto.tfvars file. To bypass this gate intentionally (NOT recommended), set var.allow_open_ingress = true."
  }

  validation {
    condition     = alltrue([for c in var.allowed_web_cidrs : can(cidrhost(c, 0))])
    error_message = "Each entry in allowed_web_cidrs must be a valid CIDR block (e.g. 203.0.113.42/32, 198.51.100.0/24). cidrhost() failed for at least one entry — check for a missing /XX suffix."
  }
}

variable "allow_open_ingress" {
  type        = bool
  default     = false
  description = "Escape hatch — when true, bypasses the non-empty validation on allowed_web_cidrs. Intended only for ephemeral exploration where the operator deliberately wants no public web ingress (empty list ⇒ no inbound :8080 / :6080 at all; SSM port forwarding becomes the only path — see RESEARCH.md Pattern 5 / Example 3). NEVER set this to true AND populate allowed_web_cidrs with 0.0.0.0/0 — that combination re-introduces the very finding Phase 2 closes."
}
