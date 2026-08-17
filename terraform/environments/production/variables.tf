variable "project" { type = string; default = "creator-store" }
variable "github_owner" { type = string; default = "kvsram" }
variable "aws_account_id" { type = string }
variable "region_a" { type = string }
variable "region_b" { type = string }
variable "region_c" { type = string }
variable "domain_name" { type = string }
variable "vpc_cidrs" { type = map(string) }
variable "canary_urls" { type = map(string); default = {} }
