output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.devbox.id
}

output "private_ip" {
  description = "Private IP address. Devbox is private-only — reached over VPC-internal routes for code-server/RDP and via SSM Session Manager for shell."
  value       = aws_instance.devbox.private_ip
}

output "ssm_start_session_command" {
  description = "Operator shell access via SSM Session Manager. Run `./run devbox-ssm` for the same effect (it also pre-flights session-manager-plugin)."
  value       = "aws ssm start-session --target ${aws_instance.devbox.id} --region ${data.aws_region.current.region}"
}

output "code_server_url" {
  description = "code-server URL (private IP — reach over VPC peering / Direct Connect / VPN, or use `./run devbox-port-forward`)"
  value       = "https://${aws_instance.devbox.private_ip}:8080"
}

output "rdp_endpoint" {
  description = "RDP desktop endpoint (xrdp/TLS :3389) — native RDP client only; not a browser URL"
  value       = "${aws_instance.devbox.private_ip}:3389 — connect with a native RDP client (mstsc / FreeRDP / Remmina), or `./run devbox-port-forward 3389` then localhost:3389"
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

output "ssm_desktop_password_param" {
  description = "SSM Parameter Store name for the RDP/desktop login password (the ec2-user PAM password)"
  value       = "/devbox/${var.devbox_user}/desktop-password"
}

output "aws_region" {
  description = "AWS region the instance is deployed in"
  value       = var.aws_region
}

output "devbox_user" {
  description = "Username that owns this devbox"
  value       = var.devbox_user
}
