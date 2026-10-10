# Creator Store production-readiness execution plan

Plan date: **2026-10-10**  
Current release verdict: **TEST_ONLY**  
Scope: frontend, Spring Boot backend, PostgreSQL, provider integrations, GitHub Actions, Terraform/Kubernetes, security, quality, operations and launch readiness.

This is the ordered engineering backlog for turning the current Creator Store from a useful test system into a production service. It is not a request to split the modular monolith into microservices. The current modular monolith is the right starting shape; correctness, release safety and operational proof come first.

## 1. Current starting point

The current public test release proves that a React/Nginx frontend, one Spring Boot application and PostgreSQL can run together on AWS. The deployment verifier passed the selected public routes, release pins, topology and edge-IP checks at the time it was run.

That does **not** yet prove production behavior. The present system must remain synthetic-data-only because it has known tenant-authorization, fulfillment, event-atomicity, migration, storage, TLS, testing, observability and availability gaps. Its disposable-infrastructure expiration marker is also past due and must be explicitly renewed or the stack must be destroyed.

The target progression is:

```text
trustworthy local build
  -> trustworthy shared test environment
  -> complete non-money vertical slice
  -> sandbox commerce/provider flows
  -> repeatable and reversible delivery
  -> observable single-region pre-production
  -> limited customer beta
  -> measured scaling
  -> multi-region only when business and recovery requirements justify it
```

## 2. Rules that apply to every feature

A feature is not complete when only the happy-path UI works. Its Definition of Done is:

1. product behavior and failure behavior are written down;
2. authorization and tenant ownership are explicit;
3. API contract and database changes are reviewed;
4. a forward migration exists and its compatibility window is documented;
5. unit, PostgreSQL integration and relevant browser/contract tests pass;
6. duplicate, retry, timeout and concurrent-request behavior are tested where relevant;
7. logs, metrics and traces expose success and failure without leaking secrets or PII;
8. operational alerts and a short runbook exist for customer-impacting features;
9. rollout is behind a feature flag or has another bounded rollout mechanism;
10. rollback is safe for both code and schema;
11. documentation and the release manifest identify exactly what was shipped;
12. the exact built artifact—not a later rebuild—passes post-deployment verification.

## 3. Critical path

The following order is mandatory because each stage makes the next one safe:

```text
P0 ownership/security fixes
  -> durable migrations and PostgreSQL tests
  -> event/payment/booking correctness
  -> integrate frontend branches and remove fake behavior
  -> TLS, verification email and object storage
  -> golden-journey browser tests
  -> build-once signed release and automated test deployment
  -> observability, alerts, rollback and restore drills
  -> one-region HA pre-production
  -> provider sandbox certification
  -> load/soak/canary evidence
  -> limited production beta
```

Multi-region, Kafka and microservice extraction are **not** on this critical path.

## 4. Phase 0 — Control the baseline before changing it

Goal: every engineer works from the same known release and no one accidentally treats the current public environment as production.

### BASE-001 — Declare the environment classification

- Label the current K3s environment `test`, not production.
- Permit synthetic creators, buyers and payment/provider events only.
- Display an environment banner in non-production.
- Decide immediately whether to renew or destroy the expired AWS stack.

Acceptance:

- environment name and data policy appear in the application and runbook;
- a scheduled expiry check alerts before expiration and tears down only after an explicit policy decision;
- no real payment or Instagram provider credential is enabled.

### BASE-002 — Establish one source release

- Create a release manifest that binds frontend commit/digest, backend commit/digest, infrastructure commit, schema version, configuration version and rollback predecessor.
- Integrate the Identity-v1 frontend with `codex/product-merchandising-ui`; do not deploy the merchandising branch directly because it is based on older identity code.
- Remove `latest` from deployable paths.

Acceptance:

- a reviewer can map the running pods to the exact source commits;
- the integrated frontend passes both existing test sets and a production build;
- deployment rejects missing or mutable image references.

### BASE-003 — Repository governance

- Protect `main`; require pull requests, review, passing checks and conversation resolution.
- Add role-based CODEOWNERS for identity/security, commerce/data, frontend and infrastructure paths.
- Protect `test`, `preprod` and `prod` GitHub environments with least-privilege reviewers.
- Enable dependency update automation, secret scanning and CodeQL or an equivalent static-analysis gate.

Acceptance:

- an ordinary developer cannot directly push or deploy to production;
- a failed required check prevents merge;
- emergency access is logged, time-bounded and reviewed.

