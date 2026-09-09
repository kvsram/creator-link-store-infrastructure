# Creator Store API contract

Base URL locally: `http://localhost:8080`. JSON keys are intentionally stable and use snake case where the observed API family does.

These are this project's responses, not captured or claimed Stan response bodies. Creator operations under `/api/v1/**` use an opaque httpOnly session and derive creator tenancy on the server. Public storefront, checkout, click-ingress, and signed provider-webhook routes are intentionally anonymous and validate their referenced resources.

## Endpoint inventory

The product-configuration rows below are implemented. The current local evidence is 58 passing Java tests, 30 passing frontend tests, a production frontend build, a real PostgreSQL/HTTP smoke flow across all eight types, restart persistence, and a manual browser walkthrough. That evidence covers creator authoring, creator-profile persistence, public lead persistence, view-event behavior, and safe presentation; it does not prove email/file delivery or the other buyer/provider workflows.

| Method | Path | Purpose |
|---|---|---|
| GET | `/health` | Liveness response `{"status":"ok"}` |
| GET | `/api/public/{handle}` | Published public storefront |
| POST | `/api/auth/register` | Create creator and store |
| OPTIONS, POST | `/api/v1/authentication/check-unique-taken` | Public-handle availability without email enumeration |
| GET | `/api/v1/users/get_user?handle=alex` | Creator profile |
| POST | `/api/v1/users/experiments/join_communities` | Demo community join contract |
| GET | `/api/v1/users/experiments/community_stats` | Community counters |
| GET | `/api/v1/users/experiments/metadata` | Feature flags |
| GET | `/api/v1/integrations?creatorId=1` | Provider connection statuses |
| PUT | `/api/v1/experiments/variant-assignment` | Save-compatible variant response |
| PUT | `/api/v1/tags` | Idempotent tag upsert |
| GET | `/api/v1/dashboard?creatorId=1` | Home summary and checklist |
| GET, PATCH | `/api/v1/store` | Store design, item types, products, promotions |
| POST | `/api/v1/products` | Create an owner-scoped product with common fields plus type configuration as one aggregate |
| PATCH, DELETE | `/api/v1/products/{id}` | Owner-scoped aggregate edit/publish or protected deletion; `type` remains immutable |
| PATCH | `/api/v1/products/{id}/pin?pinned=true` | Pin/unpin; pinned products sort first in admin and public store |
| PUT | `/api/v1/products/{id}/configuration` | Existing separate configuration update; retained only as a compatibility boundary when aggregate POST/PATCH is available |
| GET | `/api/v1/products/{id}/configuration` | Authenticated creator detail with parsed configuration and normalized projections |
| GET, POST | `/api/v1/products/{id}/files` | List or upload an owner-scoped product/lesson/supporting file |
| DELETE | `/api/v1/products/{productId}/files/{fileId}` | Delete an owner-scoped, unused staged file and local object; protect the last required live delivery file |
| GET | `/api/public/{handle}/products/{productId}` | Published type-specific product detail with sanitized `public_configuration` |
| POST | `/api/public/products/{productId}/leads` | Idempotently persist a validated lead for a published lead magnet |
| POST | `/api/v1/promotions` | Create outbound promotion/affiliate/media link |
| PATCH, DELETE | `/api/v1/promotions/{id}` | Authenticated owner edit/publish/schedule/reorder/delete |
| PATCH | `/api/v1/promotions/{id}/pin?pinned=true` | Pin/unpin a promotion; public feed sorts all pinned promotions and products first |
| GET | `/api/v1/income?creatorId=1` | Income summary and orders |
| GET | `/api/v1/analytics?creatorId=1` | Business totals and sources |
| GET, POST | `/api/v1/customers` | List/add customers |
| GET | `/api/v1/success` | Tutorial catalog |
| GET | `/api/v1/more?creatorId=1` | Funnels, appointments, feature list |
| GET | `/api/v1/settings` | Authenticated creator's settings aggregate |
| PATCH | `/api/v1/settings/profile` | Update the session owner's display name, public store address, bio, and optional phone |
| GET | `/api/v1/payments/config` | Safe real-money provider/mode readiness; never secrets |
| POST | `/api/v1/checkout/sessions` | Idempotent Razorpay or Stripe checkout session from server-side product price |
| POST | `/api/v1/payments/razorpay/verify` | Verify Razorpay browser return; webhook remains final truth |
| POST | `/api/v1/webhooks/razorpay` | Verify and idempotently record Razorpay webhook |
| POST | `/api/v1/webhooks/stripe` | Verify timestamp/signature and idempotently record Stripe webhook |
| GET | `/api/v1/integrations/instagram/config` | Safe Instagram mode/readiness metadata |
| GET, POST | `/api/v1/webhooks/instagram` | Meta subscription challenge and signed event ingress |
| POST | `/api/v1/integrations/instagram/test-message` | Guarded allowlisted external test message |
| GET | `/api/v1/automations/instagram-posts-metadata` | Safe Instagram connection metadata |
| GET | `/api/v1/automations/analytics?automation_ids=1` | Automation counters |
| POST | `/events` | Accept page-view analytics event |
| POST | `/api/events/view` | Record a published storefront view by server-resolved public handle |
| POST | `/api/events/click` | Record a click only for an active published promotion in the supplied public storefront |

