# bootstrap/aws

Creates the AWS resources needed to hold Terraform state
for `aws/jenkins`:

- S3 bucket for state. Versioned, SSE-S3 (AES256) encrypted, all public
  access blocked, bucket policy denies any non-TLS request.

## Design intent vs. what's actually wired up

`main.tf` is written to support a belt-and-suspenders idempotent bootstrap:
a deterministic account-ID-based bucket name (no coordination needed with
other configs) plus a `bucket_already_exists` variable gating a native
`import` block, so re-running this with `terraform apply` is safe whether
the bucket already exists or not.

**That automatic create-or-import dance was never actually wired into
`deploy-jenkins.yml`.** In practice, this config was applied manually,
once (`terraform apply -var="bucket_already_exists=false"`). The actual
workflow just computes the deterministic bucket name and assumes it
already exists. It doesn't try to create it, retry on conflict, or import
anything. If this bucket were ever deleted, the workflow would start
failing until someone manually re-ran this config.

## Local dry run / re-applying manually

```
cd bootstrap/aws
terraform init
terraform plan -var="bucket_already_exists=false"   # or =true if it already exists
```

Requires AWS CLI credentials already configured (`aws sts get-caller-identity`
to verify). Creates a live S3 bucket.
