# India launch: payments and Instagram

## Non-negotiable money semantics

Every price, fee, revenue, refund, and payout value is real-world currency. The launch currency is `INR`; APIs use integer `*_subunits` fields, where 100 paise equals ₹1. The database keeps legacy `*_cents` column names only for backward-compatible local volumes and documents that they hold generic smallest units. New payment tables use `amount_subunits`.

The browser never supplies an authoritative amount. `POST /api/v1/checkout/sessions` reloads the published product, creator ownership, store currency, and amount. It requires an `Idempotency-Key`, creates a provider order/session, and records only `provider_created`. A browser return can be signature-checked for user experience, but only a verified provider webhook can move the checkout to `paid`.

## Payment strategy

`Payment provider = Razorpay | Stripe` is a server-side strategy selected per checkout. Razorpay is the India-first default and creates an INR Order before the frontend loads Razorpay Checkout. Stripe Checkout remains optional for an eligible Stripe India account. Provider secrets and webhook secrets are never returned to the browser.

Modes:

- `disabled`: default everywhere; all checkout attempts return 503 and explicitly say no charge was attempted.
- `test`: provider sandbox/test credentials only. No live money.
- `live`: production credentials; enable only after the release gate below.

Webhook ingress uses the unmodified request bytes. Razorpay verifies `X-Razorpay-Signature`; Stripe verifies the timestamped `Stripe-Signature` with a five-minute replay window. An event payload hash is unique per provider, making retries idempotent. Production should move business processing to SQS after persisting the verified event so the HTTP callback returns quickly.

## Instagram test boundary

The supported boundary is Meta's Instagram API with Instagram Login for a professional creator/business account. The app reports whether configuration exists without returning secrets. Webhook subscription verification checks the configured verify token. Event delivery verifies `X-Hub-Signature-256` against the exact request bytes and stores only a hash in this MVP.

`POST /api/v1/integrations/instagram/test-message` is deliberately guarded:

1. Mode must be `test` or `live` and all server credentials must exist.
2. The caller must explicitly send `X-Confirm-External-Send: true`.
3. In test mode, the recipient must be listed in `INSTAGRAM_TEST_RECIPIENT_IDS`.
4. The recipient must already have initiated the Instagram conversation and the app needs `instagram_business_manage_messages`.

Do not implement scraping, password-based login, personal-account automation, or unsolicited bulk DMs. Production AutoDM should persist an inbound signed comment/message event, evaluate an active creator-owned rule, enqueue one idempotent outbound action, apply Meta rate limits, and retain consent/audit evidence.

## Secrets Manager object

Create a different `creator-store/{stage}/runtime` JSON secret in dev, preprod, and prod. Expected keys are `DB_URL`, `DB_USER`, `DB_PASSWORD`, `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET`, `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `INSTAGRAM_ACCOUNT_ID`, `INSTAGRAM_ACCESS_TOKEN`, `INSTAGRAM_APP_SECRET`, `INSTAGRAM_VERIFY_TOKEN`, and `INSTAGRAM_TEST_RECIPIENT_IDS`. Modes stay in the non-secret ConfigMap so disabling an integration is a reviewable GitOps change.

Grant the API service account an IRSA role restricted to that one secret. Enable Secrets Manager rotation where supported, rotate webhook secrets with an overlap plan, and never print request authorization headers, full webhook bodies, access tokens, customer payment details, or secret values.

## Go-live gate

- Razorpay account activation/KYC, settlement account, GST/tax, refund, cancellation, privacy, and terms requirements reviewed for the business.
- Test order, success, failure, retry, duplicate webhook, delayed webhook, refund, dispute, and reconciliation cases pass in dev and preprod.
- Instagram professional-account OAuth, App Review/permissions, webhook subscription, test user, rate limit, deletion/privacy callback, and user consent are validated.
- CloudWatch metrics/alarms, SQS DLQs, reconciliation job, audit trail, backup/restore, kill switch, runbook, and on-call ownership are live.
- A canary creator with low limits is enabled first. Roll back by setting the integration mode to `disabled`; never manufacture a paid status.
