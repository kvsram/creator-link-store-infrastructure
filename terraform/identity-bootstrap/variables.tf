variable "region" {
  description = "AWS region used for provider API calls. IAM resources themselves are global."
  type        = string
  default     = "us-east-2"

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]+$", var.region))
    error_message = "region must be a valid AWS region name such as us-east-2."
  }
}

variable "expected_account_id" {
  description = "Twelve-digit AWS account that owns the operator identities."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.expected_account_id))
    error_message = "expected_account_id must contain exactly 12 digits."
  }
}
