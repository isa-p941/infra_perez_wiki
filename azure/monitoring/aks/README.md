# azure/monitoring/aks

**Status:** built, tested locally with `kind`, and confirmed working
against a real AKS cluster. Grafana, Prometheus, and Loki all ran, RBAC
hardening held up, and the datasources connected. The cluster was then
torn down to stop the cost. Real secrets (`grafana_admin_password`,
`linode_exporter_password`) come from sensitive Terraform variables, see
"Secrets".

Tested locally, and found many an error, so check "Troubleshooting" for more
details there.

Creates:

- AKS cluster, **Free tier** (`sku_tier = "Free"`, control plane genuinely
  $0, no SLA, fine for a portfolio demo)
- Default node pool: 2x `Standard_D2s_v7` (2 vCPU, 7GiB, ~$0.132/hr/node).
  B-series burstable VMs (`B2ats_v2`, then `B2ps_v2`) were tried first but
  aren't in this subscription's allowed SKU list at all. That's a Free
  Trial restriction, confirmed in both `eastus` and `eastus2`, and Free Trial
  subscriptions can't request quota increases to unlock them. Node count is
  2, not 3. This subscription's `eastus` regional vCPU quota is 4 total,
  and 3 nodes at 2 vCPU each requested 6 (see `ErrCode_InsufficientVCPUQuota`
  below).
- System-assigned managed identity for the cluster itself (separate from
  the GitHub-Actions-facing service principal in `../iam`)

Reads `azure/monitoring/iam`'s Terraform outputs (the monitoring
resource group name) via `terraform_remote_state`

## A Quick Speedbump Sign

Brand-new Azure subscriptions sometimes haven't "registered" the
`Microsoft.ContainerService` resource provider yet, which causes
`MissingSubscriptionRegistration` on first AKS creation. So to be safe,
run this first:

```
az provider register --namespace Microsoft.ContainerService
```

Registration can take a few minutes, but if you're impatient:

```
az provider show --namespace Microsoft.ContainerService --query registrationState
```

## Secrets

Two sensitive Terraform variables, no defaults: `grafana_admin_password`,
`linode_exporter_password` (must match the Linode box's current
`node_exporter` hash). Set before `plan`/`apply`:

```powershell
$env:TF_VAR_grafana_admin_password = "<real password>"
$env:TF_VAR_linode_exporter_password = "<must match the box's current node_exporter hash>"
```

Not yet wired into a GitHub Actions workflow. When that's built, these
become `secrets.GRAFANA_ADMIN_PASSWORD` / `secrets.LINODE_EXPORTER_PASSWORD`
set as `TF_VAR_*` env on the apply step, same as `deploy-jenkins-only.yml`.

## Local (`kind`) vs. Azure Live Deployment: Values File Distinction

