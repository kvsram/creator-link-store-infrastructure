variable "compartment_ocid" {
  type = string
}

variable "tenancy_ocid" {
  type = string
}

variable "region" {
  type    = string
  default = "ap-hyderabad-1"
}

variable "name" {
  type    = string
  default = "creator-store-dev"
}

variable "environment" {
  type    = string
  default = "dev"

  validation {
    condition     = contains(["dev", "preprod", "prod"], var.environment)
    error_message = "environment must be dev, preprod, or prod."
  }
}

variable "oci_auth" {
  description = "Use InstancePrincipal on the private runner, or SecurityToken locally."
  type        = string
  default     = "InstancePrincipal"
}

variable "config_file_profile" {
  type    = string
  default = null
}

variable "kubernetes_version" {
  description = "OKE-supported version from `oci ce cluster-options list`."
  type        = string
}

variable "node_image_ocid" {
  description = "OKE-compatible Oracle Linux image OCID for the selected Kubernetes version."
  type        = string
}

variable "node_count" {
  type    = number
  default = 2
}

variable "node_shape" {
  type    = string
  default = "VM.Standard.E5.Flex"
}

variable "node_ocpus" {
  type    = number
  default = 2
}

variable "node_memory_gbs" {
  type    = number
  default = 16
}

variable "node_ssh_public_key" {
  description = "Optional operator SSH public key; leave blank to disable SSH access."
  type        = string
  default     = ""
}

variable "postgres_username" {
  type    = string
  default = "creatoradmin"
}

variable "postgres_password_secret_ocid" {
  description = "OCI Vault Secret OCID holding the PostgreSQL administrator password."
  type        = string
}

variable "postgres_password_secret_version" {
  description = "Explicit Vault secret version to make rotations deliberate."
  type        = string
}

variable "postgres_instance_count" {
  type    = number
  default = 1
}

variable "freeform_tags" {
  type    = map(string)
  default = {}
}