## 5. Phase 1 — Correctness and security blockers

Goal: stop cross-tenant access, lost events and contradictory commerce state before adding features.

The Identity/Security and Commerce/Data groups can work in parallel, but Phase 1 is one release gate.

### SEC-001 — Enforce tenant ownership centrally

- Derive creator identity only from the authenticated session or service identity.
- Remove trusted `creator_id` values from creator-owned request bodies.
- Apply a reusable authorization policy to products, tags, themes, customers, files, automations, orders, analytics and settings.
- Return only public profile projections from handle-based public endpoints; never email or phone.

Acceptance:

- a two-tenant negative test exists for every owner API;
- Creator A cannot read, mutate, infer existence of or export Creator B's private resources;
- public handle lookup exposes only the documented public fields;
- authorization failures are audited without logging PII.

### ID-001 — Make one identity model authoritative

- Document the target identity/profile/credential/session/verification tables.
- Stop indefinite dual reads and writes between legacy creator fields and normalized identity tables.
- Backfill, compare, cut over reads, cut over writes and remove legacy authority in separate reversible steps.
- Set a stable production fingerprint/signing secret; never generate a new secret per process.

Acceptance:

- a migration report accounts for every user and collision;
- old and new application versions can coexist during the documented deployment window;
- restarting or scaling the API does not invalidate legitimate sessions unexpectedly;
- rollback does not corrupt the chosen source of truth.

### AUTH-001 — Finish secure signup, login and recovery

- Add transactional verification-email delivery for test and later production.
- Define password requirements, reset-token lifetime/single use, session rotation, logout-all-devices and sensitive-action reauthentication.
- Use Secure, HttpOnly and appropriate SameSite cookies behind TLS.
- Combine edge IP controls with account-aware/distributed throttling; do not rely only on per-JVM counters.
- Add generic responses to prevent account enumeration.

Acceptance:

- signup -> verification -> login -> logout -> recovery is tested in a real browser;
- expired/reused verification and reset tokens fail safely;
- fixation, brute-force and enumeration tests pass;
- multiple API replicas enforce one rate-limit policy;
- logs never contain passwords, raw tokens or session cookies.

### DATA-001 — Replace startup DDL with migrations

- Introduce Flyway or Liquibase as the only production schema authority.
- Baseline the existing database and convert current DDL to versioned migrations.
- Run migrations as a release step/job, not competitively from every API replica.
- Adopt expand/migrate/contract changes so N and N-1 application versions can overlap.

Acceptance:

- blank-database install, current-database upgrade and failed-migration recovery are automated;
- two API replicas can start without racing schema changes;
- schema checksum drift blocks deployment;
- a restore plus migration replay succeeds in an isolated environment.

### PAY-001 — Implement atomic payment inbox and fulfillment

- Keep providers behind the payment strategy interface; start with Razorpay sandbox for the India launch.
- Verify signatures against the raw request body, persist an idempotent provider-event inbox and process the state transition transactionally.
- Connect successful authorized/captured events to order, booking, enrollment, membership or download entitlement fulfillment.
- Model checkout/payment/order/fulfillment/refund as explicit state machines.
- Add reconciliation for events that remain received, processing or inconsistent.

Acceptance:

- duplicate, reordered and delayed webhook tests produce exactly one business outcome;
- a failure after inbox insert is safely retried and cannot strand a paid checkout;
- every successful sandbox payment creates the expected order and entitlement;
- invalid signatures change no state;
- refund/cancellation transitions are idempotent and auditable.

### BOOK-001 — Reserve scarce slots atomically

- Create an expiring slot reservation before starting remote payment/provider work.
- Use a unique database constraint or row lock so one slot has at most one active reservation/booking.
- Release expired/failed reservations with an idempotent sweeper.

Acceptance:

- a concurrency test with many buyers attempting one slot yields exactly one winner;
- provider timeout does not permanently consume the slot;
- a confirmed purchase cannot lose its booking;
- retrying the same request does not create a second booking.

### DM-001 — Make Instagram inbound processing lossless and idempotent

- Validate and durably record a provider event before acknowledging it.
- Atomically couple inbox state with job creation using one transaction or a transactional outbox.
- Use the provider event ID as the idempotency key.
- Replace “swallow exception and return success” paths with explicit retryable/non-retryable outcomes.
- Change automation creation to `INSERT ... RETURNING id`.

