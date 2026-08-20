terraform {
  required_version = ">= 1.10.0"

  backend "http" {}

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 8.25"
    }
  }
}

provider "oci" {
  region              = var.region
  auth                = var.oci_auth
  config_file_profile = var.config_file_profile
}
