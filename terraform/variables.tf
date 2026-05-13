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
