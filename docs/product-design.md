# Creator Store compatible product design

## Scope and evidence boundary

This is an original implementation of a creator-store product based on user-supplied observations of public UI, routes, HTTP methods, and endpoint paths. The reference material does **not** contain Stan response bodies, authorization tokens, private source, or its production database. Consequently:

- paths specifically observed in the reference are preserved where useful;
- response shapes in this project are deterministic contracts designed here;
- the SQL schema is inferred from product behavior and is not represented as Stan's schema;
- branding, writing, visual design, and demo data are original;
- payment, Instagram, email, calendar, video, and file-delivery providers are safe integration boundaries, not simulated production connections.

## Simplest deployable architecture

```text
Browser
  |
  | :3000, static React application and /api reverse proxy
  v
NGINX frontend container
  |
  | HTTP /api/*
  v
Spring Boot API container :8080
  |
  | JDBC, parameterized SQL
  v
PostgreSQL container :5432
```

The web process is static and the API process is stateless. PostgreSQL is the source of truth. In local development all three containers share one private Docker network. In AWS, the same boundaries become an EKS frontend Deployment, EKS backend Deployment, and private Aurora PostgreSQL.

## Section-by-section behavior

### Home

The frontend calls `GET /api/v1/dashboard?creatorId=1`. It renders visits, leads, orders, revenue, payout readiness, and an onboarding checklist. The backend combines `stores`, `products`, `orders`, `store_visits`, and `leads`. This is a read-optimized summary endpoint: the browser avoids five independent round trips, while the API remains responsible for a coherent snapshot.

For higher volume, update raw event/order tables synchronously and project aggregates asynchronously into a daily creator metrics table. Cache the summary for 15–60 seconds and invalidate after product publication or payment events.

### My Store

`GET /api/v1/store` returns store design metadata, ordered products, and the supported product-type catalog for the authenticated creator. Aggregate `POST /api/v1/products` and `PATCH /api/v1/products/{id}` now validate eight types: lead magnet, digital download, meeting, fulfillment, course, membership, webinar, or community. Common card fields and a schema-versioned type configuration commit together, and product type becomes immutable after creation. The public storefront reads only `status='published'` products.

The catalog uses two related representations rather than one sparse `products` table:

1. `products.configuration_json` is the schema-versioned creator-authoring source for reconstructing the editor.
2. A successful aggregate write transactionally synchronizes the normalized rows needed by operational queries: `course_modules`/`course_lessons`, `webinar_sessions`, `availability_schedules`/product-owned `bookings`, `product_payment_plans`, and `product_checkout_fields`.

This dual representation needs transaction and drift tests. Never update only the JSON or only a projection. The normalized rows are implementation projections, not a second independently editable source of truth.

Files remain staged separately because multipart bytes cannot be atomically included in the JSON aggregate request. An upload-required download or lead magnet is created as a draft, receives its owner-scoped upload, and is published only after readiness validation. Local development stores opaque object keys below `APP_STORAGE_DIR`; production files belong in cloud object storage with malware scanning, and delivery uses an authorization check plus short-lived signed access.

### Product-type configuration boundary

| Type | Creator can configure | Safe storefront summary | Buyer/runtime work that remains separate |
|---|---|---|---|
| Lead magnet | upload/HTTPS redirect delivery, name/email/phone capture choices and consent text | free-resource label and requested capture fields | consent submission, lead persistence, confirmation and gated delivery |
| Digital download | upload/HTTPS redirect delivery | downloadable-product label and non-secret metadata | paid entitlement and signed/controlled delivery |
| Meeting | location/details, timezone, duration, capacity, notice, buffer and dated slots | duration, timezone and available public slots | calendar synchronization and conflict-safe book/cancel/reschedule |
| Webinar | location, timezone, default duration/capacity and dated sessions with private join URLs | public session start/end and capacity, never join URL | provider event, registration, reminders and attendance |
| Course | ordered modules/lessons, video metadata, descriptions, drip delay and assets | module/lesson counts and drip summary | learner portal, streaming, progress and completion |
| Membership | one or more priced interval plans, public benefits and private welcome message | plan prices/intervals and intentionally public benefit summary | recurring billing lifecycle and entitlement enforcement |
| Fulfillment | turnaround, delivery format, private buyer instructions and checkout questions | turnaround, delivery-format label and safe question definitions | work queue, proof/delivery and buyer status portal |
| Community | platform, private access URL, public benefits and private welcome message | platform label and intentionally public benefits | protected posts, moderation and membership enforcement |

