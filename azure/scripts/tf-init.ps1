# Initializes an azure/monitoring/* Terraform config. Must match
# bootstrap/azure's own defaults (storage_account_prefix, resource group
# name, container name) if those are ever changed.
#
# Usage: .\azure\scripts\tf-init.ps1 azure\monitoring\iam azure-monitoring-iam.tfstate
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$WorkingDirectory,

    [Parameter(Mandatory = $true, Position = 1)]
    [string]$BackendKey
)

$ErrorActionPreference = "Stop"

$subscriptionId = az account show --query id -o tsv
if (-not $subscriptionId) {
    Write-Error "Could not get subscription ID -- make sure 'az login' has been run."
    exit 1
}

$subscriptionIdShort = $subscriptionId.Replace("-", "").Substring(0, 8)
$storageAccountName = "infraperezwiki$subscriptionIdShort"
$containerName = "tfstate"
$resourceGroupName = "infra-perez-wiki-tfstate-rg"

Push-Location $WorkingDirectory
try {
    terraform init `
        -backend-config="storage_account_name=$storageAccountName" `
        -backend-config="container_name=$containerName" `
        -backend-config="resource_group_name=$resourceGroupName" `
        -backend-config="key=$BackendKey"
}
finally {
    Pop-Location
}
