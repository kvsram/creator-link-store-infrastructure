variable "project" {
  type    = string
  default = "creator-store"
}

variable "environment" {
  type = string
  validation {
    condition     = contains(["dev", "preprod", "prod"], var.environment)
    error_message = "environment must be dev, preprod, or prod"
  }
}

variable "region" { type = string }

variable "region_key" {
  type    = string
  default = "region-a"
}

variable "vpc_cidr" { type = string }

variable "cluster_version" {
  type    = string
  default = "1.35"
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 4
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "database_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "database_multi_az" {
  type    = bool
  default = false
}

variable "database_deletion_protection" {
  type    = bool
  default = false
}

variable "canary_url" {
  type    = string
  default = ""
}

variable "infrastructure_release" {
  type = string
  validation {
    condition     = can(regex("^[0-9a-f]{40}$", var.infrastructure_release))
    error_message = "infrastructure_release must be the 40-character Git commit SHA being released"
  }
}