Acceptance:

- duplicate comments result in at most one intended DM;
- failure between receipt and enqueue is recoverable by retry/reconciliation;
- invalid signatures do not enqueue work;
- concurrent automation creation attaches rules to the correct automation;
- provider approval and OAuth remain disabled until the feature passes Meta policy review.

## 6. Phase 2 — One complete, truthful product slice

Goal: prove one creator and one visitor can complete a non-money journey without mock behavior.

### FE-001 — Integrate the active frontend work

- Rebase/cherry-pick the merchandising experience onto the current Identity-v1 line.
- Preserve signup, session and recovery behavior while adding product detail routes.
- Split the monolithic entry bundle by route and add an application error boundary.
- Add request timeout/abort, offline, session-expiry and schema-validation handling.

Acceptance:

- existing identity and merchandising tests pass in one commit;
- refresh/deep-link works on every route;
- expired sessions return the user to login without losing unsaved work where safe;
- API errors never leave permanent “Loading…” UI.

### PROD-001 — Finish type-specific product creation

Each type must have a documented schema, editor, preview, validation and customer behavior:

- promotion/external link;
- lead magnet;
- digital download;
- custom service;
- one-to-one meeting;
- course;
- membership;
- webinar;
- community.

Do not use one generic title/description/price form for all types. Shared fields stay common, while type-specific configuration uses validated typed payloads.

Acceptance:

- each type has a create/edit/publish/unpublish/delete flow;
- draft and published projections are separate;
- invalid combinations are rejected in both UI and API;
- phone preview and public storefront use the same published projection;
- pin/unpin order is persisted and deterministic;
- creator/profile changes update both workspace and preview.

### MEDIA-001 — Add durable media

- Store metadata in PostgreSQL and bytes in S3-compatible object storage.
- Use upload-init/finalize/delete APIs with short-lived signed URLs.
- Validate MIME and magic bytes, enforce size limits, scan malware and create bounded image variants.
- Model cover image, ordered gallery and lifecycle/orphan cleanup.
- Serve public derivatives through an authorized/CDN path, never from a pod filesystem.

Acceptance:

- uploads survive pod/node replacement;
- unsupported or malicious content is rejected/quarantined;
- deleting/reordering images is reflected in editor, phone preview and public detail page;
- private draft assets cannot be enumerated publicly;
- an orphan cleanup job is safe and observable.

### STORE-001 — Publish a creator storefront

- Implement draft/publish/version behavior for profile, theme, links, products and pins.
- Add a public-store projection optimized for one fetch or a bounded set of queries.
- Add metadata/OG cards, accessible semantic structure and responsive layout.
- Define cache-control/ETag and invalidate or version cache on publish.

Acceptance:

- creator signup -> profile -> product/link -> preview -> publish -> anonymous view works end to end;
- a draft never leaks to the public route;
- pinned items appear first, followed by the stable creator-defined order;
- a publish is atomic from the visitor's perspective;
- public view remains usable on supported mobile and desktop browsers.

### UX-001 — Remove misleading UI

- Wire, hide or clearly label every no-op control.
- Replace decorative analytics/income graphs with data-driven series or an honest empty state.
- Fix modal focus, keyboard operation, announcements, contrast and touch targets.
- Add dynamic document title and social metadata.

Acceptance:

- every visible primary control performs its named action or is explicitly marked unavailable;
- zero-data accounts never display invented revenue or traffic trends;
- automated accessibility checks pass and a keyboard-only manual audit has no blocking defect.

## 7. Phase 3 — Automated quality and security evidence

Goal: make regressions fail before merge and make release decisions evidence-based.

### QA-001 — Layered test pyramid

- Backend unit tests for pure business rules.
- Testcontainers PostgreSQL integration tests for constraints, transactions, `SKIP LOCKED`, migrations and concurrency.
- API contract tests binding frontend expectations to backend schemas.
- React component tests for forms, errors, permissions and state transitions.
- Playwright browser tests for the golden creator and visitor journeys.

Required golden journeys:

1. signup/verify/login/recovery;
2. create profile/store/product/media/pin/publish;
3. anonymous storefront/product detail/click tracking;
4. Razorpay sandbox checkout/webhook/fulfillment/refund;
5. meeting reservation/concurrency/cancellation;
6. AutoDM test-provider webhook/job/retry/dead-letter flow;
7. tenant isolation and role/access negative paths.

Acceptance:

