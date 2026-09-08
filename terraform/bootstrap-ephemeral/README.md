# Ephemeral test state bootstrap

This root creates only an encrypted, versioned, private S3 bucket for the
short-lived K3s/RDS environment's Terraform state. It uses free SSE-S3
encryption and native S3 state locking, so it does not create a paid KMS key or
a DynamoDB lock table.

Run it once with a reviewed plan from a non-root administrator session. Keep
the generated local state and real `terraform.tfvars` untracked. The bucket has
`prevent_destroy` because deleting test infrastructure must never delete its
audit trail.

Initialize the environment root with a backend file like:

```hcl
bucket       = "replace-with-the-created-bucket"
key          = "creator-link-store/ephemeral/devtest-us-east-2.tfstate"
region       = "us-east-2"
encrypt      = true
use_lockfile = true
```
