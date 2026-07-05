# aws/jenkins

Split into two Terraform configs with separate states. IAM inits everything we
need for connectivity and authentication, so it needs to be applied manually
then never destroyed by the one-button press.

- **`iam/`** — IAM config, applied once, manually, by hand. Never destroyed...
  unless you want to run this whole thing again manually.
- **`compute/`** — security group, EC2 instance (t4g.medium, Docker Compose
  running Jenkins + node_exporter), SSM parameters. Created on demand
  (confirmed working via full GitHub Actions automation) — **not yet
  automatically destroyed**, that's still a manual `terraform destroy`.

Both applied and confirmed working as of 2026-07-05. See each directory's
README for further details.
