# Creator Store production-readiness and multi-LLM audit

Assessment date: **2026-10-10**

This report evaluates the exact deployed test release and the associated source repositories. It compares observable capabilities with public mature-engineering practices. It does not claim knowledge of proprietary Amazon or Microsoft internal systems.

## 1. Executive decision

**Current verdict: TEST_ONLY.**

The public AWS endpoint is deployed and passed its pinned release/topology verifier. The landing page, demo storefront and login/signup screens load, and the checked frontend builds and unit tests pass. That proves a useful synthetic-data test service, not production correctness.

The release must not accept real customers, real credentials, payments, or provider messaging yet because:

1. the endpoint is HTTP-only and the single-node/Single-AZ stack is not highly available;
2. Identity-v1 signup has no transactional verification-email delivery;
3. verified tenant-authorization holes exist in current backend routes;
4. a successful payment webhook does not invoke the implemented order/entitlement fulfillment service;
5. payment and Instagram webhook inbox/state changes are not transactionally atomic;
6. startup `schema.sql` is not a production migration system;
7. product files use application/PVC storage rather than production object storage;
8. automated browser, accessibility, security, load, restore and rollback evidence is incomplete;
9. the product-detail/photo frontend work is on a separate, older feature branch and is not in the deployed identity release;
10. the disposable infrastructure expiry is past due and no automatic teardown enforces it.

## 2. What the system actually is

```text
Visitor/creator browser
  -> public HTTP IPv4
  -> Nginx + React frontend pod
  -> one Spring Boot application pod
       -> controller -> service -> JDBC repository
       -> PostgreSQL-backed session and job state
       -> disabled-by-default payment/Instagram adapters
  -> private Single-AZ RDS PostgreSQL
```

### Classification

- **Application architecture:** layered modular monolith.
- **Deployment architecture:** distributed three-tier application because browser, web, API and database are separate networked processes.
- **Not microservices:** there is one backend binary, one shared schema, one primary deployment lifecycle and an embedded worker.
- **Not highly available:** one region, one K3s node, one API/web replica in the disposable overlay and one Single-AZ database.

This is the correct application architecture for the present stage. Kubernetes does not make a monolith a microservice system. Splitting now would add versioned network contracts, distributed transactions, more deployments, more secrets, tracing and on-call burden without fixing the current correctness defects.

## 3. Is CI/CD comparable to a mature large-company pipeline?

### What already follows the right pattern

- separate frontend, backend and infrastructure repositories;
- infrastructure-first, application-second release intent;
- GitHub Actions build/test foundations;
- SHA-tagged images and exact digest support in the K3s release script;
- AWS OIDC direction rather than permanent cloud keys in workflows;
- Terraform, Kustomize, health probes, resource requests/limits and security contexts;
- manual environment promotion and a detailed post-deployment verifier;
- concurrency controls around applies/deployments;
- ECR immutability and a remote-state/locking foundation for the regional design.

GitHub Actions is not the limitation. Large engineering organizations also use GitHub Actions or equivalent orchestrators. The difference is the quality of enforced gates and operational evidence.

### Where it lags

| Capability | Current state | Required mature behavior |
|---|---|---|
| PR governance | tests exist; live branch protection/CODEOWNERS not verified | required reviews, owners, protected branches/environments, policy checks |
| Build integrity | CI and Dockerfiles rebuild artifacts separately | build once, test that artifact, package/promote exact digest |
| Supply chain | vulnerability scans are partial; no proven SBOM/signature/provenance gate | pinned actions/base images, SBOM, SLSA-style provenance, signing and verification |
| Terraform promotion | apply workflow replans instead of applying reviewed binary plan | approve and apply the same bound, signed plan or equivalent controlled service |
| Release manifest | independent manual frontend/backend/infra inputs | one signed bill of materials binding app digests, infra SHA, config and schema |
| K3s CD | current public test release is a CloudShell/SSM operator runbook | protected GitHub workflow invoking exact-digest release and verifier |
| Deployment | some manifests apply `latest` before setting exact image | render exact digest before the first apply; never apply mutable placeholders |
| Database | startup DDL | Flyway/Liquibase migration job, compatibility window and rollback policy |
| Progressive delivery | rollout status only | 5/25/50/100 canary or equivalent with SLO/business analysis |
| Verification | topology/public smoke is strong but product E2E is incomplete | post-deploy API/browser synthetics and safe write/read verification |
| Rollback | documented/manual | previous release manifest, automated abort and proven DB-compatible rollback |
| Observability | log group/dashboard/alarm scaffolding | structured logs, metrics/traces, real synthetics, paging and runbooks |
| Recovery | backups configured differently by stage; no drill evidence | PITR restore, failover and RTO/RPO drills |
| Delivery metrics | not measured | deployment frequency, lead time, change-failure rate and recovery time |

