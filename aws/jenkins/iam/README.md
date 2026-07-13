# aws/jenkins/iam

The prerequisite for automation.
Must be applied once manually. Don't destroy it or you'll need to run it
again. Requires `bootstrap/aws` run first. Three outputs:
`github_actions_role_arn`, `jenkins_instance_profile_name`,
`jenkins_instance_role_arn`. The GitHub Actions workflows need the role
ARN, `compute/` needs the instance profile name.

Creates:

- GitHub OIDC provider (`token.actions.githubusercontent.com`)
- `infra-perez-wiki-github-actions-jenkins` role, assumable only by
  `perez_wiki`'s `main` branch workflows and any `infra_perez_wiki`
  workflow. Permission set covers EC2 lifecycle, the several read-only
  Describe* actions the AWS provider needs during normal refresh
  (`DescribeInstanceAttribute`, `DescribeInstanceTypes`, `DescribeVolumes`,
  `DescribeInstanceCreditSpecifications`, etc.), security group
  management, SSM parameter management under `/infra-perez-wiki/*` (plus
  `DescribeParameters`/`ListTagsForResource`, which the provider also
  needs), **SSM Run Command** (`SendCommand`/`GetCommandInvocation`/
  `ListCommandInvocations`, used by `deploy-jenkins.yml` to check
  Jenkins's readiness and trigger the deploy job over SSM instead of the
  public network, since port 8080 is only open to `admin_cidr`), and this
  role's own Terraform state objects. Most of these were found empirically
  from actual `AccessDeniedException` errors during CI runs.
- `infra-perez-wiki-jenkins-instance` role and instance profile, assumed
  by the EC2 instance itself, scoped to reading its own SSM parameters
  plus `AmazonSSMManagedInstanceCore` (Session Manager shell access, no
  open SSH port).
- A persistent Elastic IP for the Jenkins box. It lives here (not in the
  ephemeral `compute/`) so the address stays the same across redeploys,
  which lets Prometheus scrape the box at a fixed target. `compute/`
  attaches it. The GitHub Actions policy also gained
  `ec2:AssociateAddress`/`DisassociateAddress`/`DescribeAddresses` for that
  attach step. Costs ~$3.60/mo while allocated with Jenkins torn down
  (free while attached to a running instance).

## Applying (manual, one-time)

```
cd aws/jenkins/iam
terraform init \
  -backend-config="bucket=<bootstrap output: state_bucket_name>" \
  -backend-config="region=<bootstrap output: state_bucket_region>" \
  -backend-config="key=aws-jenkins-iam/terraform.tfstate" \
  -backend-config="use_lockfile=true"
terraform plan
terraform apply
```
