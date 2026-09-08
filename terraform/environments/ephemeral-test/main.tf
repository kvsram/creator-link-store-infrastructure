data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  name             = "${var.project}-${var.test_id}"
  azs              = slice(data.aws_availability_zones.available.names, 0, 2)
  primary_az       = local.azs[0]
  parameter_prefix = "/${var.project}/ephemeral/${var.test_id}"
  database_url     = "jdbc:postgresql://${aws_db_instance.application.address}:5432/creatorstore?sslmode=require"
  public_origin    = "http://${aws_eip.k3s.public_ip}:${var.public_node_port}"
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

  # The K3s host needs direct package/image egress. PostgreSQL remains private
  # and its subnet group spans two AZs as required by RDS.
  public_subnets  = [cidrsubnet(var.vpc_cidr, 4, 0)]
  private_subnets = [for index in range(2) : cidrsubnet(var.vpc_cidr, 4, index + 8)]

  map_public_ip_on_launch = true
  enable_nat_gateway      = false
  single_nat_gateway      = false

  tags = local.tags

  depends_on = [terraform_data.account_guard, terraform_data.expiration_guard]
}

resource "aws_security_group" "k3s" {
  name        = "${local.name}-k3s"
  description = "K3s node; public storefront only, with no SSH or API ingress"
  vpc_id      = module.vpc.vpc_id

  tags = merge(local.tags, { Role = "k3s-server" })
}

resource "aws_vpc_security_group_ingress_rule" "storefront" {
  for_each = toset(var.tester_cidrs)

  security_group_id = aws_security_group.k3s.id
  description       = "Temporary storefront access from ${each.value}"
  cidr_ipv4         = each.value
  from_port         = var.public_node_port
  to_port           = var.public_node_port
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "k3s_http" {
  security_group_id = aws_security_group.k3s.id
  description       = "Bootstrap package redirects"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "k3s_https" {
  security_group_id = aws_security_group.k3s.id
  description       = "AWS APIs, packages, and container registries"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "k3s_dns_udp" {
  security_group_id = aws_security_group.k3s.id
  description       = "VPC DNS over UDP"
  cidr_ipv4         = "${cidrhost(var.vpc_cidr, 2)}/32"
  from_port         = 53
  to_port           = 53
  ip_protocol       = "udp"
}

resource "aws_vpc_security_group_egress_rule" "k3s_dns_tcp" {
  security_group_id = aws_security_group.k3s.id
  description       = "VPC DNS over TCP"
  cidr_ipv4         = "${cidrhost(var.vpc_cidr, 2)}/32"
  from_port         = 53
  to_port           = 53
  ip_protocol       = "tcp"
}

resource "aws_security_group" "database" {
  name        = "${local.name}-database"
  description = "Private PostgreSQL access from the single K3s node"
  vpc_id      = module.vpc.vpc_id

  tags = merge(local.tags, { Role = "database" })
}

resource "aws_vpc_security_group_ingress_rule" "database_from_k3s" {
  security_group_id            = aws_security_group.database.id
  referenced_security_group_id = aws_security_group.k3s.id
  description                  = "PostgreSQL from the K3s node only"
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "k3s_database" {
  security_group_id            = aws_security_group.k3s.id
  referenced_security_group_id = aws_security_group.database.id
  description                  = "Application access to private PostgreSQL"
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

resource "aws_iam_role" "k3s" {
  name = "${local.name}-k3s"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = merge(local.tags, { Role = "k3s-server" })
}

resource "aws_iam_role_policy" "k3s" {
  name = "${local.name}-k3s"
  role = aws_iam_role.k3s.id

  # This intentionally avoids AmazonSSMManagedInstanceCore because that managed
  # policy grants ssm:GetParameter(s) on every parameter in the account.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableAccessViaSSM"
        Effect = "Allow"
        Action = [
          "ssmmessages:OpenDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:CreateControlChannel",
          "ssm:UpdateInstanceInformation"
        ]
        Resource = "*"
      },
      {
        Sid    = "EnableSSMRunCommand"
        Effect = "Allow"
        Action = [
          "ec2messages:SendReply",
          "ec2messages:GetMessages",
          "ec2messages:GetEndpoint",
          "ec2messages:FailMessage",
          "ec2messages:DeleteMessage",
          "ec2messages:AcknowledgeMessage"
        ]
        Resource = "*"
      },
      {
        Sid    = "ReadOnlyThisTestConfiguration"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = "arn:${data.aws_partition.current.partition}:ssm:${var.region}:${var.expected_account_id}:parameter${local.parameter_prefix}/*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "k3s" {
  name = "${local.name}-k3s"
  role = aws_iam_role.k3s.name

  tags = merge(local.tags, { Role = "k3s-server" })
}

resource "aws_instance" "k3s" {
  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = var.node_instance_type
  availability_zone           = local.primary_az
  subnet_id                   = module.vpc.public_subnets[0]
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.k3s.id]
  iam_instance_profile        = aws_iam_instance_profile.k3s.name
  monitoring                  = false
  source_dest_check           = true
  user_data_replace_on_change = true

  user_data = templatefile("${path.module}/cloud-init/k3s.sh.tftpl", {
    k3s_version          = var.k3s_version
    k3s_installer_sha256 = var.k3s_installer_sha256
    k3s_pod_cidr         = var.k3s_pod_cidr
    k3s_service_cidr     = var.k3s_service_cidr
    k3s_cluster_dns      = var.k3s_cluster_dns
  })

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gib
    encrypted             = true
    delete_on_termination = true
    tags                  = merge(local.tags, { Name = "${local.name}-k3s-root" })
  }

  credit_specification {
    cpu_credits = "standard"
  }

  tags = merge(local.tags, {
    Name = "${local.name}-k3s"
    Role = "k3s-server"
  })

  depends_on = [
    aws_iam_role_policy.k3s,
    module.vpc
  ]
}

resource "aws_eip" "k3s" {
  domain = "vpc"

  tags = merge(local.tags, {
    Name = "${local.name}-k3s"
    Role = "k3s-server"
  })
}

resource "aws_eip_association" "k3s" {
  allocation_id = aws_eip.k3s.id
  instance_id   = aws_instance.k3s.id
}

resource "aws_db_subnet_group" "application" {
  name       = local.name
  subnet_ids = module.vpc.private_subnets

  tags = local.tags
}

resource "aws_db_parameter_group" "application" {
  name   = local.name
  family = "postgres16"

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  tags = local.tags
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
  copy_tags_to_snapshot      = true
  auto_minor_version_upgrade = true
  apply_immediately          = true

  iam_database_authentication_enabled = false
  monitoring_interval                 = 0
  performance_insights_enabled        = false
  enabled_cloudwatch_logs_exports     = []

  tags = local.tags
}

resource "aws_ssm_parameter" "k3s_instance_id" {
  name  = "${local.parameter_prefix}/k3s-instance-id"
  type  = "String"
  tier  = "Standard"
  value = aws_instance.k3s.id
}

resource "aws_ssm_parameter" "k3s_version" {
  name  = "${local.parameter_prefix}/k3s-version"
  type  = "String"
  tier  = "Standard"
  value = var.k3s_version
}

resource "aws_ssm_parameter" "public_origin" {
  name  = "${local.parameter_prefix}/public-origin"
  type  = "String"
  tier  = "Standard"
  value = local.public_origin

  depends_on = [aws_eip_association.k3s]
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