The current pipeline has the **shape** of mature delivery but not yet the enforced controls, supply-chain assurance, progressive rollout, observability or recovery proof.

## 4. Verified application blockers

### P0/P1 correctness and security

1. **Cross-tenant tag mutation:** `TagService` trusts a request-body `creator_id` rather than deriving ownership only from the authenticated session. The current user lookup can also return another handle's email/phone. Add negative two-tenant tests to every owner API.
2. **Payment is not fulfillment:** `PaymentWebhookService` records the event and marks a checkout paid, but `OrderFulfillmentService.recordPaidOrder()` has no caller. A real paid provider event can leave no order, booking, enrollment or entitlement.
3. **Non-atomic payment inbox:** webhook-event insert and checkout transition/fulfillment are separate autocommit operations. A partial failure can make a provider retry look duplicate and skip required work.
4. **Instagram event-loss window:** the deduplication marker can be stored before job enqueue, and exceptions are swallowed into an HTTP-success path. A valid retry can then be discarded.
5. **Booking/payment race:** availability is read before a remote provider call without an atomic expiring reservation. Two buyers can attempt the same slot.
6. **Automation creation race:** insert followed by `select max(id)` can attach rules to the wrong concurrent automation. Use `INSERT ... RETURNING id`.
7. **Local per-JVM login throttling:** replicas multiply the limit and restart clears it. Preserve edge controls and add an account-aware/distributed policy before horizontal scale.
8. **Dual identity model:** legacy creator fields and normalized identity tables are still dual-read/written. Define and test a cutover rather than leaving two authorities indefinitely.

### Frontend/product blockers

At the audited commits, the deployed identity branch passed **36/36** Node tests and its production Vite build; the separate merchandising branch passed **35/35** tests and its build. These are useful helper/unit checks, not rendered component or browser evidence.

1. Deployed identity frontend and product-detail/merchandising frontend diverge from a common older commit. They must be integrated, resolved and tested as one artifact.
2. Product-photo selection is a local-preview prototype; durable media upload, object storage, scan/resize, cover ordering and safe public delivery are absent.
3. Tests are helper/unit-level; there is no React component or Playwright/Cypress browser suite.
4. Several visible buttons are no-ops or demo surfaces, including CSV export, learning, customer import/search/filter and community actions.
5. Income and analytics charts are fixed decorative shapes rather than data-driven time series, which can mislead testers/users.
6. Modals, focus restoration, error announcements and touch targets need accessibility work.
7. The shared request layer lacks explicit timeout/abort/offline/session-expiry behavior and runtime response validation.

## 5. Service health: what “running correctly” means

| Question | Current answer |
|---|---|
| Does the public endpoint respond and render the pinned frontend? | Yes, verified for the tested routes. |
| Are K3s pods and RDS connectivity healthy for the verified release? | Yes, at verification time. |
| Can synthetic users explore the landing/demo/login/signup UI? | Yes, with the documented HTTP warning. |
| Can a new Identity-v1 browser signup complete? | No; verification delivery is not wired. |
| Are all creator/product/buyer flows proven end to end? | No. |
| Are real payments safe? | No; providers remain disabled and fulfillment/atomicity have blockers. |
| Is AutoDM ready for real Instagram users? | No; provider approval/OAuth plus event atomicity and operations remain. |
| Is it production-ready or highly available? | No. |
| Is the modular monolith itself a problem? | No; it is the right shape until measured needs justify extraction. |

“Healthy” means the verified process/routes are available. “Correct” requires journey, data, security and failure evidence. “Production-ready” additionally requires capacity, recovery, operations and compliance gates.

## 6. What happens when load increases

### Viral read-heavy storefront

Current public-store requests query the primary transactional database repeatedly and have no CDN/application cache contract. The progression should be:

1. measure endpoint latency, query count, database CPU/IO and connection-pool wait;
2. put static assets/media behind CDN/object storage;
3. add ETag/Cache-Control and a short-lived public-store cache with explicit version/invalidation on publish;
4. horizontally scale stateless API/web replicas behind a load balancer;
5. fix indexes/queries and prevent hot-key cache stampedes;
6. add read replicas only if measured reads justify them and stale-read semantics are acceptable.

### Analytics/click write burst

