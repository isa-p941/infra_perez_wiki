terraform {
  required_version = ">= 1.10.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # storage_account_name, container_name, key, resource_group_name supplied
  # via -backend-config at init time (see README / azure/scripts/tf-init.*).
  backend "azurerm" {
    use_azuread_auth = true
  }
}

provider "azurerm" {
  features {}
}