## Representative responses

### Dashboard

```json
{
  "store": {"title":"Alex's Creator Store","published":true,"payouts_enabled":false},
  "metrics": {"visits":1,"leads":1,"orders":1,"revenue_subunits":49900},
  "checklist": [
    {"id":"profile","label":"Complete your profile","complete":true}
  ]
}
```

### Store

```json
{
  "store": {"id":1,"title":"Alex's Creator Store","theme":"violet","currency":"INR","published":true},
  "product_types": ["lead-magnet","digital-download","meeting","fulfillment","course","membership","webinar","community","url-media"],
  "products": [
    {"id":1,"type":"digital-download","title":"Creator Content Calendar","price_subunits":49900,"price_cents":49900,"status":"published","position":1}
  ],
  "promotions": []
}
```

### Create a promotion / external link

```http
POST /api/v1/promotions
Content-Type: application/json

{"title":"25% off Glow Beauty Cream","url":"https://merchant.example/glow?utm_campaign=creator","description":"Creator partner offer","brandName":"Glow Beauty","thumbnailUrl":"https://cdn.example/glow.jpg","callToAction":"Shop with my link","couponCode":"GLOW25","offerText":"25% off","disclosure":"#ad · Affiliate link","position":10,"published":true,"startsAt":null,"endsAt":null}
```

Destination and thumbnail URLs must be absolute HTTPS URLs. If both schedule values are set, `endsAt` must be later than `startsAt`. Public queries include only published promotions inside their active schedule. Promotion clicks require both `linkId` and `creatorId`; the API verifies their relationship before recording the bounded path, referrer, user agent, and campaign metadata.

### Create or update a product aggregate

Creator-authoring requests use camelCase. Server responses use the existing snake_case response convention. `creatorId` is never accepted as authority; the authenticated session supplies tenancy.

```http
POST /api/v1/products
Idempotency-Key: product-create-6518b0e6-49a0-4e0f-b583-332b23df2e21
Content-Type: application/json

{
  "type": "course",
  "title": "Launch Course",
  "subtitle": "Build a launch plan in four modules",
  "description": "Video lessons and downloadable worksheets",
  "callToAction": "Start learning",
  "thumbnailStyle": "preview",
  "priceSubunits": 49900,
  "status": "draft",
  "position": 3,
  "configuration": {
    "schemaVersion": 1,
    "dripDays": 0,
    "modules": [
      {
        "title": "Plan",
        "lessons": [
          {"title": "Choose the offer", "videoUrl": "https://video.example/offer", "description": "Worksheet included"}
        ]
      }
    ]
  }
}
```

The success response is `201` with the persisted aggregate. `Idempotency-Key` is optional for legacy clients and limited to 120 characters, but retry-capable clients should generate one unique key for each logical create and reuse that same key for retries. Its scope is the authenticated creator: replaying a key returns the originally created aggregate instead of inserting a duplicate. Do not reuse a key for a different payload; it does not update the original product.