Views and clicks currently share the same PostgreSQL and connection pool as login/commerce. Under a burst they can harm critical traffic. The progression should be:

1. validate and durably enqueue best-effort analytics without blocking storefront rendering;
2. use an outbox/managed queue and idempotent consumers;
3. micro-batch writes and maintain hourly/daily aggregates;
4. monitor queue age, retry/dead-letter depth and data-loss/replay behavior;
5. move analytical retention/query load away from the OLTP writer when volume requires it.

Use SQS plus a DLQ—or a strengthened PostgreSQL outbox at very low scale—before operating Kafka. A queue is for work allowed to finish later; storefront reads and login should remain synchronous.

### Slow provider work

Email, AutoDM, media processing and fulfillment side effects need durable jobs, retry/backoff, idempotency and dead-letter operations. Split workers into separate deployments before creating separate repositories/services.

## 7. Components to add, in order

### Make the current test trustworthy

1. fix tenant authorization, payment/Instagram inbox atomicity and paid fulfillment;
2. integrate the product-detail branch with Identity-v1;
3. add PostgreSQL/Testcontainers concurrency and webhook E2E tests;
4. implement verification email in SES sandbox or an operator-only test-delivery harness;
5. enable TLS before real credentials;
6. adopt Flyway/Liquibase and a separate migration step;
7. move media to S3-compatible object storage with scan/signed delivery;
8. add structured logs, metrics, request correlation and accurate readiness;
9. correct/destroy the expired disposable stack.

### One-region production baseline

- load balancer/managed ingress, domain, ACM/TLS and appropriate WAF/rate limits;
- at least two worker nodes across AZs and two stateless replicas;
- Multi-AZ RDS, PITR, restore drill and pool/connection budget;
- object storage, external secrets and least-privilege identities;
- Metrics Server/node autoscaling where Kubernetes HPA is used;
- topology spread/PDBs, working NetworkPolicy, synthetics, paging and runbooks;
- protected GitHub environments, exact-plan apply, signed release manifest and progressive rollout.

### Later, only from measurements

- Redis/public-store cache for hot reads and distributed throttling;
- SQS/outbox consumers for analytics, email, AutoDM and fulfillment;
- analytics store/preaggregates;
- selective process/service extraction;
- warm second region after rollback, restore and regional-failure drills work in one region.

## 8. Multi-LLM test organization

The reusable skill is under `skills/creator-store-deep-audit/`.

- `SKILL.md`: orchestration and verdict rules;
- `references/agent-prompts.md`: six paste-ready specialist prompts plus coordinator;
- `references/test-matrix.md`: journey, device, security, load and resilience coverage;
- `references/report-contract.md`: evidence and severity schema;
- `references/project-baseline.md`: dated release/topology context;
- `references/maturity-model.md`: architecture and scale decision rules.

Six independent lanes are deliberately separated so one model's assumptions do not contaminate the others:

1. functional/API/database integrity;
2. frontend/device/accessibility;
3. security/privacy/abuse;
4. performance/resilience/distributed systems;
5. CI/CD/IaC/supply-chain/operations;
6. product completeness/integrations.

Run the coordinator only after all six reports use the same exact release manifest. Do not ask all six models “is it good?”; give each a falsifiable lane, common evidence contract and prohibited actions.

## 9. 30/60/90-day plan

### First 30 days: correctness and repeatability

- close tenant/payment/Instagram P0s;
- integrate frontend branches;
- add migrations, transactional email test path and browser E2E identity/store suite;
- remove or clearly label no-op/decorative UI;
- automate exact-digest K3s deployment plus verifier from a protected workflow;
- fix the expired-stack lifecycle.

### Days 31-60: production-shaped single region

- TLS/domain/managed edge, object storage and secrets integration;
- Multi-AZ data plan and tested restore;
- logs/metrics/traces, SLOs, paging and runbooks;
- build-once/SBOM/provenance/signing and exact release manifest;
- payment/Instagram/email sandbox tests with providers still non-live.

### Days 61-90: capacity and progressive delivery

- baseline/ramp/spike/soak tests against declared launch assumptions;
- canary analysis and automatic abort/rollback;
- queue/outbox for measured asynchronous pressure;
- node/pod/database capacity validation and failure drills;
- independent six-lane retest and coordinator verdict.

## 10. Release gate

Do not promote beyond synthetic testing until all P0/P1 findings have deterministic acceptance tests, the exact combined release passes the six audit lanes, and rollback/restore/alert delivery are demonstrated. “Microservices” and “multi-region” are not acceptance criteria; customer correctness, security, SLOs and recoverability are.
