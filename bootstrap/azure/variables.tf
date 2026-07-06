variable "azure_region" {
  type    = string
  default = "eastus"
}

variable "resource_group_name" {
  type    = string
  default = "infra-perez-wiki-tfstate-rg"
}

variable "storage_account_prefix" {
  description = "Prefix for the storage account name. Azure storage account names are 3-24 chars, lowercase letters/numbers only. No hyphens, unlike S3 bucket names."
  type        = string
  default     = "infraperezwiki"
}
