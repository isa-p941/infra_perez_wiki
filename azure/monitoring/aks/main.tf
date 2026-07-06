data "azurerm_client_config" "current" {}

locals {
  subscription_id_short      = substr(replace(data.azurerm_client_config.current.subscription_id, "-", ""), 0, 8)
  state_storage_account_name = "${var.state_storage_account_prefix}${local.subscription_id_short}"
}

# Reads azure/monitoring/iam's real outputs
data "terraform_remote_state" "iam" {
  backend = "azurerm"
  config = {
    storage_account_name = local.state_storage_account_name
    container_name        = "tfstate"
    resource_group_name    = var.state_resource_group_name
    key                    = "azure-monitoring-iam.tfstate"
    use_azuread_auth       = true
  }
}

resource "azurerm_kubernetes_cluster" "monitoring" {
  name                = var.cluster_name
  location            = var.azure_region
  resource_group_name = data.terraform_remote_state.iam.outputs.monitoring_resource_group_name
  dns_prefix          = var.cluster_name
  sku_tier            = "Free"

  default_node_pool {
    name       = "default"
    node_count = var.node_count
    vm_size    = var.node_vm_size
  }

  identity {
    type = "SystemAssigned"
  }
}
