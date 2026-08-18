# Creator Link Store: AWS production foundation

## Run the complete application locally

Clone the three repositories as sibling folders with these exact local names:

```bash
mkdir creator-store-workspace && cd creator-store-workspace
git clone https://github.com/kvsram/creator-link-store-frontend.git frontend
git clone https://github.com/kvsram/creator-link-store-backend.git backend
git clone https://github.com/kvsram/creator-link-store-infrastructure.git infrastructure
docker compose -f infrastructure/local/docker-compose.yml up --build
```

Open the admin at `http://localhost:3000/dashboard/`, the demo public store at `http://localhost:3000/alex`, and the API health endpoint at `http://localhost:8080/health`. PostgreSQL is exposed at port 5432 for local inspection. Use `docker compose -f infrastructure/local/docker-compose.yml down` to stop it, or add `-v` only when you intentionally want to delete local database data.

The [product design](docs/product-design.md) explains every frontend section, backend flow, inferred data model, optimizations, and scale path. The [API contract](docs/api-contract.md) lists the implemented endpoints and representative deterministic responses.

This repository is infrastructure-as-code only. It creates nothing until an operator supplies account/region/domain inputs and explicitly runs Terraform in an approved AWS account.

## Target topology

```
Route 53 latency + health-check routing
  -> regional ALBs (three AWS regions)
  -> EKS: web -> API (regional)
  -> Aurora PostgreSQL Global Database (one writer, regional read replicas)

GitHub Actions --OIDC--> AWS IAM --push--> ECR
CloudWatch/Synthetics/Container Insights --> alarms + dashboard
```

`region-a` is the writer region. `region-b` and `region-c` are read regions at first. The current Java API performs writes, so a production application must route writes to the writer endpoint and only use replicas for explicitly read-only public-page queries. Do not point arbitrary writes at a replica.

## Delivery before AWS purchase

Until AWS exists, each `main` commit in the application repositories runs quality/build work and publishes a SHA-tagged immutable OCI image to GitHub Container Registry: `ghcr.io/kvsram/creator-link-store-<component>:sha-<commit>`. This is an artifact, never an automatic deployment. An on-call engineer later chooses that exact SHA in a manual GitHub Actions promotion for `dev`, `preprod`, or `prod`.

When AWS is available, migrate the same immutable image flow to ECR by changing the registry step to GitHub OIDC → ECR. Do not change the SHA or rebuild during promotion.

## Safe bootstrap order

1. Create a dedicated AWS production account and a separate Terraform state account/bucket; enable CloudTrail, GuardDuty, Security Hub, and billing alerts at account level.
2. In `terraform/bootstrap`, create the encrypted S3 state bucket and DynamoDB lock table once. Copy `backend.hcl.example` to an untracked `backend.hcl`.
3. Copy `terraform/environments/production/terraform.tfvars.example` to an untracked `terraform.tfvars`; replace account ID, domain, CIDRs, and region choices.
4. Run `terraform init -backend-config=../../backend.hcl`, `terraform plan`, have the plan reviewed, then explicitly apply.
5. Configure the GitHub Environment secrets/variables named in `docs/github-oidc.md`. Use GitHub OIDC; never store long-lived AWS access keys in GitHub.

## Deliberate production boundaries

- EKS API endpoints are private. Delivery should be pull-based (Argo CD) or run from CodeBuild/self-hosted runners inside the VPC—never open EKS to the internet merely to make hosted CI convenient.
- Database credentials belong in Secrets Manager and are synced by External Secrets; the app repositories contain only placeholder Secret templates.
- Terraform creates the network/EKS/ECR/IAM/observability foundation. AWS Load Balancer Controller and ExternalDNS create regional ALBs and DNS records after cluster add-ons are installed.
- The supplied CloudWatch Synthetics canaries are regional black-box tests. They test health and public-page availability after the real regional DNS names are set.

See `docs/production-runbook.md` for rollout, rollback, alarms, and failure handling.
