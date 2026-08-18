# Spring Boot backend architecture

## Request path

```text
HTTP request
  -> domain RestController (routing and HTTP status)
  -> domain Service (validation, business rules, orchestration)
  -> domain Repository (SQL only)
  -> PostgreSQL

External side effect
  -> PaymentService / InstagramService
  -> provider strategy/client
  -> Razorpay, Stripe, or Instagram Graph API

Signed callback
  -> webhook controller
  -> signature verification service
  -> idempotent webhook repository + checkout state transition
```

## Package responsibilities

| Package | Responsibility |
|---|---|
| `controller` | 21 small REST controllers grouped by HTTP/domain boundary plus global API error handling |
| `service` | validation, use cases, transactional/orchestration boundary, response composition |
| `repository` | parameterized JDBC reads/writes grouped by domain |
| `dto` | public request records; prevents request shapes from being hidden as nested controller classes |
| `integration` | payment strategy interface and Razorpay/Stripe/Instagram HTTP adapters |
| `security` | constant-time HMAC and webhook signature helpers |
| `config` | dependency beans and centralized local CORS policy |
| `bootstrap` | deterministic seed behavior, separate from the application entry point |
| `support` | small cross-cutting value/result helpers |

`CreatorStoreApplication` now contains only the Spring Boot entry point. Controllers do not contain SQL or provider HTTP calls. Razorpay and Stripe implement the same `PaymentProviderClient` strategy, so adding an India provider does not require another checkout controller.

## Controller map

The public store, authentication, user experiments, integration catalog, experiment assignment, tags, dashboard, store, products, income, analytics, customers, success content, more tools, settings, automations, analytics events, payments, payment webhooks, and Instagram integration have separate controllers. Their existing route paths are preserved.

This is a maintainable modular monolith, not microservices. For the current scale that is deliberate: one deployable Java process keeps transactions and local development simple while maintaining seams that can later become services if load, ownership, or failure isolation justifies it.

## Next backend production layers

Before public launch, add Spring Security authentication/authorization, Bean Validation, Flyway migrations, explicit transaction annotations for multi-write operations, repository integration tests with PostgreSQL/Testcontainers, OpenAPI/contract tests, rate limiting, structured audit logs, Micrometer/OTel, background job/outbox processing, and a real order/ledger/fulfillment state machine. Do not split into microservices merely to increase the number of layers.
