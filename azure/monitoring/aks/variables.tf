variable "azure_region" {
  type    = string
  default = "eastus"
}

variable "cluster_name" {
  type    = string
  default = "infra-perez-wiki-monitoring"
}

# lowest possible tier for my cluster
variable "node_vm_size" {
  type    = string
  default = "Standard_D2s_v7"
}

variable "node_count" {
  type    = number
  default = 3
}

variable "state_storage_account_prefix" {
  description = "Must match bootstrap/azure's storage_account_prefix."
  type        = string
  default     = "infraperezwiki"
}

variable "state_resource_group_name" {
  description = "Must match bootstrap/azure's resource_group_name."
  type        = string
  default     = "infra-perez-wiki-tfstate-rg"
}
