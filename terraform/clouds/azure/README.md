# Azure regional foundation

This root provisions a private AKS cluster, Azure CNI overlay networking, OIDC/Workload Identity, the API service account's federated managed identity, ACR, Log Analytics, and private Azure Database for PostgreSQL Flexible Server. It creates infrastructure only; application deployment remains a separate exact-SHA release. Put `creator_store_workload_identity_client_id` into the Azure Kustomize overlay before deployment.

Use an Azure Storage `azurerm` backend in production. Configure it during `terraform init` rather than committing account/container names or credentials. Supply the PostgreSQL password through `TF_VAR_postgres_admin_password`; remember that Terraform state contains sensitive inputs, so encrypt and tightly restrict the state backend.

```bash
az login
terraform init -reconfigure \
  -backend-config="resource_group_name=<state-resource-group>" \
  -backend-config="storage_account_name=<state-account>" \
  -backend-config="container_name=<state-container>" \
  -backend-config="key=dev.tfstate"
terraform plan -var-file=terraform.tfvars -out=tfplan
terraform apply tfplan
az aks get-credentials --resource-group "$(terraform output -raw resource_group_name)" --name "$(terraform output -raw cluster_name)"
```

The cluster API is private. Run `kubectl` and the deployment runner from a network path that can resolve and reach the AKS private endpoint.

For a credential-free syntax check only, use `terraform init -backend=false && terraform validate`.