- tests run in pull requests and against the exact release candidate;
- flaky tests are quarantined only with owner and expiry, not silently retried forever;
- critical-state coverage is measured by states/transitions and failure cases, not just line percentage.

### QA-002 — Device, accessibility and failure matrix

- Test supported Chrome, Safari, Firefox and Edge versions.
- Test representative iPhone, Android phone, tablet and desktop viewports with touch and keyboard.
- Automate axe checks and manually audit the critical journeys with screen reader/keyboard.
- Inject offline, slow, timeout, 401, 403, 409, 429 and 5xx responses.

Acceptance:

- supported-device policy is published;
- no P0/P1 issue remains in a golden journey;
- failure states give a recoverable action and preserve data where safe;
- visual-regression baselines cover landing, auth, dashboard, editor, preview and storefront.

### SEC-002 — Security program minimum

- Threat-model identity, multi-tenancy, payment, media, provider webhooks and admin operations.
- Add SAST, dependency, secret, container and IaC scans with severity policy and expiry-bound exceptions.
- Add safe DAST against the test candidate.
- Add CSRF, XSS, SSRF, IDOR/BOLA, upload abuse, mass assignment and rate-limit tests.
- Create an immutable audit log for security-sensitive changes.

Acceptance:

- every high-risk threat has a control and validation test;
- no unresolved critical/high exploitable finding reaches pre-production;
- exceptions have owner, justification, compensating control and expiry;
- sensitive values are redacted in all logs and artifacts.

## 8. Phase 4 — Build once and deploy the exact artifact

Goal: a protected GitHub workflow deploys a reviewed release to test and can return to the prior release.

### REL-001 — Artifact and supply-chain integrity

- Build each artifact once in CI; run tests against it and promote the same digest.
- Pin actions and base images by immutable versions/digests.
- Produce SBOM, vulnerability result, provenance/attestation and signatures.
- Verify signature/policy before deployment.
- Restrict release SHA to an ancestor of protected `main` or a signed release tag.

Acceptance:

- source -> artifact -> environment is traceable in both directions;
- changing an image tag cannot change deployed bytes;
- unsigned/unapproved artifacts are rejected;
- the release manifest is stored with evidence and rollback predecessor.

### INFRA-001 — Apply reviewed infrastructure

- Terraform plan runs against the intended environment/state and produces a human-readable summary.
- Approval binds environment, commit, variables, provider lock file and exact plan.
- Apply the approved plan or an equivalently cryptographically bound plan; do not silently re-plan after approval.
- Run policy checks for public exposure, encryption, IAM scope, backup and destructive changes.

Acceptance:

- apply cannot target a different environment than the approval;
- drift is detected and reviewed;
- destructive replacements require explicit approval and a rollback/data plan;
- infrastructure output needed by the application is published through a typed contract.

### CD-001 — Automate the current test deployment

- Move the current CloudShell/SSM K3s release runbook behind a protected GitHub Actions workflow.
- Authenticate to AWS with OIDC and least-privilege environment roles.
- Render exact digest manifests before first apply.
- Run rollout status, API/browser smoke, business write/read probe and release verifier.
- Automatically return to the previous release manifest on a failed application gate when schema compatibility allows it.

Acceptance:

- a merge does not directly deploy production; it produces a promotable candidate;
- an authorized test deployment needs no copied password, long-lived cloud key or manual shell command;
- failed health/business checks stop promotion and preserve diagnostic evidence;
- rollback is rehearsed and timed.

## 9. Phase 5 — Observability and operability

Goal: know that the service is wrong before customers report it, and know how to recover it.

### OBS-001 — Telemetry foundation

- Add structured JSON logs with request/trace ID, release ID and safe actor/resource identifiers.
- Add Spring Boot Actuator, Micrometer and OpenTelemetry.
- Separate liveness (process is alive) from readiness (can safely accept required work).
- Measure request rate/errors/latency, JVM, pools, DB, cache, queues, provider calls and business outcomes.
- Add frontend error/session/performance telemetry with privacy controls.

Acceptance:

- one customer journey can be traced across web, API, database/job and provider adapter;
- dashboards can separate app failure, DB saturation, provider failure and deployment regression;
- health endpoints cannot falsely mark a DB-dependent pod ready;
- logs contain no secrets, payment details or inappropriate PII.

### SRE-001 — SLOs, alerts and runbooks

