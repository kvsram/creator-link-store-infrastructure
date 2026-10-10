# Creator Link Store: current state and LLM handoff

Snapshot date: **2026-09-14**. This document is the fastest, secret-free way for a new engineer or LLM to understand the whole project, reproduce it locally, and continue without overstating what is complete.

## 1. Product mission and legal/technical boundary

This is an original India-focused creator-commerce application in the same broad product category as link-in-bio storefronts. A creator can publish a public store, promote external links, author several product/service types, collect leads, inspect business data, and configure integrations. It is **not** Stan source code, is not affiliated with Stan, and does not claim identical private API responses or proprietary behavior.

The two supplied Word documents and limited browser observations were used as feature references. The source of truth is now this project's code, tests, and documented contract:

1. `docs/FEATURE_PARITY.md` says whether a capability is E2E, partial, a boundary, or missing.
2. `docs/api-contract.md` and Java controller mappings define the supported HTTP contract.
3. `backend/src/main/resources/schema.sql` defines the current local database model.
4. Automated tests and smoke scripts are evidence. A rendered UI, compiled service, Terraform file, or historical screenshot is not by itself proof.

## 2. Repository and branch snapshot

The system is intentionally split into independently releasable repositories. They must be sibling folders for the local orchestration scripts.

| Component | GitHub repository | Development branch at this snapshot | Verified source head before this handoff commit |
|---|---|---|---|
| React frontend | `https://github.com/kvsram/creator-link-store-frontend` | `feature/auth-autodm-cloud-portability` | `41a6aeada7a355da66c14d8496ed351ad6136094` |
| Spring Boot backend | `https://github.com/kvsram/creator-link-store-backend` | `feature/sai-auth-autodm-cloud-portability` | `7045af28623d2563a6fb90778ffaaa7493c20c1f` |
| Infrastructure/orchestration | `https://github.com/kvsram/creator-link-store-infrastructure` | `feature/multicloud-kubernetes-autodm` | `aef7c87ff2953ea536f399ebc6f6a2a7abe133c1` |

This handoff document is a documentation-only commit on top of the listed infrastructure head. Resolve the exact current branch commit with `git rev-parse HEAD`. The same reviewed heads are also published to each repository's `test` branch. Neither operation merges to protected `main`.

Branch meanings:

- `feature/...`: current integrated development line.
- `test`: movable candidate branch for shared validation; it is not automatically a deployed environment.
- `main`: protected release integration line. Use a pull request and required checks; do not push or merge directly as an ordinary collaborator.
- dev/preprod/prod: deployment environments, not Git branches. Promotion must name exact immutable application and infrastructure SHAs.

## 3. What is actually running

### Local supported topology

```text
Browser
  -> frontend Nginx/React container :3000
       -> /api and /health proxy
  -> Spring Boot API container :8080
  -> PostgreSQL 16 container :5432
```

The frontend and backend are stateless with respect to browser instances. Durable application records live in PostgreSQL. Local staged product files use a mounted application storage directory; production must replace this with cloud object storage.

### Current disposable AWS test topology

```text
Public IPv4 HTTP :80
  -> one EC2 host in us-east-2
       -> single-node K3s
            -> frontend Nginx pod (hostPort 80, edge limits)
            -> Spring Boot API pod
       -> SSM management (no public SSH, no public Kubernetes API)
  -> private, Single-AZ RDS PostgreSQL
```

This is deliberately a low-cost feature-test environment: no EKS, NAT Gateway, ALB, domain, or TLS certificate. It is not production and accepts synthetic test data only.

During this 2026-09-14 handoff the following unauthenticated probes returned HTTP 200 from `77.112.61.68`: `/`, `/health`, `/alex`, `/api/public/alex`, and `/dashboard/`. `/api/health` correctly returned 404 because the implemented route is `/health`. The public entry point is `http://77.112.61.68/`.

The last full AWS verifier run, completed before the newest profile-settings commits, checked resource topology, K3s health, private RDS connectivity, exact container digests, route normalization, real HTTP 429 limits for login and lead traffic, client-IP preservation, and rejection of spoofed forwarded-for input. Its deployed release was:

| Component | Deployed source/release | Deployed image digest |
|---|---|---|
| Infrastructure | `d130d37d64c7ea413cd60a56fb7716a1335d1f62` | n/a |
| Backend | `6c8fdbcfff0695065e0626ecb9c1299333ea823d` | `sha256:98e183eb84bc53b6b0b61ec441d7c2dc97a8fd0e7b9533222a05d6e285c63ea1` |
| Frontend | `6d8ca90739e2b307f2fdb385204122f78ca8fc2e` | `sha256:c2b27da49d0b30da4eea1b04326be8a31cc65d14f57db4e69093c334fcb5ab19` |

Therefore the endpoint is live, but it does **not** yet contain the newest current feature heads in section 2. The original disposable-stack deadline is 2026-09-15; an authorized operator must explicitly extend/recreate it or destroy it. Never infer current AWS resource state only from this document—rerun `scripts/verify-aws-ephemeral.sh` with a fresh MFA-backed operator session.

