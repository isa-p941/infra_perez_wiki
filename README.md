# infra_perez_wiki

Infrastructure for a Jenkins CI cluster (AWS) and a Grafana/Prometheus/Loki monitoring
stack (Azure), built around my [perez_wiki](https://www.perez.wiki) website.

**Status: scaffold only.** Nothing in `aws/` or `azure/` has real resources yet, and
nothing has been applied. See [Build order](#build-order) for what's next.

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

1. **Event-triggered, per real deploy.** A push to `perez_wiki`'s `main` branch
   triggers a workflow (living in the `perez_wiki` repo, calling into Terraform here)
   that starts the EC2 instance via AWS OIDC, runs a Jenkins job that SSHes into the
   Linode box and performs the exact same steps the old self-hosted-runner workflow
   did (`git pull`, reinstall deps, swap the nginx/systemd config files, restart the
   service), then self-terminates. This is what keeps real site deploys working
   without Jenkins running 24/7.
2. **Manual "deploy everything" / "destroy everything" buttons**, defined in this
   repo, that stand up (or tear down) the full Jenkins + monitoring environment
   together — for demos, not gating real deploys.

The old self-hosted-runner workflow in `perez_wiki` stays registered on the Linode
box as a **manual fallback** (`workflow_dispatch`, not auto-triggered), in case the
AWS/Jenkins path is ever broken.

## Repo layout

```
bootstrap/
  aws/      TF that creates the S3 bucket used as the remote state backend
            for aws/jenkins (SSE-S3, no customer-managed KMS key needed).
            Chicken-and-egg problem: you can't store state for the thing
            that creates your state storage. Solved without giving up on
            Terraform or a manual one-time apply: a deterministic
            account-ID-based bucket name plus a belt-and-suspenders
            create/import pattern (guarded `import` block + a
            `concurrency`-gated retry in the calling workflow) means this
            runs automatically, idempotently, on every deploy -- see
            bootstrap/aws/README.md for the full mechanics.
  azure/    same idea, creates the Azure Storage Account + container used as
            the remote state backend for azure/monitoring.
aws/
  jenkins/  EC2 instance, security group, IAM role + OIDC trust policy for
            GitHub Actions, SSM Parameter Store entries, Docker Compose
            user-data for the Jenkins controller + agent containers.
azure/
  monitoring/  AKS cluster (Free tier), node pool (3x B2ats_v2), Helm releases
               for Grafana/Prometheus/Loki, Kubernetes Secrets wiring, RBAC.
.github/workflows/
  deploy-everything.yml    workflow_dispatch — stands up both stacks + wiring
  destroy-everything.yml   workflow_dispatch — tears both stacks down
  deploy-jenkins-only.yml  reusable workflow, called from perez_wiki's
                           push-triggered path (the event-triggered lifecycle)
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

1. `bootstrap/aws` and `bootstrap/azure` — create the remote state backends.
   Both run automatically as part of the on-demand deploy workflows (no
   manual one-time apply) via a deterministic-naming + guarded-import
   pattern; see bootstrap/aws/README.md for the mechanics.
2. `aws/jenkins` — EC2 + Docker Compose Jenkins, IAM/OIDC, SSM parameters.
3. `azure/monitoring` — AKS + Helm-installed Grafana/Prometheus/Loki, RBAC,
   Kubernetes Secrets wiring.
4. Cross-cloud scrape config (Prometheus → Jenkins EC2 + Linode box exporters).
5. `.github/workflows/` — the two lifecycle paths described above.
6. Log upload-on-deploy / download-on-teardown to the user's local machine
   (deferred — lowest priority, tackled after everything else is connected).
