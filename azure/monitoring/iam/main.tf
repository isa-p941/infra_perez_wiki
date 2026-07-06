data "azurerm_client_config" "current" {}

locals {
  subscription_id_short      = substr(replace(data.azurerm_client_config.current.subscription_id, "-", ""), 0, 8)
  state_storage_account_name = "${var.state_storage_account_prefix}${local.subscription_id_short}"
}

data "azurerm_storage_account" "tfstate" {
  name                = local.state_storage_account_name
  resource_group_name = var.state_resource_group_name
}

resource "azurerm_resource_group" "monitoring" {
  name     = "infra-perez-wiki-monitoring-rg"
  location = var.azure_region

  lifecycle {
    prevent_destroy = true
  }
}

resource "azuread_application" "github_actions" {
  display_name = "infra-perez-wiki-github-actions-monitoring"
}

resource "azuread_service_principal" "github_actions" {
  client_id = azuread_application.github_actions.client_id
}

# One federated credential per exact OIDC subject
resource "azuread_application_federated_identity_credential" "perez_wiki_main" {
  application_id = azuread_application.github_actions.id
  display_name   = "perez-wiki-main"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_org}/${var.perez_wiki_repo}:ref:refs/heads/main"
}

resource "azuread_application_federated_identity_credential" "infra_repo_main" {
  application_id = azuread_application.github_actions.id
  display_name   = "infra-perez-wiki-main"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_org}/${var.infra_repo}:ref:refs/heads/main"
}

# Contributor on just this resource group
resource "azurerm_role_assignment" "monitoring_rg_contributor" {
  scope                = azurerm_resource_group.monitoring.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.github_actions.object_id
}

resource "azurerm_role_assignment" "state_storage" {
  scope                = data.azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.github_actions.object_id
}