- **Local `kind` testing** uses the plain `helm/*.yaml` files directly with
  the `helm` CLI. Any password in these files (`grafana-values.yaml`'s
  `adminPassword`, `prometheus-values.yaml`'s scrape `basic_auth.password`)
  is a non-functional placeholder. Fine to commit, never the real value.
  ```powershell
  helm upgrade --install prometheus prometheus-community/prometheus `
    --namespace monitoring --kube-context kind-grafana-test `
    -f azure/monitoring/aks/helm/prometheus-values.yaml
  ```
- **Azure Live Deployment** goes through Terraform (`helm_release` in
  `main.tf`), which injects the real values at `apply` time:
  - Grafana: `helm/grafana-values.yaml` plus a `set_sensitive` block
    overriding `adminPassword` with `var.grafana_admin_password`.
  - Prometheus: `helm/prometheus-values.yaml.tftpl` (not the plain
    `.yaml`), rendered via `templatefile()` with
    `linode_exporter_password = var.linode_exporter_password`. This file
    is not valid standalone Helm input. Don't pass it to `helm -f`
    directly.
  - Loki: no secrets involved, `helm/loki-values.yaml` used as-is for
    both paths.

## Applying

Two ways.

**GitHub Actions button** (primary): the **"Deploy Monitoring"** workflow in
this repo's Actions tab (`.github/workflows/deploy-monitoring.yml`). Reads
`GRAFANA_ADMIN_PASSWORD` and `LINODE_EXPORTER_PASSWORD` from this repo's
own secrets, so set those under Settings -> Secrets and variables ->
Actions first. Tear down with the **"Destroy Monitoring"** workflow.

**Local** (for testing/debugging):
```
bash azure/scripts/tf-init.sh azure/monitoring/aks azure-monitoring-aks.tfstate
# or: .\azure\scripts\tf-init.ps1 azure\monitoring\aks azure-monitoring-aks.tfstate
cd azure/monitoring/aks
terraform plan
terraform apply
```

Either way requires `azure/monitoring/iam` applied first. The local path
also needs the two `TF_VAR_*` secrets above set in the shell.

## Local testing with `kind` 

Iterating on Helm values against the real AKS cluster costs real money per
hour and takes time to spin up. I ain't a bank and this stuff adds up QUICK.
 
Here's how I tested against a free local cluster first:

### Prerequisites
Docker Desktop (with WSL2) + `kind`/`kubectl`/`helm` installed locally.

### Instructions
```powershell
kind create cluster --name grafana-test
kubectl create namespace monitoring --context kind-grafana-test

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana-community.github.io/helm-charts
# If `grafana` was already added pointing at the old grafana.github.io URL:
#   helm repo add grafana https://grafana-community.github.io/helm-charts --force-update
helm repo update

helm upgrade --install prometheus prometheus-community/prometheus `
  --namespace monitoring --kube-context kind-grafana-test `
  -f azure/monitoring/aks/helm/prometheus-values.yaml

helm upgrade --install loki grafana/loki --version 7.0.0 `
  --namespace monitoring --kube-context kind-grafana-test `
  -f azure/monitoring/aks/helm/loki-values.yaml

helm upgrade --install grafana grafana/grafana `
  --namespace monitoring --kube-context kind-grafana-test `
  -f azure/monitoring/aks/helm/grafana-values.yaml

kubectl get pods -n monitoring --context kind-grafana-test
```

View Grafana (run in its own terminal window, it blocks):
```powershell
kubectl port-forward -n monitoring svc/grafana 3000:80 --context kind-grafana-test
```
`http://localhost:3000`, login from `grafana-values.yaml`'s `adminUser`/`adminPassword`.
Check **Connections → Data sources** -> click each one -> **Save & test**

Check each individually.

## Troubleshooting 

**AKS cluster creation: `SystemPoolSkuTooLow`**: the system node pool
needs at least 2 vCPUs and 4GiB memory. `B2ats_v2` (1GiB) doesn't clear it.

**AKS cluster creation: `BadRequest: The VM size of ... is not allowed in
your subscription`**: B-series burstable VMs aren't in the allowed SKU
list at all on Free Trial subscriptions, confirmed in multiple regions.
Free Trial subscriptions can't request quota increases to unlock them.
`Standard_D2s_v7` is the cheapest option actually available. Feel free to try
a different configuration, but my original idea of "small cluster" falls apart
with any other tier.

**AKS cluster creation: `ErrCode_InsufficientVCPUQuota`: "left regional
vcpu quota 4, requested quota 6"**: separate limit from the SKU
restriction above: total vCPUs across the whole region, not just which VM
sizes are allowed. 3 nodes x `Standard_D2s_v7` (2 vCPU each) requests 6,
over this Free Trial subscription's 4-vCPU `eastus` quota. Can't fix by
shrinking the VM size further (2 vCPU/node is already the AKS system-pool
minimum, see `SystemPoolSkuTooLow` above). Fixed by dropping
`node_count` to 2.

**`helm_release.loki` on the Azure cluster: `context deadline exceeded`,
`loki-chunks-cache-0` stuck `Pending`**: only surfaced against the real
AKS cluster, never against local `kind`. `kubectl describe pod
loki-chunks-cache-0` showed `FailedScheduling: 0/2 nodes are available: 2
Insufficient memory`, and the pod's actual memory request was ~9.6GiB,
more than an entire `Standard_D2s_v7` node (7GiB) has. The chart's
`chunksCache.allocatedMemory` (default `8192` MB) and
`resultsCache.allocatedMemory` (default `1024` MB, why only the chunks
cache and not the results cache failed to schedule) size these memcached
pods for a real production cluster; `kind`'s single, more generously
resourced node never exposed this, since local testing never hit an
actual memory ceiling. Fixed by nuking caches, they never get warm on
a stack that's torn down between sessions anyway.

**Loki: `You have more than zero replicas configured for both the single
binary and simple scalable targets`**: set `deploymentMode: SingleBinary`
*and* explicitly zero out `read.replicas`, `write.replicas`,
`backend.replicas`. The chart defaults those to non-zero regardless of
`deploymentMode`.

**Loki: `You must provide a schema_config`**: set `loki.useTestSchema: true`.
Fine to keep for the Azure deployment too, not just local testing, since
this whole stack is ephemeral anyway.

**Loki pod crash-loops: `mkdir /var/loki: read-only file system` /
`error initialising module: ruler-storage`**: disabling persistence
removes the chart's default volume at `/var/loki`. Modules other than the
ruler still try to write there too. `ruler.enabled: false` does **not**
fix this. That flag only affects a separate Deployment in "simple
scalable" mode, not module init within single-binary (`-target=all`)
mode, where everything initializes together regardless of per-component
enable flags. So I had to mount an `emptyDir` explicitly at `/var/loki` via
`singleBinary.extraVolumes`/`extraVolumeMounts`. Fine for now, might break if
you want persistence.

**Loki: `duplicate entries for key [mountPath="/var/loki"]` on `helm
upgrade`**: chart version drift, not a values bug. The local `kind`
command for `loki` didn't originally pin `--version`, so after repointing
the `grafana` repo alias to `grafana-community.github.io/helm-charts` (see
above), it silently resolved to that repo's newest chart (an 18.x, not the
`7.0.0` this project is pinned to in Terraform). That newer version's
`singleBinary` container already mounts something at `/var/loki` itself,
colliding with the `extraVolumeMounts` entry from the schema/persistence
fix above. Always pin `--version 7.0.0` locally too, matching
`helm_release.loki`'s Terraform version. An unpinned local test isn't
actually testing what gets deployed.

**Grafana can't reach Loki (`connection refused`) even though the pod is
running**: the chart's own install notes reveal the correct datasource
URL goes through the gateway (`http://loki-gateway.monitoring.svc.cluster.local`),
not the `loki` service directly on port 3100. The direct route may not
resolve to a ready endpoint depending on chart version/topology.

**Pushgateway pod runs even with `pushgateway.enabled: false`**: wrong
key, same failure signature as the `extraScrapeConfigs` bug. The
`prometheus-community/prometheus` umbrella chart's actual sub-chart alias
is `prometheus-pushgateway:` (matches the chart dependency name, not a
simplified camelCase key), so `pushgateway:` was silently ignored the
whole time and the chart default (`enabled: true`) won. Caught while
re-verifying the RBAC changes below. That pod had been running unnoticed
for 108 minutes. `nodeExporter:` has the same mismatch (real key:
`prometheus-node-exporter:`), just harmless since `enabled: true` is what
we wanted anyway. Lesson: always check a chart's actual `Chart.yaml`
dependency aliases before assuming a values key name, not just its
top-level values.yaml comments.

**`kubectl port-forward` stops working after a `helm upgrade` or
`kubectl rollout restart`**: port-forward tracks a specific pod, not the
service. If that pod gets replaced for any reason (upgrade, rollout
restart, crash), the tunnel breaks and needs re-running. Run it in its own
terminal window so it doesn't get killed by other commands, and re-run it
any time you see "unable to connect" after touching the deployment.

**A custom Prometheus scrape config (`extraScrapeConfigs`) silently doesn't
show up anywhere, not even as a failing target**: check whether it's
nested under the wrong key before suspecting a cluster-side reload issue.
`extraScrapeConfigs` is a **top-level** key in the
`prometheus-community/prometheus` chart, not nested under `server:` (an
easy mistake, since most other server-related settings *are* under
`server:`). General debugging technique that isolates this fast: render
the chart locally without touching the cluster at all:
`helm template prometheus prometheus-community/prometheus -f helm/prometheus-values.yaml | Select-String "your-job-name" -Context 5,5`.
If it's missing from the rendered output, the values file is wrong; if
it's present there but missing from the live cluster's `/config` page,
the problem is reload/caching, not the values file.

## Cross-cloud target: the real Linode website box

Confirmed working: `node_exporter` installed natively (no Docker, matching
how the box already runs everything else) on the Linode box as a systemd
service, basic-auth protected, port 9100 opened on **both** firewall layers
(Linode Cloud Firewall + the box's own nftables, same two-layer lesson
from the SSH work on the Jenkins integration). Scraped via
`extraScrapeConfigs` in `prometheus-values.yaml`, targeting
`perez.wiki:9100` directly over the public internet (the box already has a
public IP since it hosts a live website, so this could be tested from
local `kind` without ever touching the paid AKS cluster).

Deliberately scoped to system metrics only for this first pass (CPU/RAM/disk
via `node_exporter`). Nginx request-level metrics would require editing
the tracked nginx config in the `perez_wiki` repo (a bigger step than adding
a new standalone service), and log shipping via Promtail is a separate,
not-yet-built piece.

## In-cluster RBAC

Originally planned as "a `Role`/`RoleBinding` per ServiceAccount scoped to
`get` on one named Secret." That turned out to be the wrong mechanism for
these three charts: Prometheus/Grafana/Loki all consume secret values via
env-var injection or volume mounts (`adminPassword`, `extraSecretMounts`,
etc.), which the kubelet resolves using node credentials, not via the
pod's own ServiceAccount calling the Kubernetes API. RBAC on a Secret
object only matters to something that calls `GET`/`LIST` against the API
server directly, and none of these workloads do that (we use a static
Prometheus scrape target, not `kubernetes_sd_configs`; Grafana's
datasources are in values, not the ConfigMap-watching sidecar).

