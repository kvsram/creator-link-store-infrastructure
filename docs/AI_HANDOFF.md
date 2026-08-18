# AI and engineer handoff

## Mission

Maintain an original India-focused creator storefront with a React frontend, Java API, PostgreSQL data store, safe Razorpay-first payment boundary, and optional Instagram integration. Preserve a simple local path while evolving toward manually promoted, multi-region AWS deployment.

Do not describe this project as Stan source code or a byte-for-byte clone. The supplied Word references contain observable UI/routes and an inferred database model, explicitly without response bodies, authentication tokens, proprietary source, or complete live checkout/OAuth behavior. This project's API contract is the code and `docs/api-contract.md`.

## Repository map

| Repository | Responsibility | Start reading |
|---|---|---|
| frontend | React SPA, admin sections, public store, checkout launch | `src/main.jsx`, `src/style.css`, `nginx.conf` |
| backend | REST contract, layered services/repositories, seed data, payment/Instagram boundaries | `controller/`, `service/`, `repository/`, `integration/`, `schema.sql` |
| infrastructure | local orchestration, Kubernetes, Terraform foundation, CI/CD operating model | `README.md`, `local/docker-compose.yml`, `docs/FEATURE_PARITY.md` |

The repositories must be siblings named `frontend`, `backend`, and `infrastructure`. `workspace-manifest.json` describes this for tools.

## First five commands

From `infrastructure/`:

```bash
./scripts/doctor.sh
docker compose -f local/docker-compose.yml up -d --build
./scripts/smoke-test.sh
docker compose -f local/docker-compose.yml ps
git status --short
```

If only this repository exists, use `./scripts/bootstrap-local.sh` instead; it fetches the missing application siblings.

## Source-of-truth rules

1. `docs/FEATURE_PARITY.md` decides whether a product area is end-to-end, partial, boundary-only, or absent.
2. Java controller mappings and tests decide the backend contract. Do not infer response parity from a captured path alone.
3. `schema.sql` is additive/idempotent for local volumes. Use a real migration tool such as Flyway before production; do not turn schema initialization into destructive reset logic.
4. Money is an integer in the smallest currency unit. For INR, `100` means ₹1.00. Historical `*_cents` database column names are deprecated aliases; public payloads use `*_subunits`.
5. Payment state is final only after signature verification and idempotent webhook recording. Never trust a browser callback as the source of paid status.
6. External actions default to disabled. Instagram test sends require an explicit confirmation header and an allowlisted recipient.
7. Secrets never belong in Git, images, frontend bundles, ConfigMaps, logs, or test fixtures.
8. The current creator mutations accept a client-provided creator ID and there is no session/JWT authorization. Do not expose this build publicly.
9. A `main` commit builds an artifact. It does not authorize or perform production deployment.
10. Promote the same immutable image SHA across dev, preprod, and prod; never rebuild a release during promotion.
11. An application deployment must name the infrastructure release it depends on and verify the applied SSM release marker before touching EKS.

## Guaranteed local behavior

- Clean PostgreSQL seeds `alex`, ID `1`, with INR products, one customer/order/lead/visit, disconnected integrations, and a draft automation.
- `/dashboard/` renders the sectioned admin shell.
- `/alex` renders the public store from the API.
- API health, public store, dashboard, income, analytics, customers, success, more-tools summary, settings summary, observed path aliases, payment config, and Instagram config are available.
- Product and customer creation persist.
- Payment and Instagram provider calls remain disabled without explicit mode plus secrets.

Run `make smoke` for executable proof. The smoke suite intentionally avoids creating durable user data.

## Highest-priority implementation gaps

Complete these before any public AWS launch:

1. Authentication sessions/JWT, ownership derived from the principal, route authorization, CSRF/session policy, password reset, email verification, optional 2FA, and login-session revocation.
2. Input DTO validation, URL allowlisting/SSRF controls, rate limiting, consistent error envelopes, audit logging, and API version lifecycle.
3. Flyway/Liquibase migrations, production seed separation, backups/PITR, restore drills, and connection pooling/proxy configuration.
4. Real product editors and APIs for landing pages/design, course modules/lessons, scheduling, product options, funnels, email flows, referrals, and subscription billing.
5. End-to-end checkout customer capture, order creation from verified webhook events, fulfillment, refunds/disputes, reconciliation, and payout ledger. Existing provider adapters are a safe foundation, not a complete commerce ledger.
6. CSV import validation/queueing, file/object storage, malware scanning, transactional email, and background jobs.
7. Expand frontend unit/component coverage beyond the current money-format tests; add browser E2E tests, contract tests, load tests, SAST/dependency policy, and image signing/verification.
8. Complete AWS add-ons, ingress/TLS/DNS/WAF, managed database, secrets sync, private deployment runner/GitOps, alarm notification paths, and disaster-recovery exercises.

## Safe extension pattern

For each feature slice:

1. Update `FEATURE_PARITY.md` design status only after examining the current code.
2. Add an additive database migration, domain repository/service, request DTO, and focused controller. Controllers must not contain SQL or provider HTTP calls.
3. Define request/response/error examples in `api-contract.md`.
4. Add backend unit/integration tests.
5. Add frontend loading, empty, error, and success states plus component/E2E coverage.
6. Extend `smoke-test.sh` only for stable, non-destructive contract checks.
7. Build containers and run the full local smoke suite.
8. Render Kustomize overlays and run Terraform format/validate before a PR.
9. Update operational docs and rollback signals.

## AWS handoff boundary

No cloud resource is currently proven to exist. Terraform is not evidence of an applied environment. Before applying anything, read `AWS_REGIONAL_BOOTSTRAP.md`, select actual regions and availability targets, obtain an approved AWS account/domain/budget, create remote state, review a plan, and preserve the plan output/change record.

The one-region release root is `terraform/environments/regional`; `docs/release-architecture.md` defines its plan/apply/application sequence. The older `production` root is a future three-region reference, not the current release target. Do not promise production readiness until the gap checklist is closed and an environment has passed restore, rollback, canary, security, and regional-failure exercises.
