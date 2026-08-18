# Creator Link Store workspace and AWS foundation

This is the entry repository for the complete Creator Link Store system. It coordinates three independently versioned GitHub repositories:

| Component | Repository | Local folder | Local port |
|---|---|---|---:|
| React/Vite frontend | [creator-link-store-frontend](https://github.com/kvsram/creator-link-store-frontend) | `frontend` | 3000 |
| Java/Spring Boot API | [creator-link-store-backend](https://github.com/kvsram/creator-link-store-backend) | `backend` | 8080 |
| Docker/Kubernetes/Terraform | [creator-link-store-infrastructure](https://github.com/kvsram/creator-link-store-infrastructure) | `infrastructure` | — |
| PostgreSQL 16 | official container locally; private RDS PostgreSQL in the regional Terraform root | Docker volume | 5432 |

## What is guaranteed today

A clean clone can start a deterministic three-container application with an admin SPA, a public creator page, a Java API, and PostgreSQL. The included smoke test verifies the supported API/UI contract. Payments and Instagram are disabled by default, so a fresh local run cannot send a message or create a real charge.

This is an original creator-commerce implementation based on the observable feature reference supplied for this project. It is not Stan source code and does **not** claim byte-for-byte parity with Stan's private responses. Read [Feature parity and test scope](docs/FEATURE_PARITY.md) before treating a section as complete.

## Fastest setup on another laptop

Install Git and Docker Desktop (or Docker Engine with Compose v2), then run:

```bash
mkdir creator-store-workspace
cd creator-store-workspace
git clone https://github.com/kvsram/creator-link-store-infrastructure.git infrastructure
cd infrastructure
./scripts/bootstrap-local.sh
```

The bootstrap script is idempotent: it clones the missing `frontend` and `backend` siblings, validates prerequisites, builds the images, starts all containers, and runs the smoke test. It never deletes an existing checkout or database volume.

Open:

- Admin: `http://localhost:3000/dashboard/`
- Demo public store: `http://localhost:3000/alex`
- API health: `http://localhost:8080/health`

The deterministic clean-database demo is creator `alex`, creator ID `1`. See [Local setup and troubleshooting](docs/LOCAL_SETUP.md) for Windows/WSL, Apple Silicon, manual startup, persistence, environment variables, and common failures.

## Everyday commands

Run these from `infrastructure/`:

```bash
make doctor    # verify the laptop and sibling layout
make up        # build and start without deleting data
make smoke     # verify the supported end-to-end contract
make logs      # follow all container logs
make config    # render and validate the Compose model
make down      # stop containers; preserve PostgreSQL data
```

Real integration test credentials belong only in the ignored `local/.env` file. Copy `local/.env.example`, keep modes at `disabled` until ready, use provider sandbox credentials, and switch only the integration under test to `test`. Never commit credentials. The [India integrations guide](docs/india-launch-integrations.md) covers Razorpay, optional Stripe, signed webhooks, Instagram restrictions, and go-live gates.

## Read this repository in this order

For a person or another AI taking over the workspace:

1. [AI handoff](docs/AI_HANDOFF.md) — repository map, invariants, commands, and safe extension order.
2. [Feature parity](docs/FEATURE_PARITY.md) — what is end-to-end, partial, a boundary only, or not implemented.
3. [API contract](docs/api-contract.md) — implemented methods, paths, and response meanings.
4. [Product design](docs/product-design.md) — section-by-section frontend/backend/data flow.
5. [AWS regional bootstrap](docs/AWS_REGIONAL_BOOTSTRAP.md) — what exists, what remains, and the safe provisioning order.
6. [Infrastructure-first releases](docs/release-architecture.md) — separate plans/applies, application promotion, and environment contract.
7. [Backend architecture](docs/backend-architecture.md) — Spring Boot MVC/layer responsibilities.
8. [Production runbook](docs/production-runbook.md) — release, canary, rollback, and incident operations.

`workspace-manifest.json` is the machine-readable component map.

## Delivery model

Every `main` commit in the frontend or backend repository runs its build/test workflow and publishes a SHA-addressed OCI image to GHCR:

```text
ghcr.io/kvsram/creator-link-store-frontend:sha-<git-sha>
ghcr.io/kvsram/creator-link-store-backend:sha-<git-sha>
```

That is a build artifact, not a deployment. Infrastructure has independent manual plan/apply workflows. A successful infrastructure apply publishes its exact Git SHA and regional outputs to AWS Parameter Store. Application deployment is a later, manually approved workflow for `dev`, `preprod`, or `prod`; it refuses to deploy unless its required infrastructure SHA is the one actually applied, copies the immutable application image into the environment ECR, and promotes that exact image. Read [Infrastructure-first releases](docs/release-architecture.md).

## AWS status and target

No AWS resource has been created by this repository. Terraform only acts after an operator supplies an AWS account, regions, CIDRs, and state configuration and explicitly runs `terraform apply`.

The intended path is:

```text
GitHub main commit -> test/build/scan -> immutable image
                                    -> manual approved promotion

Route 53 / edge protection
  -> one regional ALB per active region
  -> private EKS managed nodes
       -> frontend Service -> backend Service
       -> regional/private managed PostgreSQL connection
```

For this application, use Amazon EKS rather than manually installing Kubernetes with `kubeadm` on private EC2 instances. EKS still runs worker instances in private subnets but removes control-plane installation, patching, and quorum ownership from this project. The active `terraform/environments/regional` root provisions a one-region VPC/private EKS/ECR/RDS/SSM/CloudWatch foundation for one stage. It is not a turn-key public production environment: ingress add-ons, TLS/DNS/WAF, private delivery runner, real synthetics/paging, migrations, authentication, and operational proof remain. The exact inventory and gates are in [AWS regional bootstrap](docs/AWS_REGIONAL_BOOTSTRAP.md).

## Safety boundaries

- Local payments and Instagram are `disabled` by default.
- Currency values are integers in the smallest unit (`paise` for INR).
- Browser payment completion is not authoritative; a verified, idempotently recorded provider webhook is required.
- Secrets stay in ignored local environment files or AWS Secrets Manager, never Git or ConfigMaps.
- PostgreSQL is not deployed as a Pod in the multi-region production topology.
- The current API has no login session/JWT authorization. It is suitable for local functional testing, not public production traffic, until the P0 items in the parity matrix are completed.
- `make down` preserves data. Database deletion is deliberately not included in the normal command set.