Creator-authoring detail is owner-scoped at `GET /api/v1/products/{id}/configuration` and can include parsed private configuration plus safe file metadata and normalized projections. Public detail is a different contract at `GET /api/public/{handle}/products/{productId}`: it builds `public_configuration` from an explicit allowlist and never serializes raw `configuration_json`.

Private delivery fields include download redirect URLs, storage object keys and local paths, provider join/access URLs, private buyer instructions, welcome messages, unpublished lessons, and credentials. Exposing any of them would bypass lead capture, payment, entitlement, or provider access controls.

### Success

`GET /api/v1/success` returns curated lesson metadata. It is intentionally not coupled to creator transaction data. In production, lesson catalog data can be served from a CMS or versioned static JSON and cached at the CDN. Progress would use a separate `lesson_progress(creator_id, lesson_id, completed_at)` model.

### Income

`GET /api/v1/income?creatorId=1` returns gross, fees, net, available/pending cashout, and the latest orders. The frontend renders summary cards, a revenue visualization, and a table. `orders` is the local ledger view; a payment processor remains authoritative for charge state.

The India-first MVP now creates idempotent Razorpay or optional Stripe sessions and verifies provider webhook signatures over raw request bytes. Only a verified webhook can mark a checkout paid. The next production requirements are an append-only double-entry ledger, refund/dispute rows rather than destructive updates, settlement reconciliation jobs, async webhook processing, and cursor pagination. Never derive available cashout solely from the UI summary query.

### Analytics

`GET /api/v1/analytics?creatorId=1` returns visit, lead, order, revenue, conversion inputs, and traffic-source counts. The storefront sends best-effort `POST /api/events/view` with a public handle; the backend resolves the published creator and records a canonical path without trusting a client tenant ID. Legacy `POST /events` remains compatibility-only. Click tracking uses `POST /api/events/click`.

At low scale PostgreSQL is enough. At high write scale, acknowledge events into Kinesis or SQS, batch them into S3, aggregate with a stream consumer, and query rollups from a warehouse/OLAP store. Do not make storefront rendering wait on analytics writes.

### Customers

`GET /api/v1/customers?creatorId=1` lists at most 5,000 contacts for the MVP. `POST /api/v1/customers` adds a contact and returns `409` for a duplicate creator/email pair. The UI implements add-contact and exposes the CSV import boundary.

Production adds cursor pagination, background CSV parsing, row-level validation reports, consent/source timestamps, suppression status, GDPR/CCPA deletion workflows, and tenant-scoped authorization on every query.

### Community

The current frontend provides the section and the observed community-entry experience. `POST /api/v1/users/experiments/join_communities` and `GET /api/v1/users/experiments/community_stats` expose deterministic demo contracts. A production community should be a separately permissioned bounded context with membership, posts, replies, moderation, and notifications.

### More: Funnels, Appointments, Referrals, Email Flows, AutoDM

`GET /api/v1/more?creatorId=1` advertises the feature set and returns funnel/booking data. The inferred schema includes funnels, funnel steps, availability schedules, bookings, automations, keywords, and automation stats. The observed AutoDM read endpoints are exposed as:

- `GET /api/v1/automations/instagram-posts-metadata`
- `GET /api/v1/automations/analytics?automation_ids=...`

Instagram webhook verification and an explicitly confirmed, allowlisted test-message endpoint are implemented as the safe provider boundary. Rule-driven AutoDM publishing remains absent until OAuth tokens are encrypted, App Review/permissions are approved, consent/audit evidence exists, and rate limits, idempotent queues, retries, and dead-letter handling are operational. Email, calendar, and social publishing likewise remain external side effects requiring confirmation.

### Settings

`GET /api/v1/settings` aggregates Profile, Integrations, Billing, Payments, Email Notifications, and Security tab inputs for the authenticated creator. `PATCH /api/v1/settings/profile` updates only the creator resolved from the opaque session; it normalizes and validates the display name, public store address, bio, and optional phone, rejects reserved or conflicting addresses, and returns the persisted profile. Changing the public address makes the new `/{address}` route live and the old route unavailable, so the UI warns the creator to update shared links. `GET /api/v1/integrations` returns safe provider connection status only. Secret values never appear in a response or in the repository.

Production settings writes need per-field validation, optimistic concurrency, audit history, reauthentication for security/payment changes, secret-manager references for credentials, and webhook-driven provider state.

### Registration and onboarding

