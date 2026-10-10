# Architecture and delivery maturity model

Large companies do not share one private implementation standard. Compare observable engineering capabilities using public frameworks such as the AWS and Azure Well-Architected Frameworks, NIST SSDF, SLSA, OWASP ASVS/API Security, WCAG and DORA delivery metrics.

Primary references:

- AWS Well-Architected pillars: <https://docs.aws.amazon.com/wellarchitected/latest/framework/the-pillars-of-the-framework.html>
- Azure Well-Architected Framework: <https://learn.microsoft.com/azure/architecture/framework/>
- NIST SSDF SP 800-218: <https://csrc.nist.gov/pubs/sp/800/218/final>
- SLSA specification: <https://slsa.dev/spec/>
- OWASP ASVS: <https://owasp.org/www-project-application-security-verification-standard/>
- OWASP API Security: <https://owasp.org/www-project-api-security/>
- WCAG 2.2: <https://www.w3.org/TR/WCAG22/>
- DORA capabilities and metrics: <https://dora.dev/>

## Current maturity assessment

| Area | Current shape | Mature target |
|---|---|---|
| Architecture | modular monolith with clear layers and provider seams | keep until measured ownership, scale or failure-isolation need justifies extraction |
| Distribution | browser + frontend + API + PostgreSQL over a network | multi-AZ stateless compute and managed data recovery for production |
| CI | useful build/test/quality workflows and immutable release intent | required PR gates, broader E2E/security/performance tests, reproducibility, provenance and policy enforcement |
| CD | infra-first design, exact SHA/digest inputs, manual promotion and verifier | protected environments, artifact promotion, migration gate, canary analysis, automatic safe rollback and deployment telemetry |
| Security | session ownership checks, edge limits and disabled providers | threat model, Spring Security policy, verification/reset/MFA option, centralized rate limiting, SAST/DAST/dependency/container/IaC gates and incident response |
| Data | PostgreSQL authoritative writer and parameterized repositories | managed migrations, pool limits, PITR/backups, restore drills, audit/retention, object storage and tested RPO/RTO |
| Operations | health checks, deployment scripts and partial dashboard/alarm scaffolding | SLOs, structured telemetry, paging, runbooks, synthetic checks, capacity forecast and game days |
| Resilience | restartable containers on a cheap test node | multi-AZ service, failure isolation, graceful degradation, tested rollback/restore and regional strategy tied to business need |

The current CI/CD has the **shape** of mature delivery—separate IaC and application releases, immutable identifiers, manual promotion, verification—but not yet the evidence depth or automated safeguards of a large production platform.

## Microservices decision

Do not split merely to look distributed. Keep the modular monolith while one team owns the product, transactions cross domains, deployment cadence is shared, and one service can meet SLO/capacity goals.

Consider extraction only when at least one condition is measured:

- a domain needs independent scaling that materially reduces cost or contention;
- a failure must be isolated from storefront/login/checkout;
- a separate team owns its data and release lifecycle;
- its availability or security boundary differs materially;
- the monolith cannot meet deployment or recovery objectives despite modular correction.

Likely future candidates, in order of evidence rather than fashion:

1. analytics/click ingestion and rollups;
2. notification/email/Instagram job processing;
3. media upload/scan/transcode/delivery;
4. payment webhook processing and ledger only after its consistency model is mature.

Each extraction adds network failures, schema/version compatibility, tracing, deployment, secrets and on-call cost. Define ownership, API/event contract, idempotency, retry/dead-letter, data authority and rollback before extraction.

## Scale evolution

### Low scale now

- one authoritative PostgreSQL writer;
- stateless frontend/API containers;
- bounded database connection pool;
- database outbox/job table for a small volume of asynchronous work;
- object storage for files;
- measurement before adding caches or brokers.

### Read-heavy popular storefronts

1. put static assets behind a CDN;
2. add cache validators and short-lived public-store cache with explicit invalidation/versioning;
3. scale stateless API replicas horizontally;
4. tune queries/indexes and pool limits from traces;
5. add a read replica only when measured database reads justify it and stale-read semantics are acceptable.

### Write-heavy analytics/webhooks

1. keep the customer response path independent of best-effort analytics;
2. accept a validated idempotent event quickly;
3. persist via an outbox/durable queue;
4. batch consumers and apply backpressure;
5. monitor queue age, retries and dead letters;
6. partition/aggregate only after volume and retention require it.

Use a managed queue such as SQS before operating Kafka unless ordering, replay, throughput and team capability clearly justify Kafka.

### High availability

- load balancer/ingress across multiple nodes and Availability Zones;
- at least two stateless replicas with disruption budgets and topology spread;
- Multi-AZ database, backups/PITR and restore drills;
- externalized sessions or session store compatible with horizontal replicas;
- object storage rather than node-local files;
- independent synthetics, paging and rehearsed rollback.

Multi-region is a later business decision. Define RTO/RPO, data-write authority, failover procedure and consistency trade-offs before buying duplicate infrastructure.

## Alternate request channels

An influencer may act through the web dashboard, mobile browser, future mobile app, CSV import, public API, Instagram webhook, scheduled job or support/admin workflow. Treat each as an adapter to the same validated use case:

```text
channel adapter -> authenticated/verified command -> service policy -> transaction/outbox -> side effect
```

Every channel needs actor identity, tenant boundary, schema/version, idempotency key, rate limit, audit context and consistent error/result semantics. Do not duplicate business logic in controllers, webhook handlers or queue consumers.

## Recommended order of investment

1. correctness/security: TLS, identity delivery, session/CSRF policy, migrations, tenant tests;
2. repeatability: browser E2E, contract tests, exact release manifest, protected gates;
3. operations: SLOs, telemetry, paging, backup/restore and rollback drills;
4. production data paths: object storage, email, payment ledger/fulfillment, provider sandbox evidence;
5. capacity: baseline/load/soak tests and measured scaling;
6. HA/multi-region and selective service extraction only when business requirements justify them.