Newer application releases keep the applied infrastructure guard
`d130d37d64c7ea413cd60a56fb7716a1335d1f62` separate from the exact manifest
commit. Pass both values to the deploy and verification scripts. They validate
the Terraform-managed SSM marker/EC2 tag against the applied infrastructure SHA
and fetch helpers/Kustomize content from the manifest SHA; an application
release must not rewrite the infrastructure marker.

## 4. High-level application design

The current backend is a modular monolith, which is intentional for the present scale:

```text
React view/state
  -> HTTP JSON/multipart contract
Spring MVC controller
  -> service validation/orchestration/transaction boundary
  -> repository parameterized SQL
  -> PostgreSQL
  -> provider strategy/client only for an enabled external integration
```

Important boundaries:

- Controllers route and translate HTTP. They do not contain SQL or provider calls.
- Services own authorization-aware orchestration and validation.
- Repositories own parameterized SQL and row mapping.
- DTO records define accepted request shapes.
- Provider interfaces isolate Razorpay, Stripe, and Instagram.
- Authenticated creator identity is resolved from the server-side session, never trusted from a browser-supplied creator ID.
- Public endpoints resolve a published resource, then derive and cross-check its creator.
- Keep this as one Java deployable until measured load, ownership, release cadence, data ownership, or failure isolation justifies extracting a service.

## 5. Main end-to-end user journeys

### 5.1 Visitor discovers the product and registers

1. Visitor opens `/`, `/about`, `/create-store`, `/features`, or `/pricing`.
2. Marketing UI explains Starter and test-stage Creator Pro boundaries.
3. `/signup` collects plan choice, identity/store details, and review confirmation.
4. The UI calls the public handle-availability endpoint. This intentionally does not reveal email existence.
5. Registration normalizes the handle/email, rejects reserved routes or duplicates, BCrypt-hashes the password, and transactionally creates creator, store, notification preferences, and an opaque session.
6. Browser receives an httpOnly SameSite cookie and enters `/dashboard/`.
7. All new accounts remain on the free/Starter plan. Premium billing is not fabricated.

Still missing: email/phone verification, password reset, MFA for creator accounts, real creator-subscription checkout, verified subscription ledger, trial lifecycle, and server-side Premium entitlements.

### 5.2 Creator signs in and updates identity

1. `/login` accepts handle or email plus password.
2. Backend verifies BCrypt and creates a random opaque session; only its SHA-256 hash is stored.
3. `GET /api/auth/me` restores browser account state.
4. Settings -> Profile saves display name, **public store address** (the intuitive UI name for handle), bio, and optional phone using `PATCH /api/v1/settings/profile`.
5. Backend applies the same normalization/reserved-name/collision rules as signup and derives ownership from the session.
6. The dashboard identity and phone preview update immediately. A successful handle change activates the new public route; the old route returns not found. Redirect/history policy is not yet implemented.

### 5.3 Creator designs a storefront

My Store has three focused views:

- Store: products/services and external promotions.
- Landing Pages: public headline, tagline, and product/link visibility.
- Edit Design: allowlisted theme, accent color, background, button shape, and typography.

`PATCH /api/v1/store` persists this model. The admin phone preview and public storefront consume the same saved data, so it is not browser-only customization.

### 5.4 Creator authors a product or service

The visual picker supports eight checkout product types plus one separate promotion type:

- digital download: upload or HTTPS redirect configuration;
- lead magnet: capture requirements plus future delivery configuration;
- meeting/coaching: duration, notice, buffer, timezone, capacity, availability, slots;
- webinar: timezone, dated sessions, capacity, and private join data;
- course: modules, lessons, video metadata, drip, and supporting assets;
- membership: recurring plan intervals, amounts, and benefits;
- fulfillment/custom service: turnaround, format, and checkout questions;
- community: platform, public benefits, and private access/welcome data;
- promotion/external link: a separately stored HTTPS outbound offer, not a checkout product.

Common product fields and `configuration.schemaVersion=1` are written as one aggregate. Product type becomes immutable after creation. The service validates type-specific fields and transactionally rebuilds normalized projections for queryable/runtime data.

Upload-mode downloads and lead magnets use draft-first publication:

1. Create draft product.
2. Upload an owned file using multipart.
3. Persist opaque file metadata/object key.
4. Publish only after readiness validation succeeds.

The current AWS/local application storage is not the final secure delivery design. Production requires object storage, malware scanning, authorization/entitlement checks, and short-lived signed URLs.

### 5.5 Creator manages order and prominence

- Product and promotion rows support edit, publish/draft, delete, ordering, and persistent pin/unpin.
- The phone preview is also a pinning surface.
- Published pinned products and promotions are combined first in the public feed; remaining items follow their order.
- Draft items say “Publish first” and cannot be promoted to customers.
- Deleting a product referenced by commerce history returns 409; unpublish it instead.

### 5.6 Visitor views and interacts with a public store

