# Infrastructure-first release architecture

## Repository and release boundaries

The system has three independently versioned repositories and two independent release types:

| Repository | Owns | Produces | Does not do |
|---|---|---|---|
| `creator-link-store-infrastructure` | VPC, private EKS, managed nodes, ECR, RDS PostgreSQL, CloudWatch foundation, environment contract | reviewed Terraform plan and applied infrastructure release SHA | build or deploy application source |
| `creator-link-store-backend` | Spring Boot API, schema contract, Kubernetes workload definition | tested JAR and `sha-<commit>` container | create AWS resources |
| `creator-link-store-frontend` | React/Vite UI, NGINX runtime, Kubernetes workload definition | tested static bundle and `sha-<commit>` container | create AWS resources |

An application change that needs infrastructure follows two pull requests and two releases. An application-only change skips the infrastructure release and reuses the already active infrastructure SHA.

```text
Infrastructure PR
  -> quality + Terraform validation
  -> merge
  -> Plan infrastructure release (exact infra SHA)
  -> human reviews plan
  -> Apply infrastructure release (same exact infra SHA, protected environment)
  -> Terraform publishes /creator-store/<stage>/infrastructure-release

Application PR
  -> unit/integration/build/scan
  -> merge
  -> main builds ghcr.io/...:sha-<application SHA>
  -> Deploy frontend/backend (application SHA + required infrastructure SHA)
  -> workflow verifies AWS release marker
  -> workflow copies immutable image into environment ECR
  -> private runner deploys to the EKS cluster named by the infrastructure contract
```

The infrastructure marker depends on the regional VPC/EKS foundation, ECR repositories, RDS instance, observability foundation, and all other published SSM contract values. An application workflow therefore cannot accept a Terraform commit that was merely merged or planned; it accepts only the commit recorded by a completed apply.

## Environment isolation

`terraform/environments/regional` is the active low-scale root. The same reviewed code is instantiated with independent remote state and protected GitHub Environment variables for `dev`, `preprod`, and `prod`. Each stage receives a separate VPC, EKS cluster, ECR repositories, RDS instance, Secrets Manager-managed database password, Parameter Store namespace, approvals, and AWS roles.

The remote state key is `<stage>/regional.tfstate`; this is stronger isolation than Terraform workspaces alone. For a single-region start, configure only `region-a`. Add another regional state instance only after failover and data-routing design is complete.

The older `terraform/environments/production` directory is a three-region reference topology. It is formatted and syntactically maintained, but the controlled release workflows deliberately target the single-region `regional` root until ingress, global data, and failure semantics are implemented.

## Required GitHub Environment configuration

Create protected GitHub Environments named `dev`, `preprod`, and `prod` in all three repositories. Configure these non-secret variables in the infrastructure repository:

| Variable | Meaning |
|---|---|
| `AWS_INFRA_ROLE_ARN` | OIDC role allowed to plan/apply only the stage resources |
| `AWS_REGION` | physical AWS region for that stage |
| `VPC_CIDR` | non-overlapping VPC CIDR |
| `TF_STATE_BUCKET` | encrypted/versioned bootstrap state bucket |
| `TF_STATE_LOCK_TABLE` | bootstrap DynamoDB lock table |

Configure these in each application repository:

| Variable | Meaning |
|---|---|
| `AWS_DEPLOY_ROLE_ARN` | OIDC role allowed to read the stage contract, publish to its ECR, read the DB secret (backend only), and access its EKS cluster |
| `AWS_REGION_A` | physical region for `region-a` |
| `AWS_REGION_B`, `AWS_REGION_C` | configure only when those regional contracts exist |

Protect `preprod` and `prod` with required reviewers. The workflow also requires a change-ticket string for those stages. AWS OIDC trust policies must match the GitHub Environment subjects; do not create long-lived AWS access keys.

## Release sequence

1. Run **Plan infrastructure release** with stage, exact 40-character infrastructure commit, and change ticket when required.
2. Download/read `release-plan.txt`; verify replacement, RDS, EKS, IAM, cost, and rollback impact.
3. Run **Apply infrastructure release** with the same commit. GitHub Environment approval is the release gate.
4. Confirm the workflow verifies the Parameter Store release marker.
5. Let frontend/backend `main` workflows build their immutable SHA artifacts.
6. Run **Deploy backend** and **Deploy frontend** with their application SHA and the applied infrastructure SHA.

The apply workflow intentionally recreates a plan from the immutable commit immediately before apply. For stricter production control, add signed plan promotion or Terraform Cloud with policy checks; never apply an artifact from an untrusted fork.

## Feature-change decision

| Change | Infrastructure release first? | Application release |
|---|---:|---|
| UI text/layout or Java business rule | No | frontend or backend SHA |
| New environment variable using an existing ConfigMap/Secret | Usually no; secret value is an operational change | affected application |
| New SQS queue, cache, bucket, database, IAM permission, alarm, or load balancer behavior | Yes | deploy compatible application after apply |
| Database column/table | Usually migration release first, not raw Terraform | deploy backward-compatible reader/writer |
| Destructive schema cleanup | Separate later release | only after old application versions cannot run |

Use expand/migrate/contract for database changes: add compatible schema, deploy code that handles old and new states, backfill/verify, then remove old schema in a later approved change. A Kubernetes rollback cannot undo an incompatible database migration.

## Current boundary

The release orchestration and one-region VPC/EKS/ECR/RDS contract are implemented as code, but no AWS apply has been performed. Production launch still requires authentication/authorization, Flyway/Liquibase migrations, AWS Load Balancer Controller, TLS/DNS/WAF, a private runner, least-privilege IAM, real canaries and paging, backup/restore proof, artifact signing/admission, and load/security/failure testing.
