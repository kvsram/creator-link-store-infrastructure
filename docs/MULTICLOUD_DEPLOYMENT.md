# Cloud-neutral deployment contract

The application release is Kubernetes-native and does not call AWS, Azure, or OCI APIs. The same frontend and backend OCI images run on EKS, AKS, or OKE. Cloud differences are isolated to `k8s/overlays/<cloud>`, infrastructure provisioning, workload identity, secret synchronization, managed PostgreSQL, ingress, and RWX storage.

## Common contract

Every environment must provide:

1. A private Kubernetes cluster reachable by a self-hosted GitHub runner carrying labels `k8s-private`, `<cloud>`, and `<environment>`.
2. PostgreSQL 16 with TLS, backups, point-in-time recovery, and a private endpoint. Expose only `DB_URL`, `DB_USER`, and `DB_PASSWORD` through the `creator-store-runtime-secrets` Secret.
3. An NGINX Ingress controller, cert-manager, DNS, and the `creator-store-tls` Secret.
4. A ReadWriteMany storage class for `creator-store-uploads`. The current imported fulfillment implementation uses a shared filesystem. Object storage is the recommended next migration before high scale.
5. External Secrets (or an equivalent operator) to materialize database, payment, and Meta credentials. No cloud secret identifiers are embedded in the application.
6. Metrics Server for HPA, centralized logs, alerts, and a private deployment runner.

Replace every `replace-with-*` value in the selected overlay before deployment. Render locally with:

```bash
kubectl kustomize k8s/overlays/azure
kubectl kustomize k8s/overlays/oci
```

## Azure

- AKS with OIDC issuer and Microsoft Entra Workload ID enabled.
- Azure Database for PostgreSQL Flexible Server on a private endpoint.
- Azure Files CSI RWX storage class.
- Key Vault plus External Secrets, Azure DNS, Application Gateway or NGINX ingress, and Azure Monitor.
- The service account annotation is `azure.workload.identity/client-id`; the API pod has the mandatory `azure.workload.identity/use: "true"` label.
- [`terraform/clouds/azure`](../terraform/clouds/azure/README.md) provisions the regional VNet, private AKS, ACR, Log Analytics, private PostgreSQL, and the API service account's federated identity. Its provider configuration is schema-validated; no subscription has been planned or applied.

## OCI

- Enhanced OKE cluster with workload identity and private worker/API networking.
- OCI Database with PostgreSQL (or a supported private PostgreSQL service) with backups and TLS.
- OCI File Storage for the RWX claim, OCI Vault plus External Secrets, OCI DNS, and Logging/Monitoring.
- OKE workload identity is scoped by cluster, namespace, and service account in IAM policy; it does not require an AWS/Azure-style service-account annotation.
- [`terraform/clouds/oci`](../terraform/clouds/oci/README.md) provisions the VCN, public load-balancer subnet, private API/workers/database subnets, enhanced OKE, a workload mapping, and OCI Database with PostgreSQL backed by an existing Vault secret. Its provider configuration is schema-validated; no tenancy has been planned or applied.

## What to purchase or enable for one test region

- One managed Kubernetes cluster with two modest worker nodes: EKS, private AKS, or enhanced OKE.
- One private PostgreSQL 16 instance; a burstable/development SKU is enough for dev.
- One container registry, centralized logs, DNS zone, TLS certificates, and an RWX filesystem while the imported fulfillment code still uses shared uploads.
- One small private CI runner in the cluster network. It needs cloud identity and Kubernetes deployment rights, not long-lived cloud keys.
- A protected remote Terraform state backend and the cloud's secret manager.

Start with only one provider. The provider folders are independent state roots; deploying Azure does not require AWS, and deploying OCI does not require Azure.

## Release order

```text
infrastructure PR -> cloud plan -> approved cloud apply -> validate cluster contract
application commits -> tests/build/SBOM -> immutable GHCR SHA images
manual deploy-applications workflow -> server-side dry run -> rollout -> smoke/canary
```

The portable workflow never stores a kubeconfig in GitHub. Each private runner is attached to exactly one cloud/stage and receives least-privilege cluster credentials from its host identity.
