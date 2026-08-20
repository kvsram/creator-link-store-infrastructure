# Instagram comment-to-DM design and policy boundary

Auto DM is implemented only through Meta's official Instagram API private-reply flow. It does not scrape Instagram, automate a consumer login, or cold-message arbitrary users.

## Meta prerequisites

- The influencer connects an Instagram Professional account (Business or Creator) to the Meta app through the supported OAuth flow.
- Request and obtain the current comment and messaging permissions during Meta App Review. For Instagram Login these are currently `instagram_business_basic`, `instagram_business_manage_comments`, and `instagram_business_manage_messages`.
- Subscribe the app webhook to `comments` (and separately `live_comments` only if Live behavior is implemented).
- Verify `X-Hub-Signature-256` with the app secret before parsing or persisting the event.
- A private reply is limited to one message for a comment and must be sent within seven days. Instagram Live private replies are allowed only while the broadcast is live. Follow-up messages are allowed only after the recipient responds and then follow the standard response window.

Official references:

- Meta Instagram API collection and Private Replies documentation: https://www.postman.com/meta/instagram/documentation/6yqw8pt/instagram-api
- Meta Terms: https://www.facebook.com/legal/terms

## Implemented flow

```text
Meta signed comments webhook
  -> verify raw-body HMAC
  -> deduplicate provider event/comment
  -> match active account + media + keyword rule
  -> transactionally create instagram_dm_jobs row
  -> return HTTP 200 quickly

scheduled worker
  -> claim due job with FOR UPDATE SKIP LOCKED and a lease
  -> reject jobs outside the seven-day window
  -> POST /{ig-account-id}/messages with recipient.id = comment_id
  -> mark sent and increment automation stats
  -> exponential retry only for timeout, 429, and 5xx
  -> dead-letter permanent 4xx or exhausted retries
```

`comment_id` is the private-reply recipient. The commenter-scoped ID is stored for audit/correlation but is not used to bypass Meta's conversation rules.

## Scaling

- Webhook replicas are stateless; the PostgreSQL unique constraints make delivery idempotent.
- Workers safely scale horizontally through row locks and leases. Start with two replicas and a database-backed queue. Move to OCI Queue, Azure Service Bus, or another durable broker only when measured throughput or isolation requires it; keep the same idempotency table as the source of truth.
- Partition by Instagram account when one account becomes hot. Apply per-account token buckets below Meta limits and honor `Retry-After` on 429 responses.
- Monitor webhook signature failures, webhook age, pending-job age, sent/retry/dead counts, 429s, expired-window drops, and per-account failure rates.

## Production gates still required

The repository keeps Instagram disabled by default. Before real sends, complete Meta Business Verification/App Review, implement the creator OAuth connection and token refresh lifecycle, encrypt per-creator tokens with envelope encryption, add disconnect/data-deletion handling, create abuse controls and message-template review, configure real alerting, and run a test with an Instagram app-role account. Never put a long-lived access token in Git or a ConfigMap.