1. `/{handle}` requests `GET /api/public/{handle}`.
2. Backend loads only a published store and returns saved design plus a pinned-first combined feed.
3. Browser sends one best-effort view event per mounted handle; rendering does not wait for analytics.
4. Promotion clicks are recorded only after the backend validates that the active link belongs to that storefront, then the browser redirects to its HTTPS destination.
5. Product detail uses a sanitized `public_configuration`; private object keys, redirect targets, join URLs, buyer instructions, lesson content, and welcome secrets must never be returned.
6. Published lead magnets accept idempotent, validated contact/consent submissions. They currently save data but do not send a delivery email.

### 5.7 Buyer checkout boundary

1. Public UI gathers buyer email, optional name, checkout-field answers, and applicable meeting slot or payment plan.
2. Backend reloads the published product and validates every selected child belongs to it.
3. Server derives amount and INR currency in integer paise; it does not trust a browser amount.
4. An idempotency key prevents duplicate checkout creation.
5. A configured provider strategy may create a Razorpay order or Stripe redirect.
6. A signed, deduplicated provider webhook—not the browser callback—must be the final paid-state authority.

Payment modes default to `disabled`. Existing code includes safe provider boundaries, signature verification, checkout-session/event persistence, and fulfillment scaffolding, but end-to-end production commerce still needs sandbox evidence, robust webhook-to-order/ledger/fulfillment behavior, refunds, disputes, reconciliation, payouts, and buyer portals.

### 5.8 Instagram comment-to-DM boundary

1. Creator defines a keyword rule.
2. Meta sends a signed Instagram comment webhook.
3. Backend verifies signature, deduplicates the event, resolves an enabled creator/rule, and enqueues one durable PostgreSQL DM job.
4. A scheduled worker leases jobs, respects the seven-day private-reply window, calls the provider client, records counters, retries retryable failures with a bound, and marks permanent failures dead.

Instagram defaults to `disabled`. Live use is blocked on Meta App Review, required permissions, per-creator OAuth, encrypted token storage/refresh/revocation, subscription entitlement checks, production rate-limit/retry evidence, monitoring, privacy/compliance, and controlled recipient testing. Do not treat the presence of a worker or webhook route as permission to message real users.

## 6. Frontend route and section map

| Route/section | Current behavior | Important limitation |
|---|---|---|
| `/`, `/about`, `/create-store`, `/features`, `/pricing` | public product/marketing page | copy and SEO need launch review |
| `/signup`, `/register` | three-stage signup and handle check | no verification or real SaaS billing |
| `/login` | authenticated session login | HTTP test environment is synthetic-data only |
| `/dashboard/` | home spotlight, readiness checklist, metrics | trends/actions are basic |
| `/dashboard/store` | products, promotions, live phone preview, landing/design editor | drag-and-drop and full accessibility automation absent |
| `/dashboard/success` | deterministic tutorial hub | not a CMS/video platform |
| `/dashboard/income` | INR gross/net/available/order summary | chart and export/cashout are incomplete; cashout is not authoritative |
| `/dashboard/analytics` | visits, leads, orders, conversion, sources, promotion clicks | no date filters, unique sessions, queue/batch pipeline, or conversion postbacks |
| `/dashboard/customers` | list/manual add | search/filter/import and full purchase profile incomplete |
| `/dashboard/community` | presentation/demo community surface | protected community product workflow not complete |
| `/dashboard/more` | funnels, appointments, referrals, email-flow cards; AutoDM editor | most optional tools are boundary/missing; see parity matrix |
| `/dashboard/settings` | profile, billing boundary, payments, integrations, other settings states | several tabs are informational boundaries only |
| `/{handle}` | public creator storefront | custom domain, CDN/SEO, full a11y missing |
| unknown nested path | real not-found page | n/a |

Specific UI controls that are still visual-only or partial:

- Home actions such as Create product, Market your products, Creator Coach, and the settings notice are not all wired.
- Success lessons are static metadata and do not open a real lesson player.
- Income totals/orders come from data, but the chart is decorative; CSV export and real cashout action/ledger are absent.
- Analytics totals/sources/promotion rows come from data, but the line chart is decorative and has no time-series query.
- Customer list/add works; search, filter, CSV import/export, edit, and delete do not.
- Community content/statistics are a presentation surface, not an entitled community runtime.
- Funnels and appointments have data/read foundations rather than complete editors and visitor workflows.
- Referrals and email flows are placeholders.
- Notification/security settings and several provider settings tabs are informational boundaries.
- The integration catalog is read-only; OAuth connect/disconnect is not implemented.
- The frontend does not yet expose a logout control even though the backend logout endpoint exists.

The dashboard uses an original cinematic dark visual system with compact navigation, responsive mobile navigation, focus states, high-contrast cards, and restrained motion. Creator storefront themes remain independently customizable.

Key frontend files:

