output "aws_account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "region" {
  value = var.region
}

output "k3s_instance_id" {
  value = aws_instance.k3s.id
}

output "k3s_version" {
  value = var.k3s_version
}

output "public_ip" {
  value = aws_eip.k3s.public_ip
}

output "public_origin" {
  value = local.public_origin
}

output "database_endpoint" {
  value = aws_db_instance.application.address
}

output "parameter_prefix" {
  value = local.parameter_prefix
}

output "public_http_port" {
  value = var.public_http_port
}

output "public_http_access_mode" {
  description = "Whether port 80 uses the secure-default tester allowlist or explicit public IPv4 access."
  value       = var.enable_public_http ? "public-ipv4" : "tester-allowlist"
}

output "expires_at" {
  value = var.expires_at
}

output "ssm_start_session_command" {
  value = "aws ssm start-session --region ${var.region} --target ${aws_instance.k3s.id}"
}