- Product and engineering ratify availability, latency, correctness, durability, RTO and RPO objectives.
- Add browser/API synthetics from outside the cluster.
- Alert on customer symptoms and exhausted error budget, not raw noise alone.
- Route alerts to a tested notification channel and map each actionable alert to a runbook.
- Track deployment frequency, lead time, change-failure rate and recovery time.

Acceptance:

- a synthetic failure reaches the responsible on-call path;
- every page has an owner and immediate diagnostic/mitigation steps;
- a game day demonstrates incident declaration, rollback/failover, communication and recovery;
- dashboards and alerts identify the deployed release.

### DR-001 — Backup and recovery proof

- Define data classification and retention.
- Enable policy-aligned PITR/backups and deletion protection for customer environments.
- Test restore to an isolated network, integrity checks and application startup.
- Test schema-forward recovery and document credentials/secrets recovery.

Acceptance:

- measured restore time and recovery point meet ratified RTO/RPO;
- restored orders, entitlements, accounts and media references reconcile;
- the drill result and corrective actions are retained.

## 10. Phase 6 — One-region production platform

Goal: remove single-node and Single-AZ failure from the customer-serving path.

The low-cost single-node K3s environment can remain for development/test. It is not the production topology.

### PLAT-001 — Managed regional edge and compute

- Route53/domain, ACM TLS, managed load balancer/ingress and narrowly configured WAF/rate limits.
- Private worker/data subnets and least-privilege ingress/egress.
- At least two schedulable nodes across AZs and at least two stateless web/API replicas.
- Pod disruption budgets, topology spread, resource budgets and tested rolling updates.
- Metrics Server and node autoscaling if HPA is enabled.
- Install and verify ingress, external-secrets, metrics and telemetry controllers rather than only declaring their resources.

Acceptance:

- loss of one application pod or one worker node does not break a golden journey;
- TLS is valid and HTTP redirects to HTTPS;
- NetworkPolicy allows intended web -> API and API -> required dependencies while denying tested unwanted paths;
- pod and node scaling works under a controlled load test.

### DATA-002 — Production data services

- Multi-AZ PostgreSQL for production, connection budgets and connection-pool monitoring.
- Encrypted object storage with lifecycle/versioning as required.
- Managed secrets with rotation and workload identity.
- Consider Redis only when the public-store/cache or distributed-rate-limit measurements justify it.

Acceptance:

- database failover and connection recovery are tested;
- no pod disk contains authoritative customer media;
- secret rotation can occur without rebuilding images;
- application replicas cannot exhaust database connections under declared capacity.

### ENV-001 — Promotion chain

- `test`: synthetic data, continuous candidate testing, low-cost topology acceptable.
- `preprod`: production-shaped topology/configuration with sandbox providers and anonymized/synthetic data.
- `prod`: customer data/providers, protected promotion, canary, on-call and rollback.
- Promote a release manifest; never rebuild between environments.

Acceptance:

- environment-specific configuration is separate from code and secrets;
- the same digests move test -> preprod -> prod;
- production access, approvals and audit history are demonstrable.

## 11. Phase 7 — Complete business features in sandbox

Goal: convert UI demonstrations into supported, reconcilable product capabilities.

### COM-001 — Commerce and buyer lifecycle

- Product pricing/currency/tax fields, checkout, payment, order, invoice/receipt, entitlement, refund and cancellation.
- Razorpay first; keep Stripe or future providers behind the same domain interface.
- India-specific GST/invoice/refund and marketplace/payment-flow decisions require finance/legal review.
- Buyer order history and secure delivery/download access.

Acceptance:

- finance can reconcile provider settlement to internal payment/order ledger;
- creator and buyer see consistent statuses;
- support can diagnose/refund without direct database edits;
- no raw card data enters Creator Store systems.

### AUTO-001 — Instagram AutoDM product

- Creator OAuth connection, token lifecycle/revocation, eligible media selection, keyword/rule editor and message templates.
- Webhook verification, durable inbox/outbox, worker deployment, retry/backoff/dead letter/replay and rate-limit handling.
- Consent/policy disclosures, opt-out/abuse controls and provider-review evidence.

Acceptance:

- a provider-approved test account completes connect -> configure -> comment -> exactly-once-intended DM;
- revoked/expired permissions stop safely and notify the creator;
- dead-letter operations support bounded replay;
- launch remains blocked until Meta app review and current platform-policy compliance are confirmed.

### ANALYTICS-001 — Honest analytics and income