`PATCH /api/v1/products/{id}` accepts the same editable common/configuration fields and returns the updated aggregate. The type chosen at creation is immutable; a type-changing PATCH is `409`. An unknown type, invalid configuration, cross-creator ID, or attempt to publish without a required staged upload is rejected without leaving a partially updated aggregate.

The service persists `configuration.schemaVersion = 1` and transactionally synchronizes the normalized operational rows applicable to that type. Creator detail is then available from:

```http
GET /api/v1/products/42/configuration
Cookie: cs_session=...
```

```json
{
  "id": 42,
  "type": "course",
  "title": "Launch Course",
  "status": "draft",
  "configuration": {"schemaVersion":1,"dripDays":0,"modules":[{"title":"Plan","lessons":[{"title":"Choose the offer"}]}]},
  "files": [{"id":8,"file_name":"worksheet.pdf","content_type":"application/pdf","size_bytes":24011,"kind":"supporting-material"}],
  "meeting_slots": [],
  "webinar_sessions": [],
  "payment_plans": [],
  "checkout_fields": [],
  "course_modules": [{"id":4,"title":"Plan","position":0,"lessons":[{"id":9,"title":"Choose the offer","position":0}]}]
}
```

The creator response may contain private authoring/delivery information because it is owner-scoped. It does not contain filesystem paths, and file objects expose metadata rather than `object_key`.

### Eight supported authoring configurations

| Product type | Configuration accepted from the creator | Operational projection | Still not proved by authoring alone |
|---|---|---|---|
| `digital-download` | `schemaVersion`, `deliveryMode` (`upload` or `redirect`), HTTPS `redirectUrl` for redirect mode | owned `product_files` metadata | entitlement check, malware scan, signed/redirect delivery |
| `lead-magnet` | download fields plus `collectName`, required `collectEmail`, optional `collectPhone`, and `consentText`; price must remain zero | owned download metadata plus idempotent, consent-aware lead persistence | confirmation email and gated signed delivery |
| `meeting` | `location`, optional `locationDetails`, IANA `timezone`, `durationMinutes`, `maxAttendees`, `minNoticeHours`, `bufferMinutes`, and `slots[]` with start/end | `availability_schedules` and product-owned `bookings` slots | calendar OAuth, conflict handling, buyer book/cancel/reschedule |
| `webinar` | `location`, IANA `timezone`, default `durationMinutes`/`capacity`, and `sessions[]` with start/end/capacity/private HTTPS `joinUrl` | `webinar_sessions` | provider event creation, registration, reminders and attendance |
| `course` | ordered modules/lessons with titles/descriptions, optional HTTPS video metadata, and `dripDays` | `course_modules` and `course_lessons` | learner portal, streaming, progress and completion |
| `membership` | `plans[]` (`name`, `amountSubunits`, interval and interval count), public `benefits[]`, and private `welcomeMessage` | `product_payment_plans` | recurring provider lifecycle, cancellation and entitlement enforcement |
| `fulfillment` | `turnaroundDays`, `deliveryFormat` (`file-upload`, `email`, `call`), private `buyerInstructions`, and `checkoutFields[]` with `text`, `textarea`, `email`, `phone`, `number`, or `url` field types | `product_checkout_fields` | creator work queue and buyer delivery/status portal |
| `community` | platform (`discord`, `whatsapp`, `telegram`, `circle`, `slack`, `custom`), private HTTPS `accessUrl`, public `benefits[]`, and private `welcomeMessage` | no provider membership is created by authoring | protected community, moderation and member entitlement checks |

### Staged upload and publication

Uploads cannot be embedded in a JSON transaction. For `digital-download` and `lead-magnet` with `deliveryMode=upload`, use this sequence:

1. `POST /api/v1/products` with `status="draft"` and the complete validated configuration.
2. `POST /api/v1/products/{id}/files?kind=download` as multipart form data.
3. Optionally inspect `GET /api/v1/products/{id}/configuration` and remove a wrong file using `DELETE /api/v1/products/{productId}/files/{fileId}`.
4. `PATCH /api/v1/products/{id}` with `status="published"`.

The publish transition must fail when upload-mode delivery has no owned download file. A failed upload therefore leaves a non-public draft, not a published product with no fulfillment asset.

### Public storefront

