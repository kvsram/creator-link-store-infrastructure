# OCI regional foundation

This root provisions a VCN, public load-balancer subnet, private OKE API and worker subnets, an enhanced OKE cluster, managed node pool, and private OCI Database with PostgreSQL. The database password is read by the service from an existing OCI Vault secret version; plaintext is not accepted by this root.

The default provider auth is `InstancePrincipal`, intended for a private GitHub Actions runner in OCI. For a local plan, use an OCI CLI security-token profile in an untracked tfvars file. The OKE version and compatible node image OCID are explicit inputs so upgrades are reviewed instead of silently selected.

OCI's Terraform provider does not itself provide a native Terraform state backend. Configure an approved remote backend (Terraform Cloud or an encrypted OCI Object Storage S3-compatible backend) before any shared environment apply.

```bash
terraform init -reconfigure \
  -backend-config="address=<https-state-service>/dev" \
  -backend-config="lock_address=<https-state-service>/dev/lock" \
  -backend-config="unlock_address=<https-state-service>/dev/lock"
terraform plan -var-file=terraform.tfvars -out=tfplan
terraform apply tfplan
oci ce cluster create-kubeconfig --cluster-id "$(terraform output -raw cluster_id)" --token-version 2.0.0
```

The Kubernetes endpoint is private. The deployment runner must run in the VCN or through an approved private network path.

For a credential-free syntax check only, use `terraform init -backend=false && terraform validate`.
