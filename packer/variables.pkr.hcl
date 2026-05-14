variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region to build the AMI in"
}

variable "instance_type" {
  type        = string
  default     = "t3.medium"
  description = "EC2 instance type used during the build process"
}

variable "ami_name_prefix" {
  type        = string
  default     = "devimage"
  description = "Prefix for the resulting AMI name"
}

variable "vpc_id" {
  type        = string
  default     = ""
  description = "VPC ID to launch the build instance in (empty = default VPC)"
}

variable "subnet_id" {
  type        = string
  default     = ""
  description = "Subnet ID to launch the build instance in (empty = default)"
}

variable "volume_size" {
  type        = number
  default     = 50
  description = "Root EBS volume size in GB"
}

variable "extra_tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags to apply to the AMI"
}

# Phase 1 (SEC-03): keys SSM parameter paths /devbox/<user>/* for boot-time secret fetch.
# Phase 3 (REP-05): recorded in packer-manifest.json `custom_data` so the AMI handoff
# (manifest → users/${devbox_user}.auto.tfvars) preserves operator-of-record alongside artifact_id.
variable "devbox_user" {
  type        = string
  default     = ""
  description = "Operator username; keys SSM parameter paths /devbox/<user>/* and recorded in packer-manifest custom_data for the AMI handoff. Required."
  validation {
    # Allow empty (so `packer validate` works without `-var "devbox_user=..."` for CI gates);
    # Make targets always pass a real value, where the regex applies.
    condition     = var.devbox_user == "" || can(regex("^[a-z_][a-z0-9_-]*$", var.devbox_user))
    error_message = "The devbox_user value must match the regex ^[a-z_][a-z0-9_-]*$ (lowercase letter or underscore followed by lowercase alphanumerics/dashes/underscores)."
  }
}
