# aws/jenkins/iam

The prerequisite for automation.  Must be applied once mannually. Don't destroy
it or you'll need to run it again. Requires `bootstrap/aws` run first. Note the 
two outputs: `github_actions_role_arn` and `jenkins_instance_profile_name`, 
the GitHub Actions workflows need the role ARN, `compute/` needs the instance 
profile name.

Creates:

- GitHub OIDC provider (`token.actions.githubusercontent.com`)
- `infra-perez-wiki-github-actions-jenkins` role — assumable only by
  `perez_wiki`'s `main` branch workflows and any `infra_perez_wiki` workflow,
  scoped to exactly what's needed to manage `aws/jenkins/compute` (EC2
  lifecycle, security group, SSM parameters under `/infra-perez-wiki/*`,
  and this role's own Terraform state objects)
- `infra-perez-wiki-jenkins-instance` role + instance profile — assumed by
  the EC2 instance itself, scoped to reading its own SSM parameters plus
  `AmazonSSMManagedInstanceCore` (Session Manager shell access, no open
  SSH port)

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
