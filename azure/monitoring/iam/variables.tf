variable "azure_region" {
  type    = string
  default = "eastus"
}

variable "github_org" {
  type    = string
  default = "isa-p941"
}

variable "perez_wiki_repo" {
  type    = string
  default = "perez_wiki"
}

variable "infra_repo" {
  type    = string
  default = "infra_perez_wiki"
}

variable "state_storage_account_prefix" {
  description = "Must match bootstrap/azure's storage_account_prefix. Used to recompute the same deterministic name."
  type        = string
  default     = "infraperezwiki"
}

variable "state_resource_group_name" {
  description = "Must match bootstrap/azure's resource_group_name."
  type        = string
  default     = "infra-perez-wiki-tfstate-rg"
}
