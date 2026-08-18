# Creator Store API contract

Base URL locally: `http://localhost:8080`. JSON keys are intentionally stable and use snake case where the observed API family does.

These are this project's responses, not captured or claimed Stan response bodies. The current endpoints do not authenticate a session and several mutations trust `creatorId`; keep the API local/private until the P0 authorization work in [the feature matrix](FEATURE_PARITY.md) is complete.

## Implemented endpoints

| Method | Path | Purpose |
|---|---|---|
| GET | `/health` | Liveness response `{"status":"ok"}` |
| GET | `/api/public/{handle}` | Published public storefront |
| POST | `/api/auth/register` | Create creator and store |
| OPTIONS, POST | `/api/v1/authentication/check-unique-taken` | Username/email availability |
| GET | `/api/v1/users/get_user?handle=alex` | Creator profile |
| POST | `/api/v1/users/experiments/join_communities` | Demo community join contract |
| GET | `/api/v1/users/experiments/community_stats` | Community counters |
| GET | `/api/v1/users/experiments/metadata` | Feature flags |
| GET | `/api/v1/integrations?creatorId=1` | Provider connection statuses |
| PUT | `/api/v1/experiments/variant-assignment` | Save-compatible variant response |
| PUT | `/api/v1/tags` | Idempotent tag upsert |
| GET | `/api/v1/dashboard?creatorId=1` | Home summary and checklist |
| GET | `/api/v1/store?creatorId=1` | Store, product types, products |
| POST | `/api/v1/products` | Create product draft/published product |
| GET | `/api/v1/income?creatorId=1` | Income summary and orders |
| GET | `/api/v1/analytics?creatorId=1` | Business totals and sources |
| GET, POST | `/api/v1/customers` | List/add customers |
| GET | `/api/v1/success` | Tutorial catalog |
| GET | `/api/v1/more?creatorId=1` | Funnels, appointments, feature list |
| GET | `/api/v1/settings?creatorId=1` | Settings aggregate |
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
| POST | `/api/events/click` | Record a public-link click |

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
  "product_types": ["lead-magnet","digital-download","meeting","fulfillment","course","membership","webinar","community"],
  "products": [
    {"id":1,"type":"digital-download","title":"Creator Content Calendar","price_subunits":49900,"price_cents":49900,"status":"published","position":1}
  ]
}
```

### Create product

```http
POST /api/v1/products
Content-Type: application/json

{"creatorId":1,"type":"course","title":"Launch Course","description":"Four modules","priceSubunits":49900,"status":"draft","position":3}
```

Success is `201` with the persisted product. An unknown type is `400` with `{"error":"unsupported product type"}`.

### Public storefront

```json
{
  "creator":{"id":1,"handle":"alex","display_name":"Alex Rivera","bio":"Systems and templates for independent creators."},
  "store":{"title":"Alex's Creator Store","theme":"violet","currency":"INR"},
  "links":[{"id":1,"title":"Free weekly newsletter","url":"https://example.com/newsletter"}],
  "products":[{"id":1,"type":"digital-download","title":"Creator Content Calendar","price_subunits":49900,"price_cents":49900}]
}
```

`price_cents` is a deprecated compatibility alias. For INR, both values above represent paise, not cents. New clients must use `price_subunits`.

### Checkout session

```http
POST /api/v1/checkout/sessions
Idempotency-Key: 6518b0e6-49a0-4e0f-b583-332b23df2e21
Content-Type: application/json

{"creatorId":1,"productId":1,"provider":"razorpay"}
```

When `PAYMENTS_MODE=disabled` (the default), the result is `503` and explicitly says no charge was attempted. In test/live mode with configured credentials, the API reloads the product and returns provider session metadata; it never accepts an amount from the request.

## Contract limitations

The reference material supplied for this project listed observable paths and methods but not response bodies. These responses are this project's own API contract. They are reproducible after a clean database start, but they must not be described as verbatim Stan responses.