```json
{
  "creator":{"id":1,"handle":"alex","display_name":"Alex Rivera","bio":"Systems and templates for independent creators."},
  "store":{"title":"Alex's Creator Store","theme":"violet","currency":"INR"},
  "links":[{"id":1,"title":"Free weekly newsletter","url":"https://example.com/newsletter"}],
  "products":[{
    "id":1,
    "type":"digital-download",
    "title":"Creator Content Calendar",
    "price_subunits":49900,
    "price_cents":49900,
    "public_configuration":{"schemaVersion":1,"delivery":"after-purchase"}
  }]
}
```

`price_cents` is a deprecated compatibility alias. For INR, both values above represent paise, not cents. New clients must use `price_subunits`.

Both the storefront collection and `GET /api/public/{handle}/products/{productId}` carry a server-built, allowlisted `public_configuration`. The collection supplies the safe data needed by current cards and checkout controls; the detail route returns the selected published product using the same projection rules. For example, a course detail is:

```json
{
  "id": 42,
  "creator_id": 7,
  "type": "course",
  "title": "Launch Course",
  "description": "Video lessons and downloadable worksheets",
  "subtitle": "Build a launch plan in four modules",
  "call_to_action": "Start learning",
  "thumbnail_style": "preview",
  "price_subunits": 49900,
  "status": "published",
  "position": 3,
  "pinned": false,
  "currency": "INR",
  "public_configuration": {
    "schemaVersion": 1,
    "dripDays": 0,
    "modules": [
      {
        "id": 4,
        "title": "Plan",
        "description": "Start with positioning",
        "position": 0,
        "lessons": [{"id":9,"title":"Choose the offer","position":0}]
      }
    ]
  }
}
```

`public_configuration` is a server-built projection, not raw `configuration_json`. Public payloads must exclude at least `redirectUrl`, file `objectKey`, local paths, provider `joinUrl`/`accessUrl`, private `buyerInstructions`, `welcomeMessage`, unpublished lesson content, and any creator/provider credential. A download destination is disclosed only after the appropriate lead or paid entitlement flow; those buyer flows are not made complete by this authoring API.

### Creator profile update

```http
PATCH /api/v1/settings/profile
Cookie: cs_session=<opaque-session-token>
Content-Type: application/json

{
  "displayName": "Alex Creates",
  "handle": "alex_creates",
  "bio": "Practical creator systems.",
  "phone": "+91 98765 43210"
}
```

```json
{
  "id": 1,
  "username": "alex_creates",
  "display_name": "Alex Creates",
  "email": "alex@example.com",
  "phone": "+91 98765 43210",
  "bio": "Practical creator systems.",
  "avatar_url": null
}
```

The session decides the creator row; a client-supplied creator ID is not accepted as authority. Handles are lowercased, must contain 3–40 letters, numbers, or underscores, and cannot collide with another creator or a reserved application route. Validation returns `400`, a taken address returns `409`, and a missing/expired session returns `401`. A successful handle change immediately moves the public store to the new route; there is no old-address redirect in this slice.

### Checkout session

```http
POST /api/v1/checkout/sessions
Idempotency-Key: 6518b0e6-49a0-4e0f-b583-332b23df2e21
Content-Type: application/json

{"creatorId":1,"productId":1,"provider":"razorpay","buyerEmail":"buyer@example.com","buyerName":"Buyer"}
```

When `PAYMENTS_MODE=disabled` (the default), the result is `503` and explicitly says no charge was attempted. In test/live mode with configured credentials, the API reloads the product and returns provider session metadata; it never accepts an amount from the request.

## Contract limitations

The reference material supplied for this project listed observable paths and methods but not response bodies. These responses are this project's own API contract. They are reproducible after a clean database start, but they must not be described as verbatim Stan responses.

Product authoring, buyer fulfillment, and provider execution are separate proof boundaries. Creator CRUD/configuration tests do not prove that a visitor can receive a download, submit a lead magnet, reserve a conflict-free meeting, attend a webinar, consume a course, maintain a recurring membership, receive custom work, or enter a protected community. Keep those flows marked partial until their visitor UI, API, persistence, authorization/entitlement, external-provider behavior, and browser E2E tests all pass.
