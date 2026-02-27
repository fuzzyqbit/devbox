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