- `src/main.jsx`: application shell, pages, API orchestration, modals, public store.
- `src/AuthPages.jsx`: signup/login/account flows.
- `src/MarketingHome.jsx`: public landing content.
- `src/routes.js`: deterministic route classification.
- `src/productConfig.js`: type-specific frontend configuration normalization/validation.
- `src/profileSettings.js`: profile payload/validation/error mapping.
- `src/publicEvents.js`, `src/leadSubmission.js`: safe public interaction helpers.
- `src/style.css`, `src/integrations.css`: UI system.
- `nginx.conf`: container SPA fallback and backend proxy.

## 7. Backend package/layer map

| Layer/package | Responsibility |
|---|---|
| `controller` and `identity/AuthController` | HTTP methods, paths, status/response translation |
| `dto` | accepted request records |
| `service` | validation, creator-scoped orchestration, product/provider workflows |
| `repository` | parameterized SQL and database row mapping |
| `domain` | typed product configuration model |
| `identity` | session cookies, current creator resolution, auth/origin interceptors |
| `integration` | Razorpay/Stripe/Instagram provider clients and strategies |
| `security` | signature utilities |
| `commerce` | verified-payment fulfillment orchestration foundation |
| `bootstrap` | deterministic demo seed initialization |
| `support` | stable result/value helpers |

Main controller domains are authentication, dashboard, store, products/files, promotions, public store/leads/events, customers/tags, income/analytics, settings, payments/webhooks, Instagram/automations, integrations, experiments, success, and optional-tool summaries.

The project targets Java 17 and Spring Boot 3.5.16. It currently uses direct repository SQL rather than JPA, keeping queries explicit. `schema.sql` uses additive `create if not exists`/`alter if not exists` initialization for local persistence; this must be replaced with versioned Flyway/Liquibase migrations before production.

## 8. Implemented HTTP surface

The detailed bodies, response examples, validation rules, and compatibility semantics are in `docs/api-contract.md`. Current route families are:

### Public/system/account

- `GET /health`
- `POST /api/auth/register`
- `POST /api/auth/login`
- `POST /api/auth/logout`
- `GET /api/auth/me`
- `OPTIONS|POST /api/v1/authentication/check-unique-taken`
- `GET /api/public/{handle}`
- `GET /api/public/{handle}/products/{productId}`
- `POST /api/public/products/{productId}/leads`
- `POST /events`
- `POST /api/events/view`
- `POST /api/events/click`

### Authenticated creator/catalog/business

- `GET /api/v1/dashboard`
- `GET|PATCH /api/v1/store`
- `POST /api/v1/products`
- `PATCH|DELETE /api/v1/products/{id}`
- `PATCH /api/v1/products/{id}/pin`
- `GET|PUT /api/v1/products/{id}/configuration`
- `GET|POST /api/v1/products/{id}/files`
- `DELETE /api/v1/products/{productId}/files/{fileId}`
- `POST /api/v1/promotions`
- `PATCH|DELETE /api/v1/promotions/{id}`
- `PATCH /api/v1/promotions/{id}/pin`
- `GET|POST /api/v1/customers`
- `PUT /api/v1/tags`
- `GET /api/v1/income`
- `GET /api/v1/analytics`
- `GET /api/v1/success`
- `GET /api/v1/more`
- `GET /api/v1/settings`
- `PATCH /api/v1/settings/profile`

### Payments and external integrations

- `GET /api/v1/payments/config`
- `POST /api/v1/checkout/sessions`
- `POST /api/v1/payments/razorpay/verify`
- `POST /api/v1/webhooks/razorpay`
- `POST /api/v1/webhooks/stripe`
- `GET /api/v1/integrations`
- `GET /api/v1/integrations/instagram/config`
- `GET|POST /api/v1/webhooks/instagram`
- `POST /api/v1/integrations/instagram/test-message`
- `GET|POST /api/v1/automations/instagram-comment-rules`
- `GET /api/v1/automations/instagram-posts-metadata`
- `GET /api/v1/automations/analytics`

### Compatibility/demo routes

- `GET /api/v1/users/get_user`
- `POST /api/v1/users/experiments/join_communities`
- `GET /api/v1/users/experiments/community_stats`
- `GET /api/v1/users/experiments/metadata`
- `PUT /api/v1/experiments/variant-assignment`

Matching an observed method/path does not mean the response, authorization, side effects, limits, or errors match another product.

## 9. Core PostgreSQL model

Think of `creators` as the tenant root. Almost every creator-owned aggregate carries `creator_id`, and every authenticated query must scope by the server-derived creator.

```text
creators (tenant/login/profile)
  1--1 stores (public design and visibility)
  1--* products
          1--* product_files
          1--* product_payment_plans
          1--* product_checkout_fields
          1--* product_reviews
          1--* course_modules --* course_lessons
          1--* webinar_sessions --* webinar_registrations
          1--* availability_schedules / bookings
          1--* checkout_sessions --0..1 orders
          1--* entitlements / course_enrollments / membership_subscriptions
  1--* links (promotions) --* click_events
  1--* customers --* orders
          *--* tags through customer_tags
  1--* leads
  1--* store_visits
  1--* integrations
  1--* automations --* automation_keywords
          1--1 automation_stats
          1--* instagram_comment_events --* instagram_dm_jobs
  1--* sessions
  1--1 notification_preferences
  1--* funnels --* funnel_steps
```

