# Creator Store project baseline

Snapshot: **2026-10-10**. This is routing context, not permanent truth. Reverify before every audit.

## Canonical release under test

| Component | Repository branch | Commit |
|---|---|---|
| Backend | `kvsram/creator-link-store-backend:test` | `3a1ae4286a66e531333d6ee512d34821870144c1` |
| Frontend | `kvsram/creator-link-store-frontend:test` | `6eee4556f0dc02f6ad2dafe5758d5a4e646f8461` |
| Infrastructure manifest | `kvsram/creator-link-store-infrastructure:test` | `1cd0b072905e5ee155e25e9575a32e1f2d5a0c5e` |
| Applied infrastructure | SSM/tag release marker | `d130d37d64c7ea413cd60a56fb7716a1335d1f62` |

| Release evidence field | Snapshot value |
|---|---|
| Backend image digest | `sha256:1a0c2f4d720199a48c22885c4ff4f9898740b5394785bb58a479d2624dc7535e` |
| Frontend image digest | `sha256:16a25daf02c9e1d562b278d13906215786a7a743cf16ba91390293db0d35277d` |
| Verifier date | `2026-10-10`; exact UTC completion timestamp is not recorded here |
| Database migration version | `NONE-startup-DDL`; production migration tooling is not present |
| Rollback release manifest | `UNKNOWN`; must be captured before the next deployment |
| Expiry/cleanup | historical deadline `2026-09-15T02:26:23Z` is past; stack still existed at snapshot |

The separate frontend product-detail/merchandising work is published at `codex/product-merchandising-ui` commit `6063d745e17c07fc03ebfcbb19f4a6b08563b798`; it is not part of the deployed `test` release and must not be silently treated as live.

## Verified low-cost AWS topology

```text
Public HTTP IPv4 :80
  -> one EC2 instance in us-east-2
     -> single-node K3s
        -> Nginx/React frontend
        -> Spring Boot API
  -> private Single-AZ RDS PostgreSQL
```

The deployment verifier passed the pinned image digests, local and public health, database connectivity, release markers, edge rate limiting, source-IP preservation, and spoofed-forwarded-header rejection. There is no EKS, NAT Gateway, or load balancer. This remains a disposable synthetic-data test environment, not production.

Public origin at this snapshot: `http://77.112.61.68`.

The historical teardown/expiry marker is already past. Treat that as an operational and budget-control defect until corrected or the stack is destroyed.

## Architecture classification

- React/Vite SPA served by Nginx.
- One Spring Boot deployable organized as controllers -> services -> JDBC repositories -> PostgreSQL.
- Opaque database-backed web sessions.
- Provider strategy boundaries for payments and Instagram; live modes disabled by default.
- PostgreSQL-backed jobs exist for parts of AutoDM; there is no general message broker/cache tier.
- This is a **modular monolith**, which is an appropriate current application architecture.
- The runtime is network-distributed across browser, edge/frontend, API and database, but it is **not a fault-tolerant distributed service platform**: one region, one K3s node, one API replica in the test release, and a Single-AZ database.

## Known evidence and gaps

Verified or present:

- separate application and infrastructure repositories;
- immutable SHA-tagged images and pinned release verification;
- Terraform/Kustomize, infrastructure-first release model and manual application promotion;
- layered backend, PostgreSQL persistence, public storefront and dashboard routes;
- unit/integration/build/smoke foundations and AWS topology verification;
- safe disabled boundaries for Razorpay/Stripe and Instagram.

Not production-complete:

- HTTP only: no domain, TLS, secure-cookie production proof, CDN/WAF or managed edge;
- new Identity-v1 signup cannot complete because transactional verification email is not wired;
- current tag/user routes have audited cross-tenant authorization/PII risks that require session-derived ownership and negative two-tenant tests;
- payment webhooks mark checkout state but do not invoke the existing order/entitlement fulfillment service, and webhook inbox/state transitions are not atomic;
- Instagram deduplication can be persisted before enqueue and transient failures can be acknowledged, creating a verified event-loss window;
- no full automated browser suite across identity, eight product types and buyer journeys;
- product-merchandising UI branch not integrated with deployed identity branch;
- no Flyway/Liquibase migration lifecycle and restore drill evidence;
- local/application file storage is not production object storage with scan and signed delivery;
- payment ledger, refunds/disputes/reconciliation and buyer fulfillment are incomplete;
- Instagram requires Meta approval, creator OAuth, token lifecycle and controlled live evidence;
- observability, alert delivery, SLOs, canary analysis, automatic rollback and DR drills are incomplete;
- single-node/single-AZ topology has expected host/AZ/database failure exposure;
- software-supply-chain signing/provenance, complete SBOM policy, DAST and performance gates need proof.

Some handoff/parity prose broadly claims session-derived ownership, while the pinned source audit found a body-controlled `creator_id` tag path and arbitrary-handle contact lookup. Treat source/runtime evidence as authoritative, record the documentation contradiction, and do not inherit the broader claim.

## Source-of-truth order

1. exact deployed cloud state, artifact digests and verifier output;
2. tests and runtime observations against that release;
3. code at the pinned commits;
4. current API contract and feature-parity documents;
5. plans, diagrams and historical handoff notes.

Never reverse this order.
