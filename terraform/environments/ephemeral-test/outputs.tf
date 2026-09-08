output "aws_account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "region" {
  value = var.region
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "database_endpoint" {
  value = aws_db_instance.application.address
}

output "parameter_prefix" {
  value = local.parameter_prefix
}

output "public_node_port" {
  value = var.public_node_port
}

output "expires_at" {
  value = var.expires_at
}

output "find_public_url_command" {
  value = "aws ec2 describe-instances --region ${var.region} --filters Name=tag:eks:cluster-name,Values=${module.eks.cluster_name} Name=instance-state-name,Values=running --query 'Reservations[0].Instances[0].PublicIpAddress' --output text"
}
