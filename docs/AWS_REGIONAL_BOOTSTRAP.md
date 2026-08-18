# AWS regional bootstrap and readiness

## Current answer

The application is containerized and now has a valid one-region Terraform release root plus separate infrastructure plan/apply and application-deploy workflows. AWS is **not yet provisioned and the checked-in Terraform is not a complete production platform**. Do not describe it as deployed or production-ready merely because code and workflows exist.

For this workload, prefer Amazon EKS managed node groups over manually installing Kubernetes on private EC2 instances. Worker nodes still live in your private subnets, while AWS owns the control-plane installation and availability. AWS documents private-only API endpoints and the requirement that `kubectl` then run from the VPC or a connected network: [EKS cluster API endpoint access](https://docs.aws.amazon.com/eks/latest/userguide/cluster-endpoint.html). Managed nodes in private subnets require NAT or ECR/S3 VPC endpoints to pull images: [EKS managed node groups](https://docs.aws.amazon.com/eks/latest/userguide/managed-node-groups.html).

## What the repository already contains

| Area | Checked-in foundation | Proof still required |
|---|---|---|
| Containers | multi-stage, non-root frontend/backend Dockerfiles | image scan/signature/SBOM policy and registry pull test |
| Local environment | PostgreSQL + API + web Compose stack, doctor, smoke test | second-laptop clone execution |
| Kubernetes | deployments, services, probes, requests/limits, HPA, PDB, NetworkPolicy, three Kustomize region labels | live cluster render/apply, ingress, secrets, DNS/TLS, policy tests |
| CI | `main` builds/tests and publishes immutable SHA-tagged GHCR images | branch protection, required reviewers, artifact attestation enforcement |
| Release control | independent Terraform plan/apply workflows publish an applied infrastructure SHA; application deploy verifies it | protected GitHub Environments, bootstrapped OIDC roles, live release exercise |
| CD | explicit manual workflows copy the built SHA image into environment ECR before EKS rollout | private AWS runner/GitOps and canary/rollback test |
| Networking | Terraform VPC with three public/private subnets per region and EKS private API | reviewed CIDRs, endpoints/NAT strategy, flow logs, firewall/WAF, connectivity test |
| Compute | reusable one-region EKS root plus a future three-region reference; version is an explicit variable | live stage sizing, add-on compatibility and upgrade rehearsal |
| Registry | immutable frontend/backend ECR repositories in the active regional environment | cross-region replication or a repository per added region and admission policy |
| Data | private RDS PostgreSQL, AWS-managed master password, private SG from EKS, backups/deletion settings by stage | Flyway, restore test, connection/proxy sizing, production HA review |
| Contract | SSM parameters publish applied infra SHA, EKS name, ECR URLs, DB endpoint, and DB secret ARN | least-privilege reader policy and live verification |
| Identity | legacy GitHub OIDC ECR role reference | bootstrap separate infra/deploy roles with least privilege and stage/environment conditions |
| Observability | regional log group, dashboard, and alarm definition | actual Synthetics canary resource, SNS/Pager path, app metrics/traces/log shipping |

Important: the current alarm references a Synthetics canary name, but Terraform does not create the canary itself. Until that resource and its artifact bucket/runtime code exist, the dashboard/alarm are only scaffolding.

## Recommended low-scale topology

Start with one active region and one warm secondary. Add the third only after regional deployment and data-recovery drills are boring and repeatable.

```text
Users
  -> Route 53 health/latency policy + WAF
      -> Region A ALB -> EKS web/API -> primary PostgreSQL writer
      -> Region B ALB -> EKS web/API -> read replica / writer routing
      -> Region C later

Infrastructure main -> manual plan -> manual approved apply -> SSM release contract
Application main    -> test/build/scan -> immutable image
                    -> contract check -> ECR promotion -> private EKS rollout

Secrets Manager -> External Secrets -> Kubernetes Secret
CloudWatch/OTel -> dashboards -> alarms -> SNS/on-call
```

AWS provides an example of multi-region EKS with Aurora Global Database for low-latency regional reads: [Multi-Region application scaling with EKS and Aurora](https://docs.aws.amazon.com/solutions/multi-region-application-scaling-using-amazon-aurora/). That is a target pattern, not a feature the current API already supports.

### Database truth

The present Java API reads and writes through one JDBC URL. It has no read/write datasource split and cannot safely treat regional replicas as writable. Choose one of these explicit first-release modes:

1. **Recommended initial mode:** Region A serves traffic and owns the writer; Region B is warm standby and receives no normal writes. Failover is a runbook action.
2. **Intermediate:** all regions serve public reads, but creator/admin/checkout writes are routed to Region A. Add a writer endpoint and a read-only datasource before enabling this.
3. **Later active/active application:** only after conflict semantics, idempotency, session locality, cache invalidation, provider webhooks, and database failover behavior are designed and tested.

Aurora Global Database replicates data across regions, but it does not make arbitrary multi-writer application behavior automatic. Never point a write-capable generic JDBC pool at a read replica.

## Stage/account model

Use separate AWS accounts for `dev`, `preprod`, and `prod` when possible, under one organization. At minimum use separate state, clusters, databases, KMS keys, secrets, DNS names, IAM roles, GitHub Environments, budgets, and alarm routes.

| Stage | Initial regions | Deployment approval | Data |
|---|---:|---|---|
| dev | 1 | engineering | generated/non-sensitive |
| preprod | 1, then 2 for failover rehearsal | service owner | anonymized/synthetic |
| prod | 2 active/warm; third after evidence | on-call + change approval | real, encrypted, governed |

The active `terraform/environments/regional` root models one region for any one stage and uses a separate remote-state key per stage. The older `production` root is retained as a future three-region reference and is not targeted by the controlled release workflow. Do not use Terraform workspaces alone as the only security boundary for production.

## Provisioning order

### 0. Close application P0s

Do not expose the current API publicly. Complete authentication/authorization, migrations, rate limiting, validation, audit logging, verified-webhook order/ledger behavior, backup/restore behavior, and required product workflows from `FEATURE_PARITY.md`.

### 1. Establish AWS governance

- create stage accounts, IAM Identity Center access, break-glass process, budgets, CloudTrail, Config, GuardDuty/Security Hub policy, and an owner for security findings;
- select India launch regions and verify every required service/provider is available there;
- define RTO/RPO, data residency, retention/deletion, encryption, and incident requirements;
- create Route 53 hosted zone and decide subdomains for each stage/region.

### 2. Bootstrap Terraform state

From `terraform/bootstrap`, supply a globally unique state bucket name, review the plan, then apply once with an approved bootstrap identity. Configure each protected GitHub Environment with that encrypted/versioned S3 bucket and DynamoDB lock table. Keep `backend.hcl` and real tfvars untracked.

The code is formatted, provider/module selections are locked, and the active regional root validates with Terraform 1.10.5. It defaults to EKS Kubernetes 1.35, which AWS currently lists in standard support through March 27, 2027: [EKS Kubernetes version lifecycle](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html). Recheck support immediately before every infrastructure release; checked-in pins are a snapshot, not a promise of future AWS compatibility.

### 3. Release the one-region foundation

Merge an infrastructure PR, run **Plan infrastructure release** for the exact commit, review the text plan, then run **Apply infrastructure release** with the same commit and protected-environment approval. The apply creates the stage VPC/private EKS/ECR/RDS/SSM/CloudWatch foundation and publishes the applied commit SHA only after its contract resources succeed. Application workflows reject any other infrastructure SHA.

The workflow requires `AWS_INFRA_ROLE_ARN`, `AWS_REGION`, `VPC_CIDR`, `TF_STATE_BUCKET`, and `TF_STATE_LOCK_TABLE` in each GitHub Environment. The first OIDC/state roles are a one-time governance bootstrap; no workflow can safely create the authority it is currently using.

### 4. Complete network and EKS production controls

- three AZs per production region;
- public subnets only for internet-facing load balancers/NAT as designed;
- EKS managed nodes in private subnets;
- private Kubernetes API, reachable from a private runner, SSM-managed admin host, VPN, or connected network;
- one NAT gateway per AZ for production fault isolation, or a reviewed VPC-endpoint-heavy design; the current single NAT per region is a low-cost starting point, not HA;
- VPC flow logs, least-privilege security groups, KMS keys, ECR/S3/STS/Logs/Secrets endpoints as needed.

AWS's EKS guidance recommends carefully selecting endpoint mode and notes the subnet tags/controllers required for load balancers: [EKS VPC and subnet considerations](https://docs.aws.amazon.com/eks/latest/best-practices/subnets.html).

### 5. Install and own cluster add-ons

Install with pinned versions and an upgrade owner:

- AWS Load Balancer Controller with workload IAM;
- ExternalDNS;
- External Secrets Operator;
- metrics-server;
- EBS CSI (already declared as an EKS add-on in the foundation);
- CloudWatch/ADOT or an approved observability collector;
- cert-manager only if ACM/ALB termination does not cover the chosen path;
- Argo CD or private self-hosted GitHub runners for private-cluster delivery;
- policy enforcement and runtime/image controls.

AWS documents the IAM and cluster prerequisites for the controller: [Install AWS Load Balancer Controller](https://docs.aws.amazon.com/eks/latest/userguide/lbc-manifest.html). Pull-based Argo CD treats Git as desired-state source: [Continuous deployment with Argo CD on EKS](https://docs.aws.amazon.com/eks/latest/userguide/argocd.html).

### 6. Complete data and secrets

- the regional root creates RDS PostgreSQL in private subnets with encryption and an AWS-managed master secret; tune Multi-AZ, deletion protection, backups, monitoring, and instance class per stage and prove restore;
- RDS Proxy or a carefully sized pool if connection multiplication across Pods/regions requires it;
- Secrets Manager objects per stage/region for DB, Razorpay, optional Stripe, and Instagram;
- External Secrets sync into `creator-store-db` and `creator-store-runtime-secrets`;
- S3 buckets plus scanning/signing flow for uploads and downloads;
- never run the production database inside EKS.

### 7. Publish and promote artifacts

- GitHub OIDC assumes a narrow build role; no long-lived AWS key;
- build frontend/backend images in GHCR by immutable SHA, then let the manual deploy copy that exact image to environment ECR;
- scan, generate SBOM/provenance, sign, and enforce signature at admission;
- promote the exact digest from dev to preprod to prod;
- the application workflow verifies `/creator-store/<stage>/infrastructure-release`, resolves EKS/ECR/DB outputs from SSM, and a private runner applies the Kustomize release because the Kubernetes API is private;
- require GitHub Environment approval for preprod/prod and record change ticket, image digest, database migration, canary result, and rollback target.

### 8. Add ingress, TLS, DNS, and protection

- regional ALB created by AWS Load Balancer Controller;
- ACM certificate and HTTPS-only listener;
- WAF managed rules plus application-specific rate limits;
- Route 53 records and health checks with controlled failover/latency policy;
- regional `/health` plus a business canary that loads a known public store without external side effects.

### 9. Prove operations before launch

- unit, integration, API-contract, browser E2E, migration, performance, and provider-sandbox suites pass;
- canary/linear rollout, rollback, and failed-migration procedures are rehearsed;
- database point-in-time restore and regional promotion are timed against RTO/RPO;
- node/AZ/region/provider failure exercises are complete;
- dashboards cover request rate/error/duration/saturation, JVM/DB, queue/jobs, checkout/webhook lag, and regional synthetic success;
- every alarm has severity, threshold rationale, runbook link, and tested notification receiver.

## Go/no-go checklist for each new region

- [ ] CIDRs do not overlap connected networks or other regions.
- [ ] EKS/Kubernetes/add-on versions are supported and pinned.
- [ ] Private runner/GitOps can reach the Kubernetes API.
- [ ] Nodes pull the exact signed image digest.
- [ ] DB endpoint role is explicit: writer or read-only.
- [ ] Secrets sync without appearing in logs or Git.
- [ ] HTTPS/WAF/DNS health checks pass.
- [ ] `/health` and business canary pass from outside and inside the region.
- [ ] Logs, metrics, traces, dashboards, alarms, and on-call delivery work.
- [ ] Rollback and regional traffic removal are rehearsed.
- [ ] Cost budget and owner are recorded.

Only after this checklist and the application P0 list are closed should a region receive real user traffic.
