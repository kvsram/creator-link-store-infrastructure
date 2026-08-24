# Feature parity and testing scope

This matrix compares the two user-supplied Stan walkthrough documents with the code in these three repositories. The documents explicitly record observable UI/navigation and client-visible paths, not response bodies, private business logic, proprietary code, or the real Stan schema. Therefore the realistic target is equivalent creator-store workflows under **our** documented API contract—not identical private responses.

## Status legend

- **E2E** — UI, API, and persistence/provider safety path work and are locally testable.
- **Partial** — useful behavior exists, but the referenced workflow is incomplete.
- **Boundary** — route, UI section, or schema foundation exists; primary workflow is not implemented.
- **Missing** — not implemented.
- **Human/provider** — requires a real external account, OAuth/identity step, or real-world verification and cannot be proven by the default local stack.

## Accounts and shell

| Reference area | Status | What this project does | Remaining work |
|---|---|---|---|
| Registration and uniqueness check | Partial | Registration, BCrypt password, login/logout, opaque httpOnly database-backed sessions, and uniqueness paths are present | email/phone verification, reset, 2FA |
| Socials/plan/start onboarding | Boundary | register response returns `/subscribe/socials` as next step | onboarding UI/state, platform subscription billing, trial lifecycle |
| Post-login user/experiment calls | Partial | observed path aliases return deterministic project responses | authentication and real experiment allocation |
| Admin navigation | Partial | Home, My Store, Success, Income, Analytics, Customers, Community, More, Settings render | dedicated AutoDM page and optional-module nav activation |
| Authorization | E2E for creator APIs | `/api/v1/**` resolves the creator from the authenticated session; promotion mutations also enforce ownership | add role/admin model, audit log, rate limits, and security penetration coverage |

## Store and products

| Reference area | Status | What this project does | Remaining work |
|---|---|---|---|
| Store list and mobile preview | E2E | persisted products and promotions load; published items render in preview/public store | product-specific edit/reorder controls and drag-and-drop interaction |
| Create/manage product | Partial | all eight reference types persist; creator can edit, draft/publish, pin/unpin, and safely delete when no commerce history exists | per-type validation/editors, optimistic concurrency, archive workflow |
| Public storefront | E2E | public handles load scheduled published products/promotions; affiliate cards disclose outbound behavior and record validated clicks | custom domains, SEO, caching/CDN, accessibility/E2E coverage |
| Promotion / URL-media link | E2E | creator can draft/publish/edit/delete/reorder/schedule a promotion with brand, image, CTA, offer, coupon, disclosure and HTTPS destination | file upload, geotargeting, provider conversion/postback attribution |
| Landing pages | E2E | persisted headline, introduction, product/link visibility, and phone preview | private slug routing and arbitrary section blocks |
| Themes/colors/fonts | E2E | allowlisted persisted theme, accent, background, button and typography settings | asset uploads and more templates |
| Lead magnet fulfillment | Partial | conditional editor supports free lead capture plus upload/redirect delivery configuration | customer form renderer, consent, confirmation email |
| Digital download | Partial | conditional editor supports upload/HTTPS redirect; owned local file metadata persists | cloud object storage, malware scan, signed download fulfillment |
| Coaching call | Partial | conditional availability editor persists provider, timezone, duration, notice, buffer, capacity, and schedule text | slot generation, calendar OAuth/conflict synchronization |
| Custom fulfillment | Partial | conditional editor persists turnaround, buyer instructions, and delivery format | order work queue and customer fulfillment delivery UI |
| eCourse | Partial | module/lesson/video URL editor, drip metadata, and lesson/supporting file upload persist | learner UI, streaming/transcoding, module publishing and progress APIs |
| Membership | Partial | recurring interval and benefits editor persist | provider subscription lifecycle, cancellation and entitlement enforcement |
| Webinar | Partial | location, start, duration, and capacity editor persist | provider event creation, multiple slots, attendee UI and reminders |
| Community | Partial | benefits/welcome editor and community-style admin page exist | protected posts, categories, moderation and member entitlement enforcement |
| Product payment plans | Boundary | table exists | API, validation, checkout/provider support |
| Custom checkout fields | Boundary | table exists | editor, answer persistence, checkout rendering |
| Reviews/testimonials | Boundary | product review table exists | creator editor, ordering, storefront rendering |
| Confirmation email | Missing | — | templates, merge fields, transactional delivery |
| Order bumps and affiliate share | Missing | — | plan gates, eligibility, commission/ledger logic |
| Per-product email flows | Missing | — | workflow model, scheduler/queue, unsubscribe/compliance |

