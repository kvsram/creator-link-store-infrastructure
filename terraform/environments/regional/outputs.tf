output "infrastructure_release" {
  value = aws_ssm_parameter.infrastructure_release.value
}

output "cluster_name" {
  value = module.region.cluster_name
}

output "frontend_ecr_url" {
  value = aws_ecr_repository.frontend.repository_url
}

output "backend_ecr_url" {
  value = aws_ecr_repository.backend.repository_url
}

output "database_endpoint" {
  value = aws_db_instance.application.address
}

output "database_master_secret_arn" {
  value     = aws_db_instance.application.master_user_secret[0].secret_arn
  sensitive = true
}
