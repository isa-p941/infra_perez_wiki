#!/usr/bin/env bash
# Initializes an azure/monitoring/* Terraform config. Must match
# bootstrap/azure's own defaults (storage_account_prefix, resource group
# name, container name) if those are ever changed.
#
# Usage: azure/scripts/tf-init.sh <working-directory> <backend-key>
# Example: azure/scripts/tf-init.sh azure/monitoring/iam azure-monitoring-iam.tfstate
set -euo pipefail

if [ $# -ne 2 ]; then
  echo "Usage: $0 <working-directory> <backend-key>" >&2
  exit 1
fi

workdir="$1"
key="$2"

subscription_id=$(az account show --query id -o tsv)
subscription_id_short=$(echo "$subscription_id" | tr -d '-' | cut -c1-8)
storage_account_name="infraperezwiki${subscription_id_short}"
container_name="tfstate"
resource_group_name="infra-perez-wiki-tfstate-rg"

cd "$workdir"
terraform init \
  -backend-config="storage_account_name=${storage_account_name}" \
  -backend-config="container_name=${container_name}" \
  -backend-config="resource_group_name=${resource_group_name}" \
  -backend-config="key=${key}"