## Business sections

| Reference area | Status | What this project does | Remaining work |
|---|---|---|---|
| Home/dashboard | E2E | store readiness checklist and persisted metrics | date trends, richer setup actions |
| Income | Partial | paid-order totals, fee/net summary, recent orders, INR display | date filters, real CSV export, cashout ledger/action, refunds/disputes/reconciliation |
| Analytics | Partial | visits/leads/orders/revenue, sources, and per-promotion validated click counts/referrer groups | date filters, unique sessions, durable event pipeline, merchant conversion postbacks |
| Customers | Partial | list and manual add with 5,000 result cap | enforce account cap on writes, first/last name, search/filter, CSV import, purchases/spend/subscription/tags |
| Success | E2E for demo | deterministic tutorial hub | CMS/video hosting and Stan-specific course content are out of scope |
| AutoDM metadata/analytics | Partial | observed metadata/analytics paths, schema, safe Instagram config/webhook/test-send boundary | automation CRUD/editor, keyword/post matching, queue, publish state machine, metrics updates |
| Funnels | Boundary | base tables and summary API | editor, step validation, visitor state, post-purchase routing |
| Appointments | Boundary | schedule/booking base tables and summary API | calendar/list UI, slot creation, booking/cancel/reschedule |
| Referrals | Missing | card only | referral codes, attribution, commission ledger and payout policy |
| Email flows | Missing | card only | plan gate, sequence editor, scheduler, deliverability/compliance |

## Settings and integrations

| Reference area | Status | What this project does | Remaining work |
|---|---|---|---|
| Profile | Partial | data loads into the form | authenticated save, username collision/change policy, avatar upload |
| Integrations list | Partial | disconnected integrations seed/load; Instagram safe status | OAuth flows and encrypted token lifecycle for each provider |
| Creator SaaS billing | Missing | — | plan, trial, invoices, feature gates; keep separate from store orders |
| Store payment settings | Partial | safe provider readiness, Razorpay-first/Stripe strategy, signed callbacks | creator onboarding, settlement identity, refunds/disputes, reconciliation |
| Razorpay/Stripe execution | Human/provider | test/live adapters can create provider sessions only when explicitly configured | sandbox credential test evidence; production compliance/onboarding |
| Email notifications | Boundary | preferences table and settings tab | save API, event delivery, templates, retries |
| Security/session management | Missing — P0 | BCrypt registration password only | login/session/JWT, 2FA, active sessions, revocation, audit, account deletion workflow |
| Instagram | Human/provider | signed webhook verification/deduplication and allowlisted test send | Meta app review/OAuth, durable job/automation processing, rate-limit handling |
| Google Calendar/Zoom/Zapier | Boundary | provider rows only | OAuth, token refresh, provider APIs/webhooks |

## API path compatibility

The following observed paths are intentionally available in this project with **project-defined** responses:

- `OPTIONS/POST /api/v1/authentication/check-unique-taken`
- `GET /api/v1/users/get_user`
- `POST /api/v1/users/experiments/join_communities`
- `GET /api/v1/users/experiments/community_stats`
- `GET /api/v1/users/experiments/metadata`
- `GET /api/v1/integrations`
- `PUT /api/v1/experiments/variant-assignment`
- `PUT /api/v1/tags`
- `GET /api/v1/automations/instagram-posts-metadata`
- `GET /api/v1/automations/analytics?automation_ids=...`
- `POST /events`

Matching a path and method is not proof of a matching Stan body, error model, authorization behavior, rate limit, or side effect. The exact supported bodies are described in `api-contract.md` and backend tests.

## What `make smoke` proves

On the running local Compose stack it proves:

- backend health;
- web SPA delivery;
- deterministic public `alex` store backed by PostgreSQL;
- dashboard contract;
- INR store currency;
- explicit real-money and external-service markers;
- payments and Instagram default to disabled;
- a disabled checkout returns HTTP 503 and does not attempt a charge.

It does not prove login/security, every advanced editor, provider sandbox behavior, performance, AWS readiness, regional failover, or private Stan response parity.

## Launch blockers

Before exposing the app to real users, at minimum close the P0 authorization/security gap; introduce migrations and production data lifecycle; finish verified-webhook-to-order/fulfillment/ledger behavior; add validation/rate limits/auditability; implement the actual product workflows being marketed; add frontend and browser tests; and complete the AWS readiness gates in `AWS_REGIONAL_BOOTSTRAP.md`.
