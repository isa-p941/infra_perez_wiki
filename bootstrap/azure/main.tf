data "azurerm_client_config" "current" {}

locals {
  subscription_id_short = substr(replace(data.azurerm_client_config.current.subscription_id, "-", ""), 0, 8)
  storage_account_name  = "${var.storage_account_prefix}${local.subscription_id_short}"
}

resource "azurerm_resource_group" "state" {
  name     = var.resource_group_name
  location = var.azure_region

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_storage_account" "state" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.state.name
  location                 = azurerm_resource_group.state.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  blob_properties {
    versioning_enabled = true
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"
}

resource "azurerm_role_assignment" "self_blob_access" {
  scope                = azurerm_storage_account.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

