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
    container_name       = "tfstate"
    resource_group_name  = var.state_resource_group_name
    key                  = "azure-monitoring-iam.tfstate"
    use_azuread_auth     = true
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

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
  }

  depends_on = [azurerm_kubernetes_cluster.monitoring]
}

resource "helm_release" "prometheus" {
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  # Renders the real password via templatefile(), see helm/prometheus-values.yaml.tftpl
  values = [templatefile("${path.module}/helm/prometheus-values.yaml.tftpl", {
    linode_exporter_password = var.linode_exporter_password
  })]
}

resource "helm_release" "loki" {
  name = "loki"
  # Chart source migrated here from grafana.github.io/helm-charts
  repository = "https://grafana-community.github.io/helm-charts"
  chart      = "loki"
  version    = "7.0.0" # pinned to match the version validated locally against kind
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  values = [file("${path.module}/helm/loki-values.yaml")]
}

resource "helm_release" "grafana" {
  name       = "grafana"
  repository = "https://grafana-community.github.io/helm-charts"
  chart      = "grafana"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  values = [file("${path.module}/helm/grafana-values.yaml")]

  set_sensitive {
    name  = "adminPassword"
    value = var.grafana_admin_password
  }
}