- Define event names, schema versions, ownership, consent and retention.
- Keep storefront rendering independent of non-critical analytics writes.
- At low scale use a transactional outbox/PostgreSQL worker; introduce SQS/DLQ when durability/throughput or failure isolation requires it.
- Batch/aggregate views, clicks, conversion and income series; reconcile commerce metrics to the ledger.

Acceptance:

- queue/event sink outage does not block storefront reads;
- duplicates/replays do not inflate defined metrics;
- dashboard numbers can be traced to events/orders and state their timezone/window;
- deletion/privacy policy covers raw and aggregated data.

### ADMIN-001 — Operations and support tooling

- Role-based internal support access, creator/account lookup, provider-event history, job/dead-letter inspection and safe retry.
- Feature-flag control, audit trail and reason-required privileged actions.
- Customer support/export/delete workflows.

Acceptance:

- common incidents are resolved without production database shell access;
- every privileged read/write is attributable and reviewable;
- support roles cannot view payment secrets or unrelated tenant data.

## 12. Phase 8 — Capacity, resilience and progressive delivery

Goal: prove the one-region system under expected launch and failure conditions.

### PERF-001 — Capacity model and load tests

- Define launch assumptions: active creators, viral-storefront fan-out, dashboard traffic, writes/sec, webhook burst, media volume and provider latency.
- Run baseline, ramp, spike and soak tests against production-shaped preprod.
- Record latency/error/resource curves and the first saturated dependency.
- Establish headroom and a scaling/cost model.

Acceptance:

- ratified SLOs hold at launch load plus agreed headroom;
- database pool, CPU/memory, storage IO and queue age remain within defined bounds;
- the team knows the tested maximum and degradation behavior.

### RES-001 — Failure testing

- Restart pods/workers during traffic; remove one node; exercise database failover; inject provider timeouts/429/5xx; pause the async sink.
- Prove idempotency, backpressure, circuit breakers/bulkheads and recovery.
- Verify no lost paid entitlement or AutoDM event during each allowed fault.

Acceptance:

- customer-facing degradation matches documented behavior;
- critical state reconciles after recovery;
- alerts fire and runbooks lead to recovery within objectives.

### REL-002 — Canary and automatic abort

- Promote 5/25/50/100 percent or another justified progression.
- Compare technical SLOs and business correctness metrics against the stable release.
- Abort/rollback automatically on a material regression.

Acceptance:

- a deliberately bad release is detected and stopped in preprod;
- database changes remain compatible with both canary and stable versions;
- promotion and rollback evidence is stored with the release.

## 13. Phase 9 — Limited beta and production launch

Goal: release to a controlled creator cohort with an explicit go/no-go decision.

Before beta:

- all P0/P1 issues closed with deterministic evidence;
- independent functional, UX/accessibility, security/privacy, resilience, delivery and product audits pass the exact release manifest;
- external or independent penetration test completed for the public attack surface;
- terms, privacy, consent, retention, refunds, tax/payment responsibilities and incident communications reviewed by qualified owners;
- customer support, on-call, status communication and escalation are staffed;
- restore, rollback, provider outage and account-compromise game days pass;
- product analytics and kill switches can bound blast radius.

Beta rollout:

1. internal synthetic accounts;
2. a small invited creator cohort with sandbox or tightly limited money/provider capabilities;
3. expand only while SLO, support, security and reconciliation evidence remains healthy;
4. pause automatically or manually when error budget or correctness gates fail.

## 14. Phase 10 — Scale only after measurement

Potential additions, in evidence-driven order:

1. CDN and S3 derivatives for public assets;
2. short-lived versioned public-store cache with stampede protection;
3. Redis for measured hot reads/distributed throttling;
4. SQS plus DLQs and separately scaled worker deployments for email, analytics, fulfillment, AutoDM and media processing;
5. query/index improvements and then read replicas where stale-read semantics are acceptable;
6. analytical storage/pre-aggregation after OLTP/reporting contention is measured;
7. extract a service only when independent scale, failure isolation, ownership or deployment cadence pays for the distributed-system cost;
8. add a warm second region only after one-region restore/failover works and the business defines regional RTO/RPO, data ownership and write-conflict policy.

Do not introduce Kafka because “analytics needs a queue.” SQS or a PostgreSQL outbox is the simpler first step. Do not introduce microservices because Kubernetes exists. Do not introduce active-active regional writes without a conflict and financial-correctness model.

