output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.devbox.id
}

output "private_ip" {
  description = "Private IP address. Devbox is private-only — reached over VPC-internal routes for code-server/noVNC and via SSM Session Manager for shell."
  value       = aws_instance.devbox.private_ip
}

output "ssm_start_session_command" {
  description = "Operator shell access via SSM Session Manager. Run `make devbox-ssm` for the same effect (it also pre-flights session-manager-plugin)."
  value       = "aws ssm start-session --target ${aws_instance.devbox.id} --region ${data.aws_region.current.region}"
}

output "code_server_url" {
  description = "code-server URL (private IP — reach over VPC peering / Direct Connect / VPN, or use `make devbox-port-forward`)"
  value       = "https://${aws_instance.devbox.private_ip}:8080"
}

output "novnc_url" {
  description = "noVNC remote desktop URL (private IP — reach over VPC peering / Direct Connect / VPN, or use SSM port forwarding with portNumber=6080)"
  value       = "https://${aws_instance.devbox.private_ip}:6080"
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
