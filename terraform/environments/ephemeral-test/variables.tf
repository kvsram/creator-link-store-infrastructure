variable "project" {
  description = "Project prefix used for every disposable resource."
  type        = string
  default     = "creator-store"

  validation {
    condition     = var.project == "creator-store"
    error_message = "This reviewed disposable environment is locked to the creator-store project."
  }
}

variable "test_id" {
  description = "Short unique identifier for this disposable test stack."
  type        = string
  default     = "devtest"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,16}$", var.test_id))
    error_message = "test_id must contain 3-16 lowercase letters, digits, or hyphens."
  }
}

variable "region" {
  description = "AWS region for the disposable stack; locked to the reviewed low-cost region."
  type        = string
  default     = "us-east-2"

  validation {
    condition     = var.region == "us-east-2"
    error_message = "The ephemeral test stack is cost-approved only for us-east-2."
  }
}

variable "expected_account_id" {
  description = "Twelve-digit AWS account that is allowed to receive this disposable stack."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.expected_account_id))
    error_message = "expected_account_id must contain exactly 12 digits."
  }
}

variable "vpc_cidr" {
  description = "CIDR reserved only for this disposable stack."
  type        = string
  default     = "10.42.0.0/16"

  validation {
    condition     = var.vpc_cidr == "10.42.0.0/16"
    error_message = "The reviewed disposable VPC CIDR is 10.42.0.0/16."
  }
}

variable "k3s_pod_cidr" {
  description = "K3s pod CIDR; deliberately distinct from the VPC CIDR."
  type        = string
  default     = "10.244.0.0/16"

  validation {
    condition     = var.k3s_pod_cidr == "10.244.0.0/16"
    error_message = "The reviewed disposable K3s pod CIDR is 10.244.0.0/16."
  }
}

variable "k3s_service_cidr" {
  description = "K3s service CIDR; deliberately distinct from the VPC and pod CIDRs."
  type        = string
  default     = "10.245.0.0/16"

  validation {
    condition     = var.k3s_service_cidr == "10.245.0.0/16"
    error_message = "The reviewed disposable K3s service CIDR is 10.245.0.0/16."
  }
}

variable "k3s_cluster_dns" {
  description = "Cluster DNS address inside the reviewed K3s service CIDR."
  type        = string
  default     = "10.245.0.10"

  validation {
    condition     = var.k3s_cluster_dns == "10.245.0.10"
    error_message = "The reviewed disposable K3s DNS address is 10.245.0.10."
  }
}

variable "k3s_version" {
  description = "Exact K3s release installed on the disposable node."
  type        = string
  default     = "v1.35.8+k3s1"

  validation {
    condition     = var.k3s_version == "v1.35.8+k3s1"
    error_message = "The disposable test stack is approved only for K3s v1.35.8+k3s1."
  }
}

variable "k3s_installer_sha256" {
  description = "Pinned SHA-256 of the reviewed get.k3s.io installer."
  type        = string
  default     = "8598e002e61d658fed7b7542fc6d2c66d8da6eae69e088830105d2ee1ffb6d91"

  validation {
    condition     = var.k3s_installer_sha256 == "8598e002e61d658fed7b7542fc6d2c66d8da6eae69e088830105d2ee1ffb6d91"
    error_message = "The K3s installer checksum must match the reviewed installer."
  }
}

variable "node_instance_type" {
  description = "Single K3s instance type locked to the cost estimate."
  type        = string
  default     = "t3a.medium"

  validation {
    condition     = var.node_instance_type == "t3a.medium"
    error_message = "The disposable test stack is approved only for one t3a.medium node."
  }
}

variable "root_volume_size_gib" {
  description = "Encrypted gp3 root disk size, including local-path uploads."
  type        = number
  default     = 40

  validation {
    condition     = var.root_volume_size_gib == 40
    error_message = "The approved disposable K3s root disk is exactly 40 GiB."
  }
}

variable "database_instance_class" {
  description = "Single-AZ disposable PostgreSQL instance class locked to the cost estimate."
  type        = string
  default     = "db.t4g.micro"

  validation {
    condition     = var.database_instance_class == "db.t4g.micro"
    error_message = "The disposable test stack is approved only for db.t4g.micro."
  }
}

variable "tester_cidrs" {
  description = "IPv4 /32 CIDRs allowed to reach the temporary HTTP endpoint."
  type        = list(string)

  validation {
    condition = (
      length(var.tester_cidrs) > 0 &&
      length(var.tester_cidrs) <= 5 &&
      alltrue([for cidr in var.tester_cidrs : can(cidrhost(cidr, 0)) && endswith(cidr, "/32")])
    )
    error_message = "tester_cidrs must contain between one and five valid IPv4 /32 CIDRs."
  }
}

variable "public_http_port" {
  description = "Temporary browser-facing HTTP port exposed on the single K3s node."
  type        = number
  default     = 80

  validation {
    condition     = var.public_http_port == 80
    error_message = "The reviewed disposable storefront HTTP port is exactly 80."
  }
}

variable "expires_at" {
  description = "Mandatory RFC3339 teardown deadline, no more than seven days after the plan."
  type        = string

  validation {
    condition     = can(timecmp(var.expires_at, "2020-01-01T00:00:00Z"))
    error_message = "expires_at must be an RFC3339 timestamp such as 2026-09-14T18:00:00Z."
  }
}

variable "infrastructure_release" {
  description = "Exact infrastructure Git commit being applied."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{40}$", var.infrastructure_release))
    error_message = "infrastructure_release must be a 40-character lowercase Git SHA."
  }
}
