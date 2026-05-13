output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.devbox.id
}

output "public_ip" {
  description = "Public IP address"
  value       = aws_instance.devbox.public_ip
}

output "private_ip" {
  description = "Private IP address"
  value       = aws_instance.devbox.private_ip
}

output "ssh_command" {
  description = "SSH command to connect"
  value       = "ssh -i ~/.ssh/${var.key_name}.pem ec2-user@${aws_instance.devbox.public_ip}"
}

output "code_server_url" {
  description = "code-server URL"
  value       = "https://${aws_instance.devbox.public_ip}:8080"
}

output "novnc_url" {
  description = "noVNC remote desktop URL"
  value       = "https://${aws_instance.devbox.public_ip}:6080"
}

output "security_group_id" {
  description = "Security group ID"
  value       = aws_security_group.devbox.id
}

output "iam_instance_profile" {
  description = "IAM instance profile attached to the instance"
  value       = aws_iam_instance_profile.devbox.name
}

output "ssm_code_server_password_param" {
  description = "SSM Parameter Store name for the code-server password"
  value       = "/devbox/${var.devbox_user}/code-server-password"
}

output "ssm_vnc_password_param" {
  description = "SSM Parameter Store name for the VNC password"
  value       = "/devbox/${var.devbox_user}/vnc-password"
}

output "aws_region" {
  description = "AWS region the instance is deployed in"
  value       = var.aws_region
}

output "devbox_user" {
  description = "Username that owns this devbox"
  value       = var.devbox_user
}
