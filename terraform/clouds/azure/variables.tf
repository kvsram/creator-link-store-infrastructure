variable "name" {
  description = "Short globally reusable deployment name."
  type        = string
  default     = "creator-store-dev"
}

variable "location" {
  description = "Azure region, for example centralindia."
  type        = string
  default     = "centralindia"
}

variable "environment" {
  type    = string
  default = "dev"

  validation {
    condition     = contains(["dev", "preprod", "prod"], var.environment)
    error_message = "environment must be dev, preprod, or prod."
  }
}

variable "azure_tenant_id" {
  description = "Microsoft Entra tenant used for AKS RBAC."
  type        = string
}

variable "kubernetes_version" {
  description = "Supported AKS version. Set from the target region's supported-version list."
  type        = string
  default     = null
}

variable "node_count" {
  type    = number
  default = 2
}

variable "node_vm_size" {
  type    = string
  default = "Standard_D4s_v5"
}

variable "postgres_admin_username" {
  type    = string
  default = "creatoradmin"
}

variable "postgres_admin_password" {
  description = "Supply through TF_VAR_postgres_admin_password. It is sensitive but remains in Terraform state."
  type        = string
  sensitive   = true
}

variable "postgres_sku" {
  type    = string
  default = "B_Standard_B2s"
}

variable "postgres_high_availability" {
  description = "Enable zone-redundant PostgreSQL for preprod/prod."
  type        = bool
  default     = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
