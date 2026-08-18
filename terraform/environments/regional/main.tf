locals {
  name = "${var.project}-${var.environment}-${var.region_key}"
  tags = {
    Project     = var.project
    Environment = var.environment
    RegionKey   = var.region_key
    ManagedBy   = "Terraform"
  }
}

module "region" {
  source              = "../../modules/region"
  name                = local.name
  region_key          = var.region_key
  vpc_cidr            = var.vpc_cidr
  cluster_version     = var.cluster_version
  node_instance_types = var.node_instance_types
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
  node_desired_size   = var.node_desired_size
  tags                = local.tags
}

resource "aws_ecr_repository" "frontend" {
  name                 = "${var.project}-${var.environment}-frontend"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration { scan_on_push = true }
}

resource "aws_ecr_repository" "backend" {
  name                 = "${var.project}-${var.environment}-backend"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration { scan_on_push = true }
}

resource "aws_ecr_lifecycle_policy" "frontend" {
  repository = aws_ecr_repository.frontend.name
  policy     = jsonencode({ rules = [{ rulePriority = 1, description = "Keep 30 immutable images", selection = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 30 }, action = { type = "expire" } }] })
}

resource "aws_ecr_lifecycle_policy" "backend" {
  repository = aws_ecr_repository.backend.name
  policy     = jsonencode({ rules = [{ rulePriority = 1, description = "Keep 30 immutable images", selection = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 30 }, action = { type = "expire" } }] })
}

resource "aws_db_subnet_group" "application" {
  name       = local.name
  subnet_ids = module.region.private_subnet_ids
}

resource "aws_security_group" "database" {
  name        = "${local.name}-database"
  description = "PostgreSQL access from EKS worker nodes"
  vpc_id      = module.region.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "database_from_eks" {
  security_group_id            = aws_security_group.database.id
  referenced_security_group_id = module.region.node_security_group_id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "database_egress" {
  security_group_id = aws_security_group.database.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_db_instance" "application" {
  identifier                      = local.name
  engine                          = "postgres"
  engine_version                  = "16"
  instance_class                  = var.database_instance_class
  allocated_storage               = 20
  max_allocated_storage           = 100
  storage_type                    = "gp3"
  storage_encrypted               = true
  db_name                         = "creatorstore"
  username                        = "creator_admin"
  manage_master_user_password     = true
  db_subnet_group_name            = aws_db_subnet_group.application.name
  vpc_security_group_ids          = [aws_security_group.database.id]
  publicly_accessible             = false
  multi_az                        = var.environment == "prod" ? true : var.database_multi_az
  backup_retention_period         = var.environment == "prod" ? 14 : 3
  deletion_protection             = var.environment == "prod" ? true : var.database_deletion_protection
  skip_final_snapshot             = var.environment != "prod"
  final_snapshot_identifier       = "${local.name}-final"
  copy_tags_to_snapshot           = true
  auto_minor_version_upgrade      = true
  performance_insights_enabled    = var.environment != "dev"
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
}

module "observability" {
  source     = "../../modules/observability"
  name       = local.name
  canary_url = var.canary_url
  tags       = local.tags
}

resource "aws_ssm_parameter" "infrastructure_release" {
  name        = "/${var.project}/${var.environment}/infrastructure-release"
  description = "Immutable infrastructure repository commit currently applied"
  type        = "String"
  value       = var.infrastructure_release
  depends_on = [
    module.region,
    module.observability,
    aws_ecr_lifecycle_policy.frontend,
    aws_ecr_lifecycle_policy.backend,
    aws_db_instance.application,
    aws_ssm_parameter.cluster_name,
    aws_ssm_parameter.database_endpoint,
    aws_ssm_parameter.database_master_secret_arn,
    aws_ssm_parameter.frontend_ecr_url,
    aws_ssm_parameter.backend_ecr_url,
  ]
}

resource "aws_ssm_parameter" "cluster_name" {
  name  = "/${var.project}/${var.environment}/${var.region_key}/eks-cluster-name"
  type  = "String"
  value = module.region.cluster_name
}

resource "aws_ssm_parameter" "database_endpoint" {
  name  = "/${var.project}/${var.environment}/${var.region_key}/database-endpoint"
  type  = "String"
  value = aws_db_instance.application.address
}

resource "aws_ssm_parameter" "database_master_secret_arn" {
  name  = "/${var.project}/${var.environment}/${var.region_key}/database-master-secret-arn"
  type  = "String"
  value = aws_db_instance.application.master_user_secret[0].secret_arn
}

resource "aws_ssm_parameter" "frontend_ecr_url" {
  name  = "/${var.project}/${var.environment}/${var.region_key}/frontend-ecr-url"
  type  = "String"
  value = aws_ecr_repository.frontend.repository_url
}

resource "aws_ssm_parameter" "backend_ecr_url" {
  name  = "/${var.project}/${var.environment}/${var.region_key}/backend-ecr-url"
  type  = "String"
  value = aws_ecr_repository.backend.repository_url
}
