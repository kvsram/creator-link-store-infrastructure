locals {
  tags = {
    Project     = var.project
    Environment = "production"
    ManagedBy   = "Terraform"
  }
}

resource "aws_ecr_repository" "frontend" {
  provider             = aws.region_a
  name                 = "creator-link-store-frontend"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
  tags = local.tags
}

resource "aws_ecr_repository" "backend" {
  provider             = aws.region_a
  name                 = "creator-link-store-backend"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
  tags = local.tags
}

resource "aws_ecr_lifecycle_policy" "frontend" {
  provider   = aws.region_a
  repository = aws_ecr_repository.frontend.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the most recent 30 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 30
      }
      action = { type = "expire" }
    }]
  })
}

resource "aws_ecr_lifecycle_policy" "backend" {
  provider   = aws.region_a
  repository = aws_ecr_repository.backend.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the most recent 30 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 30
      }
      action = { type = "expire" }
    }]
  })
}

module "region_a" {
  source          = "../../modules/region"
  providers       = { aws = aws.region_a }
  name            = "${var.project}-region-a"
  region_key      = "region-a"
  vpc_cidr        = var.vpc_cidrs["region-a"]
  cluster_version = var.cluster_version
  tags            = local.tags
}

module "region_b" {
  source          = "../../modules/region"
  providers       = { aws = aws.region_b }
  name            = "${var.project}-region-b"
  region_key      = "region-b"
  vpc_cidr        = var.vpc_cidrs["region-b"]
  cluster_version = var.cluster_version
  tags            = local.tags
}

module "region_c" {
  source          = "../../modules/region"
  providers       = { aws = aws.region_c }
  name            = "${var.project}-region-c"
  region_key      = "region-c"
  vpc_cidr        = var.vpc_cidrs["region-c"]
  cluster_version = var.cluster_version
  tags            = local.tags
}

module "delivery_identity" {
  source         = "../../modules/github-oidc"
  providers      = { aws = aws.region_a }
  github_owner   = var.github_owner
  aws_account_id = var.aws_account_id
  tags           = local.tags
}

module "observability_a" {
  source     = "../../modules/observability"
  providers  = { aws = aws.region_a }
  name       = "${var.project}-region-a"
  canary_url = try(var.canary_urls["region-a"], "")
  tags       = local.tags
}

module "observability_b" {
  source     = "../../modules/observability"
  providers  = { aws = aws.region_b }
  name       = "${var.project}-region-b"
  canary_url = try(var.canary_urls["region-b"], "")
  tags       = local.tags
}

module "observability_c" {
  source     = "../../modules/observability"
  providers  = { aws = aws.region_c }
  name       = "${var.project}-region-c"
  canary_url = try(var.canary_urls["region-c"], "")
  tags       = local.tags
}
