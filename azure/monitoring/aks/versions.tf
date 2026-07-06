terraform {
  required_version = ">= 1.10.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
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

# configured from kube_config output
provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.monitoring.kube_config[0].host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.monitoring.kube_config[0].client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.monitoring.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.monitoring.kube_config[0].cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = azurerm_kubernetes_cluster.monitoring.kube_config[0].host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.monitoring.kube_config[0].client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.monitoring.kube_config[0].client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.monitoring.kube_config[0].cluster_ca_certificate)
  }
}
