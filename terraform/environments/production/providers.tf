terraform {
  required_version = ">= 1.7.0"
  required_providers { aws = { source = "hashicorp/aws", version = "~> 5.0" } }
}

provider "aws" { alias = "region_a"; region = var.region_a }
provider "aws" { alias = "region_b"; region = var.region_b }
provider "aws" { alias = "region_c"; region = var.region_c }
