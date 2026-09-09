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
| Registration and uniqueness check | Partial | Public marketing page, three-step plan/details/review UI, availability check, normalized registration, BCrypt password, login/logout, opaque httpOnly database-backed sessions, and reserved-route protection are present | email/phone verification, reset, 2FA, automated browser submission test |
| Socials/plan/start onboarding | Boundary | Starter/Creator Pro selection and safe billing explanation lead into account creation and `/dashboard/` | persisted onboarding state, creator subscription checkout, verified entitlement, trial lifecycle |
| Post-login user/experiment calls | Partial | observed path aliases return deterministic project responses | authentication and real experiment allocation |
| Admin navigation | Partial | Home, My Store, Success, Income, Analytics, Customers, Community, More, Settings render | dedicated AutoDM page and optional-module nav activation |
| Authorization | E2E for creator APIs | `/api/v1/**` resolves the creator from the authenticated session; promotion mutations also enforce ownership; AWS K3s edge has per-IP request/connection limits | add account-aware lockout, role/admin model, audit log, production distributed-edge protection, and security penetration coverage |

## Store and products

| Reference area | Status | What this project does | Remaining work |
|---|---|---|---|
| Store list and mobile preview | E2E | persisted products and promotions load; published items render in the workspace phone preview and public store | drag-and-drop ordering and broader accessibility coverage |
| Create/manage product | Partial | the verified aggregate authoring slice covers all eight types, existing-item hydration, normalized projections, draft/publish gates, staged files, pin/unpin, and safe deletion | optimistic concurrency, archive workflow, and the buyer/runtime flows listed below |
| Public storefront | Partial | public handles and product details render type-specific, allowlisted `public_configuration`; the PostgreSQL/HTTP smoke test asserts that private authoring values are excluded | custom domains, SEO, caching/CDN, and full accessibility automation |
| Promotion / URL-media link | E2E | creator can draft/publish/edit/delete/reorder/schedule a promotion with brand, image, CTA, offer, coupon, disclosure and HTTPS destination | file upload, geotargeting, provider conversion/postback attribution |
| Landing pages | E2E | persisted headline, introduction, product/link visibility, and phone preview | private slug routing and arbitrary section blocks |
| Themes/colors/fonts | E2E | allowlisted persisted theme, accent, background, button and typography settings | asset uploads and more templates |
| Lead magnet fulfillment | Partial | creator-side capture policy plus public email/name/phone/consent submission, durable idempotent lead persistence, consent-text snapshot, tenant validation, and safe public projection are implemented | confirmation email, malware-scanned object storage, and gated signed delivery |
| Digital download | Partial | verified creator-side upload/HTTPS redirect configuration, owned file metadata, staged publication, and safe public projection | cloud object storage, malware scan, entitlement check, and signed delivery |
| Coaching call | Partial | verified creator-side location, timezone, duration, notice, buffer, capacity, dated availability, and normalized slot projection | recurring slot generation, buyer booking flow, and calendar OAuth/conflict synchronization |
| Custom fulfillment | Partial | creator-side turnaround, private buyer instructions, and delivery format exist | order work queue and customer fulfillment delivery UI |
| eCourse | Partial | verified creator-side module/lesson/video metadata, drip settings, assets, and normalized module/lesson projection | learner portal, streaming/transcoding, module publication, and progress APIs |
| Membership | Partial | verified creator-side multi-plan interval/benefit configuration and normalized payment-plan projection | provider subscription lifecycle, cancellation, billing webhooks, and entitlement enforcement |
| Webinar | Partial | verified creator-side location, timezone, multiple dated sessions, private join URLs, capacity, and normalized session projection | provider event creation, buyer registration, attendee UI, and reminders |
| Community | Partial | verified creator-side platform, benefits, private access/welcome configuration, and safe public summary | protected posts, categories, moderation, buyer/member portal, and entitlement enforcement |
| Product payment plans | Partial | membership plans are authored, validated, normalized, reloaded, and presented as safe public choices | recurring checkout/provider lifecycle and subscription management |
| Custom checkout fields | Partial | fulfillment questions are authored, normalized, reloaded, rendered publicly, and validated against the owning product | order-response UI and complete fulfillment lifecycle |
| Reviews/testimonials | Boundary | product review table exists | creator editor, ordering, storefront rendering |
| Confirmation email | Missing | — | templates, merge fields, transactional delivery |
| Order bumps and affiliate share | Missing | — | plan gates, eligibility, commission/ledger logic |
| Per-product email flows | Missing | — | workflow model, scheduler/queue, unsubscribe/compliance |

