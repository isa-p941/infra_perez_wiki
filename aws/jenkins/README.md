# aws/jenkins

Split into two Terraform configs with separate states. IAM sets up
everything needed for connectivity and authentication, so it's applied
manually and never destroyed by the one-button press.

- **`iam/`**: IAM config, applied once, manually, by hand. Never
  destroyed, unless you want to run this whole thing again manually.
- **`compute/`**: security group, EC2 instance (t4g.medium, Docker Compose
  running Jenkins + node_exporter), SSM parameters. Created on demand,
  confirmed working through full GitHub Actions automation. Not yet
  automatically destroyed, that's still a manual `terraform destroy`.

Both applied and confirmed working as of 2026-07-05. See each directory's
README for details.