Table families and meaning:

- Identity: `creators`, `sessions`, `notification_preferences`.
- Store catalog: `stores`, `products`, `links`.
- Product authoring/projections: `product_files`, `product_payment_plans`, `product_checkout_fields`, `product_reviews`, `availability_schedules`, `bookings`, `webinar_sessions`, `course_modules`, `course_lessons`.
- Audience/analytics: `customers`, `tags`, `customer_tags`, `leads`, `store_visits`, `click_events`.
- Commerce/access: `checkout_sessions`, `provider_events`, `orders`, `order_field_responses`, `entitlements`, `webinar_registrations`, `membership_subscriptions`, `course_enrollments`, `lesson_progress`.
- Automation/Instagram: `integrations`, `automations`, `automation_keywords`, `automation_stats`, `instagram_events`, `instagram_automation_rules`, `instagram_comment_events`, `instagram_dm_jobs`.
- Future product boundaries: `funnels`, `funnel_steps`.

Important data invariants:

- creator handles and emails are unique after normalization;
- one store and one notification-preference row per creator;
- customer email is unique within a creator, not globally;
- product creation and lead capture use creator/product-scoped idempotency keys;
- money is a nonnegative integer in smallest currency units—paise for INR;
- legacy `*_cents` column names contain generic subunits and are exposed as `*_subunits` in current APIs;
- provider events and Instagram events are deduplicated;
- foreign keys preserve or restrict commerce history where deletion would be unsafe;
- product creator configuration is stored as schema-versioned JSON, with operational child projections rebuilt transactionally;
- public projections must be allowlisted rather than serializing creator configuration directly.

## 10. Authentication and current security model

Implemented:

- BCrypt password hashing;
- random opaque sessions, SHA-256 token storage, expiry and logout revocation;
- httpOnly SameSite cookie;
- authenticated `/api/v1/**` default with an explicit public allowlist;
- server-derived tenant identity for creator mutations;
- owner-scoped product, file, promotion, profile, and reporting behavior;
- allowed-origin mutation guard;
- signature verification/deduplication boundaries for provider webhooks;
- HTTPS-only external promotion/download destinations;
- size/type metadata controls for uploads;
- Nginx per-IP connection/request limits in the disposable K3s edge;
- untrusted forwarded-for replacement with the actual socket client address.

Not production-complete:

- the AWS test endpoint is plain HTTP, so secure cookies/TLS are not end-to-end;
- no creator email verification, reset, MFA, session inventory, revoke-all, role/admin model, or account deletion;
- no complete formal CSRF posture, audit trail, broad authorization matrix, SAST/DAST/pentest evidence, or distributed abuse defense;
- no production object-storage scanning/signed-download system;
- no production secret synchronization proof or rotation drill;
- no managed WAF/DDoS layer on the cheap test endpoint.
- `/health` reports process liveness only; it does not prove database or provider readiness.

Do not commit passwords, MFA seeds/codes, AWS keys, GitHub tokens, payment secrets, Meta tokens, cookies, database credentials, or real customer data. Synthetic test credentials also stay out of this document and must be transferred separately and rotated.

## 11. Analytics, queue rationale, and current limits

Today, storefront views, eligible promotion clicks, leads, customers, and orders are persisted synchronously in PostgreSQL. This makes the low-scale system easy to understand and test. Analytics reads aggregate those tables for dashboard totals and sources.

At high storefront traffic, analytics writes become a separate pressure problem: for example, 20,000 viewers opening a viral creator link in one minute can produce hundreds of inserts per second even though all visitors read the same store. Those noncritical inserts can consume database connections, increase WAL/index churn, and slow the revenue-critical checkout/profile queries.

The next scaling step is an event queue because analytics is allowed to be eventually consistent:

```text
storefront request -> return page immediately
                  -> best-effort event ingress -> durable queue
                                              -> batch consumer -> analytics tables
```

If queue publication is temporarily unavailable, public content should still load; the visitor experience is more important than losing/delaying a view counter. Checkout/payment events have different durability requirements and must use transactional outbox/idempotent processing rather than the same lossy policy.

Queue/batch analytics, unique-session logic, retention/rollups, partitioning, and a read model are designed future work, not present code.

## 12. Testing evidence and how to reproduce it

Recorded current-source evidence before branch publication:

- backend: `mvn -B verify` passed 58 tests;
- frontend: `npm test` passed 30 tests;
- frontend: `npm run build` passed;
- earlier real PostgreSQL/HTTP product smoke passed for all eight types and two isolated creator sessions;
- earlier restart check proved product aggregates/projections reload;
- manual browser exploration covered marketing, signup, login, public store, not-found, dashboard, billing boundary, type-specific editor, pinning, and profile state behavior;
- GitHub Actions successfully built current backend and frontend image artifacts and ran infrastructure quality checks.

