# bootstrap/azure

Creates the Azure resources needed to hold Terraform state for
`azure/monitoring`:

- Resource group for state storage
- Storage Account: `LRS` (locally redundant, cheapest replication tier),
  TLS 1.2 minimum, versioning enabled (recovery path if a bad `apply`
  corrupts state), private container (no anonymous blob access)
- Blob container within it for the actual state files

Deterministic naming (storage account name derived from your Azure
subscription ID) so `azure/monitoring`'s backend config can reference the
same name without needing to read this config's outputs first.

## Initialization

Apply it once by hand, and any workflow that needs this storage account just
assumes it exists.

```
cd bootstrap/azure
terraform init
terraform apply
```

Requires `az login` already done (`az account show` to verify).

## Troubleshooting

**`Error: Plugin did not respond` on `provider "azurerm"`**: the provider
binary itself is crashing during setup, not a normal config error. In
order of likelihood:

1. Confirm the CLI session is actually healthy: `az account show` should
   print clean JSON with your subscription ID/tenant. If it errors or looks
   off, re-run `az login`.
2. Check the CLI's output format hasn't been changed from the default the
   provider expects: `az config get core.output` should be `json` (or
   unset). If not: `az config set core.output=json`.
3. Clear and re-download the provider plugin, in case it downloaded
   corrupted:
   ```
   Remove-Item -Recurse -Force .terraform, .terraform.lock.hcl
   terraform init
   ```
   