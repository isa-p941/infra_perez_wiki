# infra_perez_wiki

Infrastructure for a Jenkins CI cluster (AWS) and a Grafana/Prometheus/Loki monitoring
stack (Azure), built around my [perez_wiki](https://www.perez.wiki) website.

**Status:** the AWS/Jenkins side is real and confirmed working end-to-end — `bootstrap/aws`
and `aws/jenkins/iam` are applied, and `aws/jenkins/compute` deploys automatically via
GitHub Actions (`perez_wiki`'s "Deploy via Jenkins" button → this repo's
`deploy-jenkins-only.yml` → fresh Jenkins instance → real deploy to the Linode box).
The Azure/monitoring side (`bootstrap/azure`, `azure/monitoring`) hasn't been started
yet. See [Build order](#build-order) for what's next.

## Architecture
*Chart produced by Anthropic's Claude*
```mermaid
flowchart TB
    subgraph GH["GitHub"]
        PW["perez_wiki repo"]
        IPW["infra_perez_wiki repo (this one)"]
        SEC["Actions encrypted secrets"]
    end

    subgraph Linode["Linode — perez.wiki (unchanged)"]
        WEB["Flask + gunicorn + nginx"]
        RUNNER["Self-hosted runner (fallback, manual only)"]
    end

    subgraph AWS["AWS — on-demand, fully ephemeral"]
        EC2["EC2 t4g.medium\nJenkins controller + agents (Docker Compose)"]
        SSM["SSM Parameter Store (SecureString)"]
    end

    subgraph Azure["Azure — on-demand, fully ephemeral"]
        AKS["AKS Free tier, 3x B2ats_v2 nodes"]
        GRAF["Grafana"]
        PROM["Prometheus"]
        LOKI["Loki"]
    end

    PW -- "push to main" --> DJ["deploy-jenkins-only workflow"]
    DJ -- "AWS OIDC, starts instance" --> EC2
    EC2 -- "SSH: pull, install, swap configs, restart" --> WEB
    PW -. "workflow_dispatch, manual fallback" .-> RUNNER
    RUNNER -- "git pull, restart" --> WEB

    IPW -- "deploy-everything button" --> EC2
    IPW -- "deploy-everything button" --> AKS
    IPW -- "destroy-everything button" --> EC2
    IPW -- "destroy-everything button" --> AKS

    SEC --> SSM
    SEC -. "injected as native K8s Secrets at deploy time" .-> AKS

    PROM -- "scrape" --> EC2
    PROM -- "scrape" --> WEB
    GRAF --> PROM
    GRAF --> LOKI
```

## Two independent lifecycle paths for Jenkins

1. **Built and working**: `perez_wiki`'s "Deploy via Jenkins" workflow (currently
   `workflow_dispatch`-only, not yet wired to real pushes) calls `deploy-jenkins-only.yml`
   here, which starts a fresh EC2 instance via AWS OIDC, waits for Jenkins via SSM Run
   Command, and triggers the `deploy-perez-wiki` job — which SSHes into the Linode box
   and performs the exact same steps the old self-hosted-runner workflow did (`git pull`,
   reinstall deps, swap the nginx/systemd config files, restart the service).
   **Known gap: this does NOT currently self-terminate the instance afterward** —
   it keeps running (and costing money) until manually destroyed. Adding an automatic
   teardown step is still pending.
2. **Not yet built**: manual "deploy everything" / "destroy everything" buttons that
   stand up (or tear down) the full Jenkins + monitoring environment together, for demos.

The old self-hosted-runner workflow in `perez_wiki` stays registered on the Linode
box as a **manual fallback** (`workflow_dispatch`, not auto-triggered), in case the
AWS/Jenkins path is ever broken.

## Repo layout

```
bootstrap/
  aws/      APPLIED. TF that creates the S3 bucket used as the remote state
            backend for aws/jenkins (SSE-S3, no customer-managed KMS key
            needed). Uses a deterministic account-ID-based bucket name and
            a guarded `import` block designed for belt-and-suspenders
            idempotent re-runs -- but that automatic create/import dance
            was never actually wired into `deploy-jenkins-only.yml`, which
            just assumes the bucket already exists (it does, applied
            manually once). See bootstrap/aws/README.md.
  azure/    NOT YET BUILT. Same idea, will create the Azure Storage Account
            + container used as the remote state backend for azure/monitoring.
aws/
  jenkins/
    iam/      APPLIED. OIDC provider + IAM roles -- applied once, manually,
              never destroyed by the on-demand lifecycle. Permission set
              grew from real CI errors (see project memory/history) --
              expect to revisit if new AWS actions get exercised later.
    compute/  WORKING. EC2 instance, security group, SSM parameters, Docker
              Compose (Jenkins + node_exporter) -- created every session via
              `terraform apply -replace="aws_instance.jenkins"` (needed
              because plain `apply` hasn't reliably detected user_data
              changes on this resource). Confirmed deploying successfully
              to the real Linode box via full GitHub Actions automation.
azure/
  monitoring/  NOT YET BUILT. Planned: AKS cluster (Free tier), node pool
               (3x B2ats_v2), Helm releases for Grafana/Prometheus/Loki,
               Kubernetes Secrets wiring, RBAC.
.github/workflows/
  deploy-jenkins-only.yml  BUILT, working. Reusable (on: workflow_call) --
                           applies aws/jenkins/compute (with -replace to
                           force a fresh instance every run), waits for
                           Jenkins via SSM Run Command (not a direct public
                           curl -- port 8080 is only open to admin_cidr,
                           which the runner isn't), then triggers the
                           deploy-perez-wiki job the same way (crumb fetch
                           + POST, both over SSM). Called today from
                           perez_wiki's "Deploy via Jenkins" workflow,
                           which is workflow_dispatch-only (manual button)
                           by design -- flip to `push: branches: [main]`
                           there once confident in this path.
  deploy-everything.yml    NOT YET BUILT. Planned: stands up both stacks + wiring.
  destroy-everything.yml   NOT YET BUILT. Teardown is still manual
                           `terraform destroy` for now.
```

## Secrets

Source of truth is GitHub Actions encrypted secrets. Materialized at deploy time,
never committed anywhere:

- **AWS side:** SSM Parameter Store, Standard tier, `SecureString` type, encrypted
  with the AWS-managed KMS key (`aws/ssm`) to stay completely free.
- **Azure side:** no Key Vault — injected directly into native Kubernetes Secrets
  at deploy time, since the AKS cluster is fully ephemeral anyway. RBAC is scoped
  per-ServiceAccount (`get` on a specific named Secret, never namespace-wide
  `list`), since native K8s Secrets are base64 in etcd, not encrypted — RBAC is
  the only real access boundary.

**Non-negotiable when writing the Terraform:** state backends must be remote and
encrypted (see `bootstrap/`) and never committed — `sensitive = true` only hides
values from CLI output, not from the state file itself. Secrets are never echoed
in workflow steps, always passed via `env:` (not CLI args), and any Terraform
variable/output touching one is marked `sensitive = true`.

## Cost (on-demand, fully ephemeral)

| Piece | Compute | Per demo-hour | Always-on equivalent (for context) |
|---|---|---|---|
| AWS: EC2 t4g.medium, Jenkins | ~$0.034/hr | ~$0.034/hr | ~$24.82/mo |
| Azure: AKS Free tier, 3x B2ats_v2 | ~$0.028/hr | ~$0.028/hr | ~$20.58/mo |

No NAT gateway, no load balancer, no EKS/AKS Standard-tier control-plane fee.
Everything (including state-backend-adjacent storage created outside `bootstrap/`)
is destroyed between sessions — see each module's README once it exists for exact
`terraform destroy` scope and any easy-to-miss lingering resources (Elastic
IPs/Public IPs left allocated-but-unattached, etc.). 

## Build order

1. ✅ `bootstrap/aws` — applied manually, once. (`bootstrap/azure` not started.)
2. ✅ `aws/jenkins` — EC2 + Docker Compose Jenkins, IAM/OIDC, SSM parameters.
   Applied and confirmed working via full GitHub Actions automation.
3. ⬜ `azure/monitoring` — AKS + Helm-installed Grafana/Prometheus/Loki, RBAC,
   Kubernetes Secrets wiring. Not started.
4. ⬜ Cross-cloud scrape config (Prometheus → Jenkins EC2 + Linode box exporters).
5. 🟡 `.github/workflows/` — `deploy-jenkins-only.yml` built and working
   (manual `workflow_dispatch` trigger only, not yet wired to real pushes,
   and doesn't yet self-terminate the instance after deploying).
   `deploy-everything.yml`/`destroy-everything.yml` not started.
6. ⬜ Log upload-on-deploy / download-on-teardown to the user's local machine
   (deferred — lowest priority, tackled after everything else is connected).