Current artifact evidence:

| Workflow | Run | Result/artifact identity |
|---|---|---|
| backend image | `34359963324` | `sha256:bd10f26f94f3d92ac6f37311f9374a2cead073ad1c991cbbeef8a10a4e062ae5` |
| frontend image | `34359966407` | `sha256:bb01386184956b7aa07b79d60a888a8bcf84e880fc63335abdd343785419aab1` |
| infrastructure quality | `34359965345` | success |

Rerun, do not merely quote, the checks for every candidate:

```bash
# backend
mvn -B verify

# frontend
npm ci
npm test
npm run build

# integrated local environment, from infrastructure/
make doctor
make up
make smoke
make product-smoke
```

Test-suite limits are explicit: the frontend tests are mostly pure-function/contract tests, not React component or automated browser tests. Provider modes disabled in smoke tests do not prove Razorpay/Stripe/Meta sandboxes. Terraform validation does not prove applied infrastructure. The public HTTP probes do not prove the current source heads are deployed.

## 13. Clean-laptop bootstrap

Prerequisites: Git and Docker Desktop/Engine with Compose v2.

```bash
mkdir creator-store-workspace
cd creator-store-workspace
git clone --branch test https://github.com/kvsram/creator-link-store-infrastructure.git infrastructure
cd infrastructure
./scripts/bootstrap-local.sh --ref test
```

The bootstrap clones missing application siblings at `test`. It deliberately refuses to switch an existing checkout; preserve any local work and switch that repository explicitly first. Omitting `--ref` retains the stable default-branch behavior. The required layout is:

```text
creator-store-workspace/
  frontend/
  backend/
  infrastructure/
```

Then open:

- admin: `http://localhost:3000/dashboard/`
- demo store: `http://localhost:3000/alex`
- health: `http://localhost:8080/health`

The clean database seeds `alex` as a deterministic display demo, but its password is intentionally unusable. Register a new synthetic account through the UI/API to test authenticated behavior. `make down` stops containers while preserving the PostgreSQL volume. Do not add database deletion to the normal workflow.

Read `docs/LOCAL_SETUP.md` for Apple Silicon, Windows/WSL, ports, persistence, logs, and troubleshooting.

## 14. CI/CD and release model

Current GitHub Actions behavior:

- frontend/backend quality workflow: runs for pull requests targeting `main` and by manual dispatch;
- frontend/backend container workflow: on `main` push, runs tests/build and publishes immutable `ghcr.io/kvsram/...:sha-<commit>` plus a retained build artifact;
- frontend/backend deployment workflow: manual, expects exact application and applied infrastructure SHA, protected environment approval, OIDC role, and a private AWS runner;
- infrastructure quality workflow: `main` push, PR to `main`, or manual; checks Terraform, Compose, Kubernetes renders, edge policy, and script syntax;
- infrastructure plan/apply workflows: separate manual operations against an exact reviewed SHA;
- multi-cloud workflow: separate Azure or OCI plan/apply with provider-private runners;
- cloud-neutral application workflow: exact-SHA Kubernetes deployment to AWS/Azure/OCI using a provider/stage-specific private runner.

The last cloud-neutral workflow currently applies rendered Kubernetes YAML but does not yet resolve/verify the provider's applied-infrastructure marker, obtain cloud identity/cluster credentials, copy images to the target registry by digest, materialize database/runtime secrets, run smoke/canary analysis, or automate rollback. The separate frontend/backend AWS workflows implement more of that AWS-specific release contract. Reconcile these paths before calling the multi-cloud workflow production-ready.

Pushing `test` does not currently deploy or publish a container by itself. A test branch is source organization, not CI/CD proof. To validate it, open a PR to `main` or manually dispatch the applicable quality/container workflow from that ref. Do not change this into automatic production deployment.

Intended production release order:

1. Developer implements code and tests on a feature branch.
2. PR quality/security checks pass; review and merge to `main`.
3. `main` creates immutable application images; record SHAs/digests/SBOM/attestation.
4. If the feature needs infrastructure, plan the exact infrastructure commit first, review it, then apply it.
5. Verify the applied infrastructure release marker and outputs.
6. Manually promote the already-built application image to dev.
7. Run smoke, integration, browser E2E, security, and rollback checks.
8. Promote the same digest to preprod, then prod with approvals/change record and canary analysis.
9. Observe; automatically or manually roll back application traffic only when schema compatibility allows it.

## 15. Infrastructure code inventory

### Local and Kubernetes

- `local/docker-compose.yml`: frontend/backend/PostgreSQL test topology.
- `k8s/base`: namespace, API/web deployments/services, config, storage contract, ingress, probes, resource bounds, NetworkPolicy, HPA/PDB where appropriate.
- `k8s/overlays/aws`, `azure`, `oci`: provider-neutral application contract with cloud-specific identity/storage patches.
- `k8s/overlays/aws-ephemeral`: single-node K3s overlay with hostPort/public edge, Recreate strategy, local storage, and Nginx IP limits.

