data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

locals {
  name       = "${var.project}-${var.test_id}"
  azs        = slice(data.aws_availability_zones.available.names, 0, 2)
  primary_az = local.azs[0]
  tags = {
    Project               = var.project
    Environment           = "ephemeral-test"
    TestId                = var.test_id
    Owner                 = "kvsram"
    ExpiresAt             = var.expires_at
    ManagedBy             = "Terraform"
    InfrastructureRelease = var.infrastructure_release
  }
}

resource "terraform_data" "expiration_guard" {
  input = var.expires_at

  lifecycle {
    precondition {
      condition     = timecmp(var.expires_at, plantimestamp()) > 0
      error_message = "expires_at must be in the future."
    }
    precondition {
      condition     = timecmp(var.expires_at, timeadd(plantimestamp(), "168h")) <= 0
      error_message = "The ephemeral stack must expire within seven days of this plan."
    }
  }
}

resource "terraform_data" "account_guard" {
  input = data.aws_caller_identity.current.account_id

  lifecycle {
    precondition {
      condition     = data.aws_caller_identity.current.account_id == var.expected_account_id
      error_message = "Refusing to create the disposable stack in an unexpected AWS account."
    }
    precondition {
      condition     = data.aws_caller_identity.current.arn != "arn:aws:iam::${var.expected_account_id}:root"
      error_message = "Refusing to create the disposable stack with AWS root credentials; assume a non-root administrator role."
    }
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.17.0"

  name = local.name
  cidr = var.vpc_cidr
  azs  = local.azs

  public_subnets  = [for index in range(2) : cidrsubnet(var.vpc_cidr, 4, index)]
  private_subnets = [for index in range(2) : cidrsubnet(var.vpc_cidr, 4, index + 8)]

  map_public_ip_on_launch = true
  enable_nat_gateway      = false

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  depends_on = [terraform_data.account_guard, terraform_data.expiration_guard]
}

module "ebs_csi_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.48.0"

  role_name             = "${local.name}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.31.6"

  cluster_name    = local.name
  cluster_version = var.cluster_version

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = concat(module.vpc.public_subnets, module.vpc.private_subnets)
  control_plane_subnet_ids = module.vpc.private_subnets

  cluster_endpoint_private_access      = true
  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = var.cluster_public_access_cidrs

  enable_cluster_creator_admin_permissions = false
  create_cloudwatch_log_group              = false
  cluster_enabled_log_types                = []
  cluster_encryption_config                = {}
  create_kms_key                           = false

  access_entries = {
    operator = {
      principal_arn = var.operator_role_arn
      type          = "STANDARD"

      policy_associations = {
        cluster_admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  cluster_addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_irsa_role.iam_role_arn
    }
  }

  eks_managed_node_groups = {
    test = {
      subnet_ids     = [module.vpc.public_subnets[0]]
      instance_types = [var.node_instance_type]
      capacity_type  = "ON_DEMAND"
      min_size       = 1
      max_size       = 1
      desired_size   = 1
      disk_size      = 30

      credit_specification = {
        cpu_credits = "standard"
      }
    }
  }

  node_security_group_additional_rules = {
    temporary_storefront = {
      description = "Temporary creator-store test access"
      protocol    = "tcp"
      from_port   = var.public_node_port
      to_port     = var.public_node_port
      type        = "ingress"
      cidr_blocks = var.tester_cidrs
    }
  }

  tags = local.tags
}

resource "aws_security_group" "database" {
  name        = "${local.name}-database"
  description = "Private PostgreSQL access from the disposable EKS worker"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "database_from_eks" {
  security_group_id            = aws_security_group.database.id
  referenced_security_group_id = module.eks.node_security_group_id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

resource "aws_db_subnet_group" "application" {
  name       = local.name
  subnet_ids = module.vpc.private_subnets
}

resource "aws_db_parameter_group" "application" {
  name   = local.name
  family = "postgres16"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }
}

resource "random_password" "database" {
  length  = 32
  special = false
}

resource "aws_db_instance" "application" {
  identifier = local.name

  engine         = "postgres"
  engine_version = "16"
  instance_class = var.database_instance_class

  allocated_storage     = 20
  max_allocated_storage = 0
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = "creatorstore"
  username = "creator_admin"
  password = random_password.database.result
  port     = 5432

  db_subnet_group_name   = aws_db_subnet_group.application.name
  parameter_group_name   = aws_db_parameter_group.application.name
  vpc_security_group_ids = [aws_security_group.database.id]
  availability_zone      = local.primary_az
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period    = 1
  delete_automated_backups   = true
  deletion_protection        = false
  skip_final_snapshot        = true
  auto_minor_version_upgrade = true
  apply_immediately          = true

  performance_insights_enabled    = false
  enabled_cloudwatch_logs_exports = []
}

locals {
  parameter_prefix = "/${var.project}/ephemeral/${var.test_id}"
  database_url     = "jdbc:postgresql://${aws_db_instance.application.address}:5432/creatorstore?sslmode=require"
}

resource "aws_ssm_parameter" "cluster_name" {
  name  = "${local.parameter_prefix}/eks-cluster-name"
  type  = "String"
  tier  = "Standard"
  value = module.eks.cluster_name
}

resource "aws_ssm_parameter" "database_url" {
  name  = "${local.parameter_prefix}/database-url"
  type  = "String"
  tier  = "Standard"
  value = local.database_url
}

resource "aws_ssm_parameter" "database_username" {
  name  = "${local.parameter_prefix}/database-username"
  type  = "String"
  tier  = "Standard"
  value = aws_db_instance.application.username
}

resource "aws_ssm_parameter" "database_password" {
  name  = "${local.parameter_prefix}/database-password"
  type  = "SecureString"
  tier  = "Standard"
  value = random_password.database.result
}

resource "aws_ssm_parameter" "infrastructure_release" {
  name  = "${local.parameter_prefix}/infrastructure-release"
  type  = "String"
  tier  = "Standard"
  value = var.infrastructure_release
}

resource "aws_ssm_parameter" "expires_at" {
  name  = "${local.parameter_prefix}/expires-at"
  type  = "String"
  tier  = "Standard"
  value = var.expires_at
}
