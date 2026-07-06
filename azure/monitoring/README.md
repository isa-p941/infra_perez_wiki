# azure/monitoring

Split the same way as `aws/jenkins`: two Terraform configs with separate
state, so an automated destroy can never touch the trust relationship that
makes the automation possible in the first place.

- **`iam/`**: Azure AD app registration, federated credentials, RBAC role
  assignments. Applied once, manually. Never destroyed by the on-demand
  lifecycle.
- **`aks/`**: AKS cluster, Helm releases for Grafana/Prometheus/Loki, and
  in-cluster RBAC (separate from the Azure RBAC in `iam/`). Built, tested
  locally with `kind`, and confirmed working against a real cluster.
  Created and destroyed on demand, same as `aws/jenkins/compute`.

AKS cluster, Free tier (control plane genuinely $0), 2 worker nodes
(`Standard_D2s_v7`; B-series burstable VMs, originally planned, aren't
available at all on this Free Trial subscription in any region tried).
On-demand and fully ephemeral. Dashboards and datasources are provisioned
as code, so nothing is lost on teardown, but metric and log history don't
survive one either. That trade-off is deliberate, not an oversight.

`aks/` contains:

- AKS cluster and node pool
- Helm releases for Grafana, Prometheus, Loki
- Prometheus scrape config targeting the Linode website box's
  `node_exporter`, over the public internet with basic auth. Scraping the
  AWS Jenkins EC2 instance's own `node_exporter` isn't wired up yet.
- Real secrets (Grafana admin password, the Linode `node_exporter`
  password) come from Terraform variables, no Key Vault yet, see the root
  README's Secrets section
- No mounted ServiceAccount tokens or unused RBAC objects for workloads
  that don't need the Kubernetes API. See `aks/README.md` for the
  reasoning.

Backend: remote state in the Azure Storage Account created by
`bootstrap/azure`.
