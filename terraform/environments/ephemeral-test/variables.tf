variable "project" {
  description = "Project prefix used for every disposable resource."
  type        = string
  default     = "creator-store"
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

variable "operator_role_arn" {
  description = "Non-root IAM role granted explicit EKS cluster-admin access for this disposable stack."
  type        = string

  validation {
    condition = (
      can(regex("^arn:aws:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$", var.operator_role_arn)) &&
      try(split(":", var.operator_role_arn)[4] == var.expected_account_id, false) &&
      !strcontains(var.operator_role_arn, ":role/aws-service-role/")
    )
    error_message = "operator_role_arn must be a non-service IAM role ARN in expected_account_id; root, users, and STS session ARNs are not allowed."
  }
}

variable "vpc_cidr" {
  description = "CIDR reserved only for this disposable stack."
  type        = string
  default     = "10.42.0.0/16"
}

variable "cluster_version" {
  description = "EKS version locked to the reviewed standard-support release."
  type        = string
  default     = "1.35"

  validation {
    condition     = var.cluster_version == "1.35"
    error_message = "The ephemeral test stack is approved only for EKS 1.35."
  }
}

variable "node_instance_type" {
  description = "Single development worker instance type locked to the cost estimate."
  type        = string
  default     = "t3a.medium"

  validation {
    condition     = var.node_instance_type == "t3a.medium"
    error_message = "The ephemeral test stack is approved only for one t3a.medium worker."
  }
}

variable "database_instance_class" {
  description = "Single-AZ disposable PostgreSQL instance class locked to the cost estimate."
  type        = string
  default     = "db.t4g.micro"

  validation {
    condition     = var.database_instance_class == "db.t4g.micro"
    error_message = "The ephemeral test stack is approved only for db.t4g.micro."
  }
}

variable "tester_cidrs" {
  description = "IPv4 /32 CIDRs allowed to reach the temporary NodePort."
  type        = list(string)

  validation {
    condition     = length(var.tester_cidrs) > 0 && alltrue([for cidr in var.tester_cidrs : can(cidrhost(cidr, 0)) && endswith(cidr, "/32")])
    error_message = "tester_cidrs must contain at least one valid IPv4 /32 CIDR."
  }
}

variable "cluster_public_access_cidrs" {
  description = "IPv4 /32 CIDRs allowed to reach the EKS API."
  type        = list(string)

  validation {
    condition     = length(var.cluster_public_access_cidrs) > 0 && alltrue([for cidr in var.cluster_public_access_cidrs : can(cidrhost(cidr, 0)) && endswith(cidr, "/32")])
    error_message = "cluster_public_access_cidrs must contain at least one valid IPv4 /32 CIDR."
  }
}

variable "public_node_port" {
  description = "Temporary HTTP port exposed on the single EKS worker."
  type        = number
  default     = 30080

  validation {
    condition     = var.public_node_port >= 30000 && var.public_node_port <= 32767
    error_message = "public_node_port must be in the Kubernetes NodePort range."
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
