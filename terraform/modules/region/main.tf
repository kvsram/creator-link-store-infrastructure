data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.17.0"

  name            = var.name
  cidr            = var.vpc_cidr
  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets = [for index in range(3) : cidrsubnet(var.vpc_cidr, 4, index)]
  public_subnets  = [for index in range(3) : cidrsubnet(var.vpc_cidr, 4, index + 8)]

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags  = { "kubernetes.io/role/elb" = "1" }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = "1" }
  tags                = var.tags
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.31.6"

  cluster_name                             = var.name
  cluster_version                          = var.cluster_version
  cluster_endpoint_public_access           = false
  vpc_id                                   = module.vpc.vpc_id
  subnet_ids                               = module.vpc.private_subnets
  enable_cluster_creator_admin_permissions = true

  eks_managed_node_groups = {
    default = {
      instance_types = var.node_instance_types
      min_size       = var.node_min_size
      max_size       = var.node_max_size
      desired_size   = var.node_desired_size
    }
  }

  cluster_addons = {
    coredns            = {}
    kube-proxy         = {}
    vpc-cni            = { most_recent = true }
    aws-ebs-csi-driver = { most_recent = true }
  }

  tags = merge(var.tags, { RegionKey = var.region_key })
}