### Verified product-type authoring contract

The latest repository suites pass 54 backend tests and 25 frontend tests plus a production frontend build. The backend total includes real MockMvc/H2 registration-session and public-interaction integration tests. The earlier creator-authoring slice also passed a real PostgreSQL/HTTP smoke run for all eight types and an API restart persistence check. Current manual browser checks cover the marketing, signup, login, storefront, not-found, dashboard, and billing-boundary routes. This proves authoring, public lead persistence, best-effort view tracking, stable HTTP-test-stage request IDs, and safe presentation—not email/file delivery, the other buyer fulfillment flows, React component coverage, or automated browser regression coverage.

- `POST /api/v1/products` creates the common product and schema-versioned type configuration as one aggregate. `PATCH /api/v1/products/{id}` updates that aggregate, but the product `type` is immutable after creation.
- `GET /api/v1/products/{id}/configuration` returns the authenticated creator view: common authoring fields, parsed `configuration`, owned file metadata, and applicable normalized projections (`meeting_slots`, `webinar_sessions`, `payment_plans`, `checkout_fields`, and `course_modules`).
- Uploads remain multipart at `POST /api/v1/products/{id}/files`; an owner can remove an unused file with `DELETE /api/v1/products/{productId}/files/{fileId}`.
- A download or lead magnet that uses uploaded delivery is created as a **draft**. The creator uploads the file, then publishes with `PATCH /api/v1/products/{id}`. The API must reject publication when a required upload is absent. This prevents a partially configured public product when upload fails.
- The backend keeps `products.configuration_json` as the schema-versioned creator-authoring source and transactionally rebuilds the operational projections used by checkout and fulfillment: course modules/lessons, webinar sessions, meeting availability/slots, payment plans, and checkout fields.
- `GET /api/public/{handle}/products/{productId}` returns only a sanitized `public_configuration`. It must never return redirect destinations, storage object keys, provider join/access URLs, private buyer instructions, welcome messages, or private lesson content.

Creator authoring is not buyer fulfillment. Public lead capture now persists validated consent-aware submissions, but lead email/file delivery is still absent. Paid download delivery, booking, webinar attendance, course learning/progress, recurring subscription lifecycle, custom-service delivery, and community-member portals remain partial or missing as stated above.

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
| Creator SaaS billing | Boundary | Public pricing, plan choice, Premium labels, and Billing UI explicitly keep new accounts on Starter and refuse to collect card data or fabricate entitlement | provider-hosted subscription checkout, verified webhook activation, persisted plan/trial/invoices, backend feature gates; keep separate from store orders |
| Store payment settings | Partial | safe provider readiness, Razorpay-first/Stripe strategy, signed callbacks | creator onboarding, settlement identity, refunds/disputes, reconciliation |
| Razorpay/Stripe execution | Human/provider | test/live adapters can create provider sessions only when explicitly configured | sandbox credential test evidence; production compliance/onboarding |
| Email notifications | Boundary | preferences table and settings tab | save API, event delivery, templates, retries |
| Security/session management | Partial — P0 | BCrypt passwords plus random opaque server-side sessions, SHA-256 token storage, httpOnly SameSite cookies, expiry/logout revocation, owner-scoped creator routes, an allowed-origin mutation guard, and no-cost endpoint-specific IP limiting at the AWS K3s Nginx edge | production TLS/secure-cookie enforcement, account-aware lockout, managed distributed-edge protection, a formal CSRF policy, email verification/reset, MFA, session inventory/revoke-all, audit, account deletion, and broader authorization testing |
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
- `POST /api/events/view`
- `POST /api/public/products/{productId}/leads`

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

It does not prove production-grade identity/security controls, every advanced editor, provider sandbox behavior, performance, AWS readiness, regional failover, or private Stan response parity.

Run `./scripts/product-types-smoke-test.sh` after the API is available to verify the advanced authoring slice. It creates two disposable local creators and all eight configured product types, exercises upload-before-publish and transaction rollback, checks stable normalized IDs, validates tenant isolation and file guards, and rejects private configuration leakage from both public endpoints. It intentionally does not call a payment provider or pretend to complete buyer fulfillment.

## Launch blockers

Before exposing the app to real users, at minimum close the remaining P0 authentication/authorization hardening gaps; introduce migrations and production data lifecycle; finish verified-webhook-to-order/fulfillment/ledger behavior; add validation/rate limits/auditability; implement the actual product workflows being marketed; add frontend component and automated browser tests; and complete the AWS readiness gates in `AWS_REGIONAL_BOOTSTRAP.md`.