So the actually-correct least-privilege move is the opposite of a narrow
grant: since none of these pods need the Kubernetes API for anything, they
get **no token at all**.

- `automountServiceAccountToken: false` set explicitly for all three
  (Prometheus's `serviceAccounts.server.*`; Grafana's root-level key,
  since its pod spec defaults this to `true` even though
  `serviceAccount.automountServiceAccountToken` itself defaults `false`,
  so the root key has to be set too; and Loki's shared `serviceAccount.*`,
  since `singleBinary.serviceAccount.create` defaults `false` and rides on
  the shared one).
- `rbac.create: false` for Prometheus and Grafana, removing the
  ClusterRole/Role they'd otherwise create for features we don't use
  (Prometheus's in-cluster service discovery, Grafana's dashboard/
  datasource sidecar). Verified by reading each chart's actual RBAC
  templates (`role.yaml`/`clusterrole.yaml` in the chart source) rather
  than assuming from the values-file comments alone. Both charts'
  `Role` template only renders `rules:` when a specific feature we don't
  use is turned on, so this was already a no-op with our config, but
  explicit is safer against a future values change re-enabling it
  unnoticed. Loki has no equivalent `rbac.create` toggle; its own `Role`
  template is gated on `sidecar.rules.enabled`.

**Re-verified against local `kind`, and it caught a real regression.
This is exactly why "verified by reading chart templates" isn't the same
as "verified by running it":** `sidecar.rules.enabled` defaults to
**`true`** in the `loki` chart, not `false` as originally assumed here.
It ships a `loki-sc-rules` sidecar container (`kiwigrid/k8s-sidecar`,
watches ConfigMaps/Secrets for `loki_rule`-labeled rule files) regardless
of whether `ruler.enabled` is on. Disabling `automountServiceAccountToken`
broke it immediately: `CrashLoopBackOff`, `"Service token file does not
exist."` Since we don't use Loki-based alerting rules at all
(`ruler.enabled: false` already), the fix is `sidecar.rules.enabled:
false` in `loki-values.yaml`, removing the sidecar entirely rather than
re-enabling its token, which wouldn't have fully fixed it anyway (no
Role exists for it to actually list/watch anything, since
`rbac.namespaced` stays `false`).

Confirmed after the fix: `kubectl get sa -n monitoring -o custom-columns=
NAME:.metadata.name,AUTOMOUNT:.automountServiceAccountToken` shows `false`
for `grafana`, `loki`, `loki-canary`, `loki-gateway`, `loki-memcached`,
`prometheus-server`, and `prometheus-prometheus-node-exporter`; all pods
`Running` with no crash loops.

**Deliberate exception:** `prometheus-kube-state-metrics`'s ServiceAccount
keeps `automountServiceAccountToken: true`. Unlike the others, this
sub-chart's entire job is calling the Kubernetes API (`list`/`watch` on
pods, deployments, nodes, etc. to expose their state as metrics). It
genuinely needs a token, and the chart already scopes it to a read-only
ClusterRole. Disabling automount here would just break it for no security
gain, so it's left as the chart's default.

## Still to come

Log shipping (Promtail) from the Linode box, and optional nginx
request-metrics (requires editing tracked website config, deferred
pending a separate decision). The GitHub Actions deploy/destroy workflows
now exist (`deploy-monitoring.yml`/`destroy-monitoring.yml`) but haven't
been run through the button yet, only applied by hand.

## Note: Grafana/Loki chart repository

`helm_release.grafana`/`helm_release.loki` point at
`https://grafana-community.github.io/helm-charts`, not the older
`grafana.github.io/helm-charts`. Grafana migrated chart source there
(deadline for the old repo was 2026-01-30; only a redirect README remains
under its `charts/grafana`/`charts/loki` paths now). Confirmed the new
repo's packaged index carries full prior version history, including the
`loki` `7.0.0` this project pins, so there was no reason to stay on the
soon-to-be-stale mirror. If testing locally with `kind` and you'd already
run `helm repo add grafana` against the old URL, re-add with
`--force-update` (see "Local testing" below).

## Note on the Helm/Kubernetes provider configuration

`versions.tf`'s `kubernetes`/`helm` provider blocks read
`azurerm_kubernetes_cluster.monitoring.kube_config[0].*` directly. That's
a resource attribute, not a data source. This works because Terraform only
needs those values resolved when something *using* those providers
(the `helm_release`/`kubernetes_namespace` resources) actually gets
applied, by which point the cluster already exists earlier in the same
apply. If this ever fails on a from-scratch `apply` with a connection
error before the cluster is created, run `terraform apply
-target=azurerm_kubernetes_cluster.monitoring` first, then a normal
`terraform apply` for everything else.
