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

## OCI

- Enhanced OKE cluster with workload identity and private worker/API networking.
- OCI Database with PostgreSQL (or a supported private PostgreSQL service) with backups and TLS.
- OCI File Storage for the RWX claim, OCI Vault plus External Secrets, OCI DNS, and Logging/Monitoring.
- OKE workload identity is scoped by cluster, namespace, and service account in IAM policy; it does not require an AWS/Azure-style service-account annotation.

## Release order

```text
infrastructure PR -> cloud plan -> approved cloud apply -> validate cluster contract
application commits -> tests/build/SBOM -> immutable GHCR SHA images
manual deploy-applications workflow -> server-side dry run -> rollout -> smoke/canary
```

The portable workflow never stores a kubeconfig in GitHub. Each private runner is attached to exactly one cloud/stage and receives least-privilege cluster credentials from its host identity.
