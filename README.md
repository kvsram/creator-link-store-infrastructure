# Creator Link Store workspace and multi-cloud Kubernetes foundation

This is the entry repository for the complete Creator Link Store system. It coordinates three independently versioned GitHub repositories:

| Component | Repository | Local folder | Local port |
|---|---|---|---:|
| React/Vite frontend | [creator-link-store-frontend](https://github.com/kvsram/creator-link-store-frontend) | `frontend` | 3000 |
| Java/Spring Boot API | [creator-link-store-backend](https://github.com/kvsram/creator-link-store-backend) | `backend` | 8080 |
| Docker/Kubernetes/Terraform | [creator-link-store-infrastructure](https://github.com/kvsram/creator-link-store-infrastructure) | `infrastructure` | — |
| PostgreSQL 16 | official container locally; private RDS PostgreSQL in the regional Terraform root | Docker volume | 5432 |
| Mailpit development inbox | official container, local only | Docker service | 8025 |

## What is guaranteed today

A clean clone can start a deterministic four-container development system with an admin SPA, a public creator page, a Java API, PostgreSQL, and a local-only Mailpit inbox. The included smoke tests verify the base contract and all eight product-type authoring flows. Payments and Instagram are disabled by default, so a fresh local run cannot send an Instagram message or create a real charge. Authentication email is delivered only to Mailpit and never leaves the laptop.

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
- Local authentication inbox: `http://localhost:8025`

The deterministic clean-database demo is creator `alex`, creator ID `1`. See [Local setup and troubleshooting](docs/LOCAL_SETUP.md) for Windows/WSL, Apple Silicon, manual startup, persistence, environment variables, and common failures. Follow [Authentication end-to-end](docs/AUTHENTICATION_E2E.md) to prove signup, email verification, login, logout, forgot-password, reset, and session revocation with no external email account.

## Everyday commands

Run these from `infrastructure/`:

```bash
make doctor    # verify the laptop and sibling layout
make up        # build and start without deleting data
make smoke     # verify the supported end-to-end contract
make auth-smoke # independently verify signup, email, sessions, and password reset
make product-smoke # create and verify all eight configured product types
make logs      # follow all container logs
make config    # render and validate the Compose model
make down      # stop containers; preserve PostgreSQL data
```

Real integration test credentials belong only in the ignored `local/.env` file. Copy `local/.env.example`, keep payment and Instagram modes at `disabled` until ready, use provider sandbox credentials, and switch only the integration under test to `test`. Authentication already uses the local Mailpit SMTP sink. Never commit credentials. The [India integrations guide](docs/india-launch-integrations.md) covers Razorpay, optional Stripe, signed webhooks, Instagram restrictions, and go-live gates.

## Read this repository in this order

For a person or another AI taking over the workspace:

1. [Current state and LLM handoff](docs/CURRENT_STATE_AND_LLM_HANDOFF.md) — exact repository snapshot, implemented flows, data model, verified AWS test state, limitations, and safe continuation rules.
2. [AI handoff](docs/AI_HANDOFF.md) — stable repository invariants, commands, and extension pattern.
3. [Feature parity](docs/FEATURE_PARITY.md) — what is end-to-end, partial, a boundary only, or not implemented.
4. [API contract](docs/api-contract.md) — implemented methods, paths, and response meanings.
5. [Product design](docs/product-design.md) — section-by-section frontend/backend/data flow.
6. [Multi-cloud deployment](docs/MULTICLOUD_DEPLOYMENT.md) — the EKS, AKS, and OKE runtime contract.
7. [Azure private AKS root](terraform/clouds/azure/README.md) and [OCI private OKE root](terraform/clouds/oci/README.md) — provider-owned infrastructure kept separate from application releases.
8. [Instagram Auto DM](docs/INSTAGRAM_AUTODM.md) — official API boundary, queue, scaling, and production gates.
9. [AWS regional bootstrap](docs/AWS_REGIONAL_BOOTSTRAP.md) — the existing AWS Terraform path.
10. [Infrastructure-first releases](docs/release-architecture.md) — separate plans/applies, application promotion, and environment contract.
11. [Backend architecture](docs/backend-architecture.md) — Spring Boot MVC/layer responsibilities.
12. [Production runbook](docs/production-runbook.md) — release, canary, rollback, and incident operations.
13. [Authentication end-to-end](docs/AUTHENTICATION_E2E.md) — local Mailpit workflow and production SMTP/Kubernetes contract.

`workspace-manifest.json` is the machine-readable component map.

## Delivery model

Every `main` commit in the frontend or backend repository runs its build/test workflow and publishes a SHA-addressed OCI image to GHCR:

```text
ghcr.io/kvsram/creator-link-store-frontend:sha-<git-sha>
ghcr.io/kvsram/creator-link-store-backend:sha-<git-sha>
```

That is a build artifact, not a deployment. Infrastructure has independent manual plan/apply workflows. A successful infrastructure apply publishes its exact Git SHA and regional outputs to AWS Parameter Store. Application deployment is a later, manually approved workflow for `dev`, `preprod`, or `prod`; it refuses to deploy unless its required infrastructure SHA is the one actually applied, copies the immutable application image into the environment ECR, and promotes that exact image. Read [Infrastructure-first releases](docs/release-architecture.md).

## AWS status and target

Terraform acts only after an operator supplies the reviewed account, region,
CIDRs, state configuration, release SHA, and teardown deadline and explicitly
runs a saved `terraform apply` plan.

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

The approved disposable feature test is intentionally smaller than that
production target. `terraform/environments/ephemeral-test` creates one
single-node K3s EC2 host, one private Single-AZ RDS instance, and an HTTP port
80 endpoint for at most seven days. It defaults to an IPv4 `/32` tester
allowlist and supports an explicitly approved, synthetic-data-only public HTTP
mode. It has no EKS, NAT Gateway, load balancer, SSH, or public Kubernetes API.
See the [K3s test environment](terraform/environments/ephemeral-test/README.md).

## Safety boundaries

- Local payments and Instagram are `disabled` by default.
- Currency values are integers in the smallest unit (`paise` for INR).
- Browser payment completion is not authoritative; a verified, idempotently recorded provider webhook is required.
- Secrets stay in ignored local environment files or AWS Secrets Manager, never Git or ConfigMaps.
- PostgreSQL is not deployed as a Pod in the multi-region production topology.
- Creator APIs use opaque, httpOnly, database-backed sessions and server-derived tenant ownership. The disposable K3s edge now has per-IP connection and endpoint-specific request limits, but production still requires distributed-edge protection, account-aware throttling/lockout, CSRF/security testing, recovery/verification, 2FA, audit trails, and an admin/role model.
- `make down` preserves data. Database deletion is deliberately not included in the normal command set.
