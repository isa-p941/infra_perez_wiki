# azure/monitoring/iam

The prerequisite for automation. Azure's equivalent of `aws/jenkins/iam`.
Applied once, manually. Don't destroy it or you'll need to run it again.
Requires `bootstrap/azure` applied first.

Creates:

- Resource group (`infra-perez-wiki-monitoring-rg`) that holds the AKS
  cluster built in `azure/monitoring/aks`
- Azure AD app registration and service principal: the identity GitHub
  Actions authenticates as
- **Two** federated identity credentials. Azure requires an exact subject
  match per credential, unlike AWS's IAM trust policy, which can use a
  single `StringLike` condition to match a pattern. One credential for
  `perez_wiki`'s main branch, one for `infra_perez_wiki`'s main branch.
- RBAC role assignments: `Contributor` scoped to just the monitoring
  resource group, and `Storage Blob Data Contributor` scoped to just the
  state storage account from `bootstrap/azure`. This permission set held
  up through a full AKS apply/destroy cycle without needing any changes.

Authentication is OIDC to keep the same approach as the AWS "cluster."

## Applying

Bash (Git Bash/Mac/Linux):
```
bash azure/scripts/tf-init.sh azure/monitoring/iam azure-monitoring-iam.tfstate
```

PowerShell:
```
.\azure\scripts\tf-init.ps1 azure\monitoring\iam azure-monitoring-iam.tfstate
```

Then:
```
cd azure/monitoring/iam
terraform plan
terraform apply
```
