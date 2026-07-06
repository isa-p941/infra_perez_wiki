output "cluster_name" {
  value = azurerm_kubernetes_cluster.monitoring.name
}

output "kube_config_raw" {
  value     = azurerm_kubernetes_cluster.monitoring.kube_config_raw
  sensitive = true
}