`OPTIONS/POST /api/v1/authentication/check-unique-taken` checks only public-handle availability so it cannot enumerate registered emails. `POST /api/auth/register` validates input and atomically creates the creator, default store, notification preferences, and hashed opaque session; the response sets the same httpOnly cookie used by login. The selected Starter or test-stage Creator Pro journey continues in the frontend, while paid entitlement remains disabled until provider-hosted checkout and a verified subscription webhook exist.

Production authentication should use Cognito or another OIDC provider, verified email/phone, rate limits, bot defenses, secure cookies, MFA, password reset, session revocation, and account recovery. The application should not become its own identity provider without a compelling reason.

### Public storefront

`GET /api/public/{handle}` returns the creator profile, published store, published links, and a compact published-product collection. `GET /api/public/{handle}/products/{productId}` returns the selected published product plus its sanitized, type-specific `public_configuration`. A published lead magnet accepts idempotent visitor data at `POST /api/public/products/{productId}/leads`; the backend derives the creator from the product, validates configured name/phone/consent requirements, snapshots consent text, and never returns a private delivery URL. PostgreSQL/HTTP and browser tests verify the read contracts without exposing raw creator configuration or delivery secrets. These are the highest-read endpoints and the best CDN targets; cache by handle/product with a short TTL and purge both keys on publish or public-field changes. Product checkout must create a server-side payment session; price and product ownership must be re-read from the database and never trusted from the browser.

## Backend organization for the next stage

The MVP intentionally stays in one deployable Spring Boot service. Before team growth, split code into packages—not microservices—around `identity`, `catalog`, `commerce`, `audience`, `analytics`, `automation`, and `settings`. Each package owns its controllers, application services, repositories, DTOs, and tests. Extract a service only after independent scaling, release cadence, data ownership, or failure-isolation needs are measured.

## Frontend optimization

The current Vite build is a client-side application with one API aggregator per section. Next optimizations:

1. Split each section with `React.lazy` so public-store visitors never download admin modules.
2. Add TanStack Query for request deduplication, cancellation, caching, retries, and optimistic mutations.
3. Use generated TypeScript clients from OpenAPI and migrate JSX to strict TypeScript.
4. Virtualize customer/order tables and use cursor pagination.
5. Upload files directly to S3 with short-lived presigned POSTs.
6. Put static assets behind CloudFront with content-hashed immutable caching and a strict CSP.
7. Track Core Web Vitals and keep the public storefront bundle on a tighter budget than the admin application.

## Backend optimization

At low scale, parameterized JDBC and indexed PostgreSQL queries are adequate. The first optimizations should be measurement-led:

1. Add Actuator, Micrometer, OpenTelemetry traces, structured logs, and per-route latency/error metrics.
2. Use Flyway migrations instead of startup `schema.sql` before any shared environment.
3. Add Hikari pool limits per replica so Kubernetes scaling cannot exhaust Aurora connections; introduce RDS Proxy when replica count grows.
4. Add cursor pagination and composite indexes verified with `EXPLAIN ANALYZE`.
5. Use Redis only for measured hot reads, idempotency keys, and rate limits.
6. Move analytics, email, webhooks, exports, and file processing behind queues.
7. Add tenant authorization before every repository call; `creatorId=1` is demo-only and must be derived from the authenticated principal in production.

## Scaling modes

| Workload | First change | Database pattern | Caching/queueing |
|---|---|---|---|
| Low read, low write | One API and web replica per active region | One Aurora writer | None beyond CDN assets |
| High read, low write | Scale web/API horizontally | Aurora readers for explicitly read-only queries | CloudFront + Redis for public stores |
| Low read, high write | Protect API with bounded pools | Writer sized for IOPS; partition event tables | Kinesis/SQS for analytics and webhooks |
| High read, high write | Separate public-read and command workloads | Global DB plus regional read endpoints; writer routing | CDN, Redis, queues, rollup store |

Multi-region writes are not enabled by merely adding Kubernetes replicas. A request that changes a store, order, or customer must reach the writer region unless the data model is deliberately redesigned for conflict resolution.

## Production completion checklist

This repository now has real provider adapters, signed webhook ingress, disabled/test/live modes, and Kubernetes secret wiring, but it is not yet authorized for live money or public Instagram automation. Before production: OIDC authentication and tenant authorization; Flyway migrations; append-only ledger and settlement reconciliation; S3 uploads and malware scanning; provider OAuth/App Review; Secrets Manager rotation; rate limits; audit logs; India legal/tax/privacy/refund review; consent/deletion workflows; integration/contract/end-to-end/load/security tests; backup/restore drills; SLOs; dashboards; alarms; canaries; incident runbooks; and reviewed staged promotion from dev to preprod to prod.
