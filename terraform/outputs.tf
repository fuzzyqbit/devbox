output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.devbox.id
}

output "private_ip" {
  description = "Private IP address. Devbox is private-only — reached over VPC-internal routes for code-server/DCV and via SSM Session Manager for shell."
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

output "dcv_endpoint" {
  description = "Amazon DCV endpoint (TLS :8443, TCP+UDP/QUIC) — direct connect within var.allowed_web_cidrs; browser web client or native DCV client"
  value       = "https://${aws_instance.devbox.private_ip}:8443 — Amazon DCV web client (browser) or native DCV client, within the allowed CIDR"
}

output "security_group_id" {
  description = "Security group ID"
  value       = aws_security_group.devbox.id
}

output "home_volume_id" {
  description = "Persistent /home EBS volume ID (survives AMI swaps + tofu destroy; snapshotted daily by DLM). Use for manual snapshot/restore ops."
  value       = aws_ebs_volume.home.id
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
  description = "SSM Parameter Store name for the DCV/desktop login password (the ec2-user PAM password)"
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

output "runner_iam_enabled" {
  description = "Whether the shared GitLab-runner IAM variant is attached (org permissions boundary on the instance role + explicit S3/EC2/caged-IAM policy)"
  value       = var.enable_runner_iam
}
