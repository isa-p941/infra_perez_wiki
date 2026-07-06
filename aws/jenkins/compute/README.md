# aws/jenkins/compute

**Status: confirmed working**, deployed successfully through full GitHub Actions
automation (`perez_wiki`'s "Deploy via Jenkins" button triggers `deploy-jenkins-only.yml`).

The ephemeral half: security group, EC2 instance, and the SSM parameters
Jenkins needs at boot time.

What the instance runs:

- **Jenkins controller** (`jenkins/jenkins:lts-jdk17`), configured entirely
  via JCasC (`jcasc/jenkins.yaml`): one `admin` user, one pipeline job
  (`deploy-perez-wiki`) that SSHes into the Linode box as the dedicated
  `jenkins-deploy` user and runs the same steps the self-hosted-runner
  workflow did. The Docker socket is mounted so the Docker plugin can spin
  up build agents as containers on demand, instead of running separate
  long-lived agent containers.
- **node_exporter**, basic-auth protected, scraped by the Prometheus in
  `azure/monitoring/aks` (this scrape config is still not wired up, only
  the Linode box's `node_exporter` is scraped so far).

Secrets (Linode SSH key, node_exporter auth hash, Jenkins admin password)
are written to SSM as `SecureString` parameters by Terraform, then read back
by the instance at boot (through its own scoped IAM role) into
`/opt/jenkins/secrets` on the host. That directory is bind-mounted
read-only into the Jenkins container at `/run/secrets`, not
`/var/jenkins_home/secrets`. That path is Jenkins's own reserved internal
directory, and mounting over it broke the boot the first time around.

Shell access, if ever needed, goes through AWS Systems Manager Session
Manager via IAM. No SSH port is open.

## Automated path (primary, how this actually gets used)

`perez_wiki`'s "Deploy via Jenkins" workflow (currently `workflow_dispatch`
only) calls this repo's `deploy-jenkins-only.yml`, which runs `terraform
apply -replace="aws_instance.jenkins"`. The `-replace` is required every
time, since plain `apply` hasn't reliably detected changes to `user_data`
on this resource (see project history/memory for the underlying
`user_data_replace_on_change` quirk). It then waits for Jenkins and
triggers the deploy job over SSM Run Command, not the public network,
since port 8080 is only open to `admin_cidr`.

## Manual apply (for testing/debugging)

```
cd aws/jenkins/compute
terraform init \
  -backend-config="bucket=<bootstrap output>" \
  -backend-config="region=<bootstrap output>" \
  -backend-config="key=aws-jenkins-compute/terraform.tfstate" \
  -backend-config="use_lockfile=true"
terraform apply -replace="aws_instance.jenkins" \
  -var="admin_cidr=<your IP>/32" \
  -var="linode_ssh_private_key=..." \
  -var="exporter_basic_auth_hash=..." \
  -var="jenkins_admin_password=..."
```

Requires manual run of `aws/jenkins/iam` during first deployment.

## Tearing down

Nothing tears this down automatically after a deploy. It keeps running,
and costing money, until destroyed. Use the **"Destroy Jenkins"** workflow
(`.github/workflows/destroy-jenkins.yml`, `workflow_dispatch`, run
directly from this repo's Actions tab) instead of a local
`terraform destroy`. Same effect, but callable from anywhere, no local
Terraform or AWS credentials needed. Needs its own copy of the 4 secrets
configured on `infra_perez_wiki` directly, not inherited from `perez_wiki`.
