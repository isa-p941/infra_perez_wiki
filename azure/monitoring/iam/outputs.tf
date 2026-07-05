output "github_actions_client_id" {
  value = azuread_application.github_actions.client_id
}

output "tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "subscription_id" {
  value = data.azurerm_client_config.current.subscription_id
}

output "monitoring_resource_group_name" {
  value = azurerm_resource_group.monitoring.name
}