### Terraform

- `terraform/bootstrap`: AWS production-style state/OIDC bootstrap foundation.
- `terraform/bootstrap-ephemeral`: isolated disposable-test remote state.
- `terraform/identity-bootstrap`: temporary MFA-protected human deployment role; review/remove broad temporary permission by its deadline.
- `terraform/environments/ephemeral-test`: cost-capped K3s EC2 + private Single-AZ RDS test stack.
- `terraform/environments/regional`: one-region AWS production foundation with VPC, private EKS, managed nodes, ECR, RDS, SSM release contract, and CloudWatch foundations.
- `terraform/environments/production`: future multi-region reference, not the current one-region release root.
- `terraform/clouds/azure`: private AKS, ACR, workload identity, PostgreSQL Flexible Server, and logging foundation.
- `terraform/clouds/oci`: private OKE, OCIR/runtime identity, PostgreSQL/secret contract, and logging foundation.

### Disposable test operations

- `scripts/deploy-aws-ephemeral.sh`: operator-side account/region/resource guard, independent applied-infrastructure and manifest commit validation, then SSM deployment.
- `scripts/deploy-k3s-node.sh`: node-side exact-manifest/image deployment without printing database secrets.
- `scripts/verify-aws-ephemeral.sh`: AWS topology, independent infrastructure/manifest release evidence, networking, RDS, images, public policy, and runtime verification.
- `scripts/verify-k3s-node.sh`: pod/service/config/runtime and endpoint-limit checks on the host.

The cheap test stack is not a model for production availability. One node and Single-AZ database are expected single points of failure.

## 16. Production target and scaling sequence

Do not jump directly to three regions. The intended sequence is:

### Stage A: current low scale

- modular monolith;
- one active environment/region;
- PostgreSQL primary;
- synchronous business writes;
- cheap K3s/RDS test stack for feature validation only.

### Stage B: production one region

- domain + TLS + CDN/edge protection;
- regional load balancer;
- private managed Kubernetes (EKS) and managed nodes;
- Multi-AZ RDS, backups/PITR, connection pooling;
- secret manager synchronization;
- centralized logs/metrics/alerts;
- migration job, private deployment path, canary/rollback proof;
- object storage and transactional email where product flows require them.

### Stage C: high public-read traffic

- CDN cache public storefront payload/assets;
- invalidate by creator/version on publish;
- Redis/cache only after measuring misses/latency;
- multiple stateless API replicas and read scaling;
- protect checkout/auth endpoints separately from cacheable reads.

### Stage D: high analytics-write traffic

- queue event ingress;
- idempotent micro-batch consumers;
- partition/roll up event data;
- isolate analytics read model from transactional checkout queries;
- define loss/backpressure policy separately for views versus money events.

### Stage E: two or three regions

- one independently deployable cluster per active region;
- edge routing/health checks;
- one authoritative writer strategy first, with warm secondary and rehearsed failover;
- explicit RPO/RTO, replicated object storage, secrets, images, and queues;
- never enable arbitrary active-active PostgreSQL writes without a designed conflict/data-ownership model;
- add the third region only after deployment, database restore, and regional-failure drills are repeatable.

## 17. Known gaps, ordered by launch risk

### P0: must close before real customers/money

1. TLS/domain and secure-cookie enforcement.
2. Email verification, password reset, account lockout/abuse defenses, CSRF decision, session management, audit trail, broader tenant tests, and security review.
3. Versioned database migrations, production/demo seed separation, backups/PITR, restore drill, pool sizing, and schema-compatible rollback policy.
4. Real creator subscription billing/entitlements if Premium is sold.
5. Verified provider-webhook-to-order/customer/ledger/entitlement/fulfillment behavior, including refunds/disputes/reconciliation.
6. Object storage, malware scan, signed delivery, and transactional email.
7. Complete each marketed buyer flow: download access, booking, webinar registration/attendance, learner portal/progress, membership lifecycle, custom fulfillment, and community access.
8. Component/browser E2E, contract, load, security, and provider-sandbox test evidence.
9. Production AWS ingress/add-ons/secrets/private deployment runner/observability/canary/rollback/DR proof.

### P1: product completeness

- customer search/filter/import and purchase/subscription detail;
- analytics ranges, unique sessions, attribution and durable event pipeline;
- income export, cashout ledger, payout/reconciliation UX;
- reviews/testimonials editor and rendering;
- funnels, appointments, referrals, email flows;
- richer content/asset editor, custom domains, SEO and accessibility automation;
- avatar upload and handle redirect/history policy.

### Known code-specific cautions

