# End-to-end test matrix

Select a subset based on the declared stage and authorization. Record omitted rows as deliberately out of scope or blocked.

## Environments

| Environment | Appropriate evidence | Never infer |
|---|---|---|
| Local Compose | deterministic feature/API/database checks, schema bootstrap, failure injection | cloud networking, managed-service behavior, public security |
| Disposable AWS test | deployment topology, same-origin routing, basic public accessibility, synthetic journeys | HA, TLS security, production capacity, disaster recovery |
| Dev/staging | provider sandbox, browser E2E, DAST, load baseline, migrations, rollback | production customer behavior |
| Preprod | production-shaped canary, restore, soak, capacity and failure drills | unlimited scale or permanent readiness |
| Production | low-risk synthetics, SLOs, alert and rollout evidence | permission for intrusive scanning or load testing |

## Core journeys

### Visitor and identity

- landing page, pricing, legal/support/navigation, SEO metadata and not-found;
- signup validation, reserved/duplicate public store address, verification and resend;
- login by handle/email, logout, password reset, session restore/expiry/revocation;
- brute-force/account lockout behavior, CSRF policy, cookie flags, concurrent sessions;
- plan and entitlement boundaries without trusting frontend flags.

### Creator

- profile and public address update, collision, stale-link policy, preview consistency;
- store design, landing copy, visibility, reordering, pin/unpin and draft behavior;
- create/edit/reload/publish/unpublish/archive/delete for every product type;
- file upload/remove/readiness and private/public configuration separation;
- customers, analytics, income, settings, integrations, notifications and logout;
- empty, loading, partial, error, stale-session and retry states.

### Buyer/audience

- public storefront, pinned ordering, product detail, promotion click and redirect safety;
- lead capture consent and idempotency;
- checkout amount/currency derivation, duplicate submission and provider cancel/failure;
- webhook signature, replay, out-of-order events and authoritative paid state;
- delivery/booking/course/webinar/membership/community entitlement where implemented.

### Instagram and outbound messaging

- signed webhook, deduplication, rule match, queue/job creation, retry/dead-letter;
- OAuth/token lifecycle, consent, unsubscribe/revocation and audit record;
- provider rate limits and private-reply window;
- no live send unless the recipient, provider mode, entitlement and test scope are explicitly approved.

## Device and browser grid

Use real devices for at least the launch-critical cells; emulation is supplementary.

| Class | Minimum coverage |
|---|---|
| Small iPhone | current Safari, portrait/landscape, touch, text zoom |
| Large iPhone | current Safari, safe areas, keyboard/open modal behavior |
| Android phone | current Chrome, back button, low-memory reload, file picker |
| Tablet | iPad Safari or Android Chrome, portrait/landscape, split width |
| Desktop | current Chrome, Edge, Firefox and Safari where supported |
| Assistive | keyboard-only, visible focus, screen reader smoke, 200%/400% zoom, reduced motion, contrast |

For each critical journey collect viewport/device, browser/version, URL, release identity, expected result, observed result, screenshot or trace, console errors, failed network calls and cleanup result.

## Network and dependency conditions

- high latency, slow 3G, intermittent disconnect, offline submit and reconnect;
- API 400/401/403/404/409/422/429/500/503 and timeout;
- browser refresh/back/duplicate tab/double click;
- database connection exhaustion and slow query in an authorized stage;
- payment/email/Instagram timeout, 429, invalid signature and duplicate callback;
- pod/process restart during safe idempotent operations;
- stale frontend against newer backend and vice versa during rollout.

## Security coverage

- horizontal and vertical authorization with two synthetic creators;
- mass assignment, IDOR/BOLA, SQL/command/template injection, stored/reflected XSS;
- URL allowlist/open redirect/SSRF, CORS, CSRF, session fixation and cookie policy;
- upload type/size/path/ownership, malware workflow and signed download authorization;
- secrets in repository, image, frontend bundle, logs, errors and CI output;
- rate limits by IP and account, spoofed forwarding headers and resource exhaustion;
- dependency/container/IaC/SAST scans plus manual business-logic abuse review;
- privacy inventory, retention/deletion/export/consent and log redaction.

Active exploit tests require written target scope and stopping conditions.

## Performance and resilience profiles

Define SLOs before load. At minimum record throughput, error rate, p50/p95/p99 latency, CPU, memory, pod restarts, database CPU/connections/locks/IO, connection-pool wait, queue depth/age and cost.

1. single-user trace for correctness and query count;
2. baseline at expected normal concurrency;
3. ramp to declared launch peak;
4. short spike above peak;
5. soak at sustainable load;
6. hotspot: one popular influencer plus many small stores;
7. write burst: analytics/click/lead/webhook ingestion;
8. dependency degradation and recovery;
9. rollback/restore drill.

Run load only in an authorized environment with synthetic data, capped duration/concurrency/cost, abort thresholds and cleanup. A public URL is not permission to load test.

## Release-quality gates

- reproducible clean build and tests;
- exact immutable artifacts promoted, not rebuilt;
- additive/backward-compatible migration and rollback window;
- critical browser journeys automated and passing;
- no open P0/P1 security or tenant-isolation defect;
- SLO and capacity target met with headroom;
- alerts reach a human and link a usable runbook;
- backup restore and application rollback demonstrated;
- external provider remains disabled unless its sandbox/live gate is separately approved.