## 15. Parallel team structure

These are role boundaries, not named people:

| Workstream | Primary scope | Can begin | Main dependency |
|---|---|---:|---|
| Identity & Security | SEC-001, ID-001, AUTH-001, threat model | Phase 0 | shared auth/ownership contract |
| Commerce & Data | DATA-001, PAY-001, BOOK-001, ledger | Phase 0 | migration/test foundation |
| Provider & Jobs | DM-001, email, workers, replay/DLQ | Phase 0 | transactional inbox/outbox contract |
| Frontend & Product | FE-001, PROD-001, STORE-001, UX-001 | Phase 0 | integrated branch and stable APIs |
| Media | MEDIA-001 and delivery pipeline | Phase 1 | object-storage/API contract |
| Quality Engineering | test harnesses, E2E, contracts, devices | Phase 0 | stable golden-journey definitions |
| Platform & Release | BASE-002/003, REL/INFRA/CD/ENV | Phase 0 | release manifest contract |
| SRE & Data Reliability | OBS/SRE/DR/PERF/RES | Phase 1 | deployable telemetry-enabled build |
| Product/Legal/Support | policies, pricing, refunds, launch support | Phase 0 | business decisions and provider rules |

Each workstream may develop concurrently, but it may not bypass the phase release gates.

## 16. First four delivery increments

This is the recommended work to start now.

### Increment 1 — Trust boundaries and test foundation

- SEC-001 tenant ownership and PII projection;
- DATA-001 Flyway/Liquibase baseline;
- Testcontainers PostgreSQL harness;
- BASE-002 combined release manifest and frontend integration branch;
- decide renew/destroy current expired test stack.

Exit: cross-tenant tests pass, migrations own the schema and one integrated source candidate builds.

### Increment 2 — Durable state changes

- PAY-001 webhook inbox/state machine/fulfillment;
- BOOK-001 atomic reservation;
- DM-001 inbox/outbox and automation-ID fix;
- ID-001 identity cutover plan and stable secrets;
- contract tests for these APIs.

Exit: duplicates, retries, partial failures and concurrent requests produce deterministic state.

### Increment 3 — Complete non-money vertical slice

- AUTH-001 test email delivery and browser auth journey;
- PROD-001 type-specific creator editor;
- MEDIA-001 object-store path;
- STORE-001 preview/publish/public view;
- UX-001 remove fake/no-op behavior;
- Playwright golden journey and accessibility baseline.

Exit: a new synthetic creator can sign up, create and publish a media-rich promotion/product, and an anonymous user can view it on supported devices.

### Increment 4 — Repeatable release and operations

- REL-001 build-once provenance/signing;
- INFRA-001 exact reviewed plan;
- CD-001 protected automated test deploy and rollback;
- OBS-001 telemetry and accurate health;
- SRE-001 first SLOs, synthetics and alert delivery;
- DR-001 first restore drill.

Exit: GitHub can promote the exact candidate to test, verify it, identify it, alert on failure and restore/rollback it without copied credentials.

Only after these increments should the team prioritize the full sandbox commerce, AutoDM certification and production-shaped regional platform.

## 17. Explicitly deferred work

Do not start these as near-term feature projects:

- splitting the backend into multiple repositories/microservices;
- Kafka or a service mesh;
- three-region active-active production;
- real customer data on the HTTP/single-node test stack;
- live payment collection before fulfillment/reconciliation/refund correctness;
- live Instagram AutoDM before OAuth, provider review, atomic delivery and abuse controls;
- AI recommendations, marketplace discovery or advanced personalization;
- sophisticated data warehouse/ML pipelines before event quality and business metrics are trustworthy.

## 18. Release decision states

Use one of these explicit verdicts for every candidate:

- **BLOCKED** — artifact/environment identity or required evidence is missing.
- **TEST_ONLY** — synthetic testing is allowed; real customers/providers/money are prohibited.
- **PREPROD_READY** — production-shaped sandbox testing and failure drills are allowed.
- **LIMITED_BETA_READY** — a bounded customer cohort is allowed with kill switches/on-call.
- **PRODUCTION_READY** — launch gates, SLOs, security, recovery and operational ownership all pass.

The current system remains **TEST_ONLY** until the Phase 1 correctness/security gate and the minimum TLS/identity/data conditions are satisfied. A green health endpoint or successful Kubernetes rollout cannot raise that verdict by itself.