- `PaymentWebhookService` can mark a checkout session paid but does not currently invoke `OrderFulfillmentService.recordPaidOrder`; a verified webhook therefore does not yet complete customer/order/entitlement fulfillment.
- There is no secure entitlement redemption/delivery endpoint for downloads, courses, communities, meetings, webinars, or custom fulfillment.
- Membership checkout is not yet a real recurring provider-subscription lifecycle, and webinar checkout does not yet let a buyer choose a session.
- Lead magnets persist consent-aware leads but do not send email or issue a short-lived signed delivery link.
- `TagService` historically trusted request `creator_id`; re-audit and session-scope this before exposing tag mutation as production complete.
- Income/cashout presentation contains incomplete/hard-coded behavior and must not be treated as actual withdrawable funds.
- Provider modes must remain disabled unless the matching external approval, secret, sandbox, test, entitlement, and monitoring gates are complete.
- The managed-cluster base NetworkPolicy allows API ingress from frontend-labeled pods, while the checked-in Ingress routes `/api` directly to the API Service; a real policy-enforcing cluster may block ingress-controller traffic until routing or policy is corrected.
- The AWS overlay expects RWX/EFS-style upload storage, while the current regional Terraform installs EBS CSI but not an EFS filesystem/CSI/storage class. Replace uploads with object storage or provision the complete storage contract.
- HPA requires Metrics Server, and the current EKS Terraform does not install it.
- `creator-store-runtime-secrets` is a required runtime object; the checked-in external-secret manifest is an example and current general deployment automation does not materialize it.
- The AWS Terraform apply workflow recreates a plan from the reviewed commit rather than applying the exact previously uploaded binary plan. The immutable commit reduces drift but does not provide strict reviewed-plan promotion.
- Product files still use local filesystem storage. The generic API Deployment has a read-only root filesystem without a completed persistent upload mount/`APP_STORAGE_DIR` contract; multi-replica uploads require object storage or a fully implemented shared storage patch.
- Every backend replica currently runs evolving startup schema initialization, which is unsafe for concurrent production rollout and is not a substitute for ordered migrations.

## 18. How another LLM should continue safely

Before any change:

1. Read this file, `FEATURE_PARITY.md`, `api-contract.md`, and the relevant source/tests.
2. Run `git status --short --branch` in all three repositories; never discard unknown user changes.
3. Resolve exact local and remote SHAs. Do not assume this snapshot is current.
4. Label conclusions as implemented, locally verified, cloud verified, partial, designed only, or blocked.
5. Work on a feature branch and preserve protected `main`.

For a new product slice:

1. Define UI states, API body/errors, ownership, database model, idempotency, external side effects, and rollback behavior.
2. Add an additive/versioned migration plan.
3. Implement DTO -> controller -> service -> repository/provider layers.
4. Add unit and integration tests, then frontend loading/empty/error/success behavior and component/E2E coverage.
5. Update `api-contract.md` and `FEATURE_PARITY.md` only to the level actually proven.
6. Run full local/container checks.
7. If infrastructure changes, release/apply it before the compatible application release.
8. Promote exact immutable digests and record evidence.

Never:

- scrape/copy proprietary Stan code or claim private parity;
- transmit or print passwords, MFA codes/seeds, cookies, tokens, customer data, or cloud secrets;
- trust `creatorId`, amount, paid state, file path, redirect, provider event, or forwarded client IP from the browser without server verification;
- equate Git push, CI build, Terraform plan, Kubernetes YAML, HTTP 200, or UI appearance with complete E2E/production proof;
- make destructive database/cloud changes without exact target resolution and explicit authority.

## 19. Recommended reading order

1. `docs/CURRENT_STATE_AND_LLM_HANDOFF.md` — current snapshot and operating truth.
2. `docs/FEATURE_PARITY.md` — completeness matrix.
3. `docs/api-contract.md` — detailed HTTP bodies and responses.
4. `docs/product-design.md` — frontend/backend/data flow by product section.
5. `docs/backend-architecture.md` — Java package/layer responsibilities.
6. `docs/LOCAL_SETUP.md` — clean-laptop operation and troubleshooting.
7. `docs/INSTAGRAM_AUTODM.md` — Meta boundary, queue, and launch gates.
8. `docs/india-launch-integrations.md` — Razorpay-first integration boundary.
9. `docs/release-architecture.md` and `docs/production-runbook.md` — infra-first promotion, canary, rollback, incidents.
10. `docs/AWS_REGIONAL_BOOTSTRAP.md` — production AWS gaps and one-region target.
11. `docs/MULTICLOUD_DEPLOYMENT.md` — AWS/Azure/OCI runtime contract.
12. `docs/creator-store-system-design.drawio` — editable architecture visualization.

## 20. Immediate next action after this snapshot

1. Run all current checks again from the `test` heads.
2. Decide whether to redeploy the newest backend/frontend artifact digests to the disposable AWS endpoint before its deadline.
3. If continuing AWS testing, use a fresh MFA-backed, short-lived operator session; verify exact account/region/release and rerun the post-deploy verifier.
4. Test current profile settings and all eight authoring flows through an automated browser suite, not only manual clicking.
5. Select one P0 vertical slice—recommended: authentication recovery/verification and TLS before real-user testing, or verified Razorpay sandbox order-to-entitlement before money testing—and complete it end to end.
