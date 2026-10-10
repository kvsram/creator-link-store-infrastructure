# Authentication release handoff — 2026-10-10

> **Release status: feature-branch candidate only.** It has not been reviewed, merged to a
> protected integration branch, built into publishable registry images, or deployed to AWS.
> Local PostgreSQL 16/Mailpit SMTP
> lifecycle and controlled V3-upgrade checks now pass, but shared HTTPS/real-provider acceptance
> remains unproven. Do not promote it until every gate in this document is closed.

This document supersedes older authentication, schema-initialization, email-delivery, test-count,
and authentication-readiness statements elsewhere in the infrastructure repository. Older files
remain useful for product and deployment history, but they describe authentication before this
cross-repository candidate.

## 1. Exact source state

All three repositories use `codex/full-authentication-v1`. The backend and frontend candidate
commits are pinned below. For infrastructure, the candidate is the commit containing this handoff;
resolve it with `git rev-parse HEAD` after cloning the branch and record it in the release ticket.

| Component | Repository | Local working tree | Candidate identity | Candidate state |
|---|---|---|---|---|
| Backend | `https://github.com/kvsram/creator-link-store-backend` | `/private/tmp/creator-link-store-backend-core-security` | `214ef5561406e0f425d5e1b2089314d2d36389e6` | Committed controller/service/repository, Flyway, SMTP, Spring Security, Boot 4 migration, patched dependency stack, documentation, and tests |
| Frontend | `https://github.com/kvsram/creator-link-store-frontend` | `/private/tmp/creator-link-store-frontend-core-corrections` | `7c4f6652b6e34d45ef96abde24db4dc89e605d8` | Committed Identity v1 client, UI, NGINX controls, patched dependency stack, documentation, and tests |
| Infrastructure | `https://github.com/kvsram/creator-link-store-infrastructure` | `/private/tmp/creator-link-store-infrastructure-identity-auth` | Commit containing this file on `codex/full-authentication-v1` | Local SMTP, smoke, Kubernetes runtime, protected environment rendering, workflow, runbook, and handoff |

Before review or release, confirm all three candidate commits exist on GitHub, open pull requests
against the intended integration branch, and record the infrastructure SHA plus immutable
backend/frontend registry digests. A branch name or mutable local image tag is not release identity.

At the initial audit, the remote feature refs were absent. The backend publishes through its
GitHub remote named `github`; frontend and infrastructure publish through `origin`. Verify current
remote heads rather than relying on that historical observation.

Primary implementation entry points:

- backend: `docs/AUTHENTICATION_ARCHITECTURE.md`,
  `IdentityAuthController`, `SecurityConfiguration`, `SessionAuthenticationFilter`,
  `IdentityAuthenticationService`, `RegistrationTransactionService`,
  `IdentityChallengeTransactionService`, `AuthDeliveryRepository`, `AuthDeliveryWorker`,
  `SmtpAuthEmailSender`, and `src/main/resources/db/migration/`;
- frontend: `src/apiClient.js`, `src/AuthPages.jsx`, `src/identityAuth.js`, `src/signup.js`,
  `src/main.jsx`, and `nginx.conf`;
- infrastructure: `docs/AUTHENTICATION_E2E.md`, `local/docker-compose.yml`,
  `scripts/auth-smoke-test.sh`, `k8s/auth-runtime-patch.yaml.example`,
  `k8s/aws-external-secret.yaml.example`, and the application/quality workflows.

## 2. Implemented architecture

The backend remains one Spring Boot modular monolith and one PostgreSQL consistency boundary. The
authentication module is isolated in code, but it is not a separately deployed microservice.

```text
Browser / React SPA
  -> same-origin NGINX /api proxy
  -> GET /api/v1/auth/csrf for XSRF cookie/header pair
  -> Spring Security deny-by-default filter chain
       -> SessionAuthenticationFilter
       -> SHA-256(cs_session cookie) lookup in auth_sessions
       -> CreatorPrincipal(accountId, sessionPublicId), ROLE_CREATOR
  -> IdentityAuthController
       -> authentication and transactional challenge services
       -> JdbcTemplate repositories
       -> PostgreSQL
            |-- normalized identity/session/challenge/security-event tables
            `-- transactional auth_delivery_outbox
                   -> leasing/retrying delivery worker
                   -> provider-neutral SMTP adapter
                        |-- Mailpit locally
                        `-- approved SMTP provider such as SES SMTP in a shared stage
```

The session is a random 256-bit opaque cookie, not a JWT. The browser receives `cs_session` as
`HttpOnly`, `SameSite=Lax`, path `/`; production also requires `Secure`. PostgreSQL stores only the
SHA-256 session-token hash. Sessions have a rolling 12-hour idle expiry, a 30-day absolute expiry,
and an account `session_version`; password reset increments that version and revokes all legacy and
v1 sessions.

Spring Security is the HTTP authorization boundary. Servlet sessions, form login, and HTTP Basic
are disabled. `/api/v1/**` and `/api/auth/**` are authenticated unless they appear in the reviewed
public allowlist. Authenticated controllers derive tenant ownership from `CreatorPrincipal`, never
from a browser-supplied creator ID. Cookie-authenticated mutations require the `XSRF-TOKEN` cookie
and matching `X-XSRF-TOKEN` header. The frontend API client includes cookies, bootstraps and caches
the CSRF contract, retries exactly once only after `CSRF_TOKEN_INVALID`, applies timeouts, supports
multipart bodies, and rejects non-JSON success responses rather than accepting false auth success.

## 3. Endpoint and browser flows

| Method and path | Access | Candidate behavior |
|---|---|---|
| `GET /api/v1/auth/csrf` | Public | Issues the CSRF cookie and returns the header/token contract. |
| `POST /api/v1/auth/registrations` | Public + CSRF | Atomically creates a pending account, generated or validated handle, profile, default store/preferences, Argon2id credential, verification challenge, and delivery-outbox row; returns `202` and no session. |
| `POST /api/v1/auth/email-verifications` | Public + CSRF | Consumes one valid token, activates the account, supersedes unsent matching mail, and issues the first session. |
| `POST /api/v1/auth/email-verifications/resend` | Public + CSRF | Replaces an eligible pending-account challenge and returns a generic accepted response. |
| `POST /api/v1/auth/sessions` | Public + CSRF | Authenticates normalized email or handle and creates an opaque session. |
| `GET /api/v1/auth/me` | `ROLE_CREATOR` | Returns only the authenticated account projection. |
| `GET /api/v1/auth/sessions` | `ROLE_CREATOR` | Lists active sessions/devices owned by the account. |
| `DELETE /api/v1/auth/sessions/current` | `ROLE_CREATOR` + CSRF | Revokes the current session and clears the cookie. |
| `DELETE /api/v1/auth/sessions/{publicId}` | `ROLE_CREATOR` + CSRF | Revokes another session only when it belongs to the authenticated account. |
| `POST /api/v1/auth/password-reset-requests` | Public + CSRF | Always returns a generic `202`; queues mail only for an eligible active, verified account. |
| `POST /api/v1/auth/password-resets` | Public + CSRF | Consumes one token, replaces the verifier, increments `session_version`, revokes every session, and clears the browser cookie. |

### Registration and verification

1. The frontend submits display name, normalized email, and a 12–128 character password. Handle
   and phone remain optional at the API boundary; the current frontend lets the backend allocate a
   readable unique handle.
2. The backend rate guard runs before expensive password hashing. New credentials use Argon2id;
   a successful login upgrades an eligible legacy BCrypt verifier.
3. One database transaction writes the compatibility creator row, normalized identity rows,
   credential/login state, default store/preferences, hashed verification challenge, and delivery
   outbox row. Failure rolls back the whole registration.
4. Registration returns `202`, `status=pending_verification`, and no authenticated session.
5. The delivery worker claims an outbox row with a unique lease token, sends it over SMTP, retries
   temporary failures with bounded exponential backoff, and clears the raw delivery token on send,
   expiry, terminal failure, replacement, or challenge consumption.
6. Email links use `/verify-email#token=...`. URL fragments are not sent in HTTP requests, proxy
   access logs, or `Referer` headers. The SPA still accepts a legacy query token for old messages,
   then removes either form from browser history before calling the API.
7. Successful verification activates the account and sets the first opaque session cookie.

### Login and session management

- Unknown identifiers, wrong passwords, locked accounts, and suspended/deleted accounts use the
  same public `401` result. Unknown identifiers still perform comparable password work.
- A correct password for a pending account returns `403 EMAIL_NOT_VERIFIED` with only a masked
  email hint. Resend still requires the full email and does not reveal whether an account exists.
- The dashboard restores state only through `GET /api/v1/auth/me`. A `401` means signed out;
  network/timeouts are shown as service failures instead of silently changing auth state.
- Security settings list sessions, revoke another owned session, revoke all non-current sessions
  through individual owner-scoped calls, and sign out the current browser.

### Password recovery

1. Forgot-password accepts a syntactically valid email and returns the same public `202` shape for
   known and unknown addresses.
2. An eligible account gets a durable outbox row and `/reset-password#token=...` mail link. The SPA
   also accepts the legacy query form and immediately scrubs it from browser history.
3. A valid token is single-use and expires after 30 minutes. Reset writes the new verifier,
   invalidates all earlier sessions, and makes the old password fail.

The old `/api/auth/register`, `/api/auth/login`, `/api/auth/logout`, and `/api/auth/me` compatibility
surface still exists. Compatibility registration is now verification-first, but the new frontend
uses only `/api/v1/auth/**`. Remove the legacy surface after deployed clients are confirmed migrated;
do not restore a frontend fallback to it.

## 4. Flyway migrations and database cutover

Spring startup SQL is disabled. Flyway is enabled with `baseline-on-migrate=true` and baseline
version `1`.

| Migration | Purpose and release behavior |
|---|---|
| `V1__baseline.sql` | Full clean-environment application baseline plus normalized identity tables (`accounts`, profiles, handles, emails/phones, password/login state, hashed opaque sessions, verification/reset tokens, and security events). It backfills legacy creators and still-valid sessions, preserves existing business foreign keys, and grandfathers existing active users' primary emails as verified. A blank database executes V1. A non-empty legacy database with no Flyway history is baselined at V1 rather than replaying this file. |
| `V2__authentication_delivery_outbox.sql` | Adds the transactional email outbox, due/account indexes, retry state, lease time, error metadata, and raw token field needed for delivery. An upgraded legacy database applies this after the V1 baseline marker. |
| `V3__authentication_delivery_lease_ownership.sql` | Adds a unique `lease_token` to every worker claim, returns rows left `leased` by the pre-V3 protocol to `pending`, and enforces consistent lease ownership fields. This prevents a stale worker from overwriting a newer claim. |

Required database evidence before release:

1. Run V1–V3 against a new PostgreSQL 16 database and prove application startup and the complete
   auth lifecycle.
2. Restore a representative copy of the deployed startup-DDL database, take a recoverable
   snapshot, let Flyway baseline it at V1 and apply V2/V3, then prove legacy creator/session
   compatibility and the new lifecycle.
3. Record `flyway_schema_history`, application/image digest, database snapshot, migration timing,
   and rollback owner in the release record.
4. Use a Recreate application cutover for this transition. Mixed old/new pods are not supported.
   V2/V3 are additive, but rolling back to an old image intentionally loses sessions issued only by
   v1 and may reintroduce old auth behavior.
5. Never attempt an automatic schema `DROP` rollback. Restore the snapshot or forward-fix after
   confirming application compatibility.

## 5. Configuration and secret contract

### Nonsecret runtime values

A shared environment must supply and review all of the following through its ConfigMap/overlay:

| Setting | Required shared-stage value |
|---|---|
| `APP_ENVIRONMENT` | `production` for a production stage, enabling the fail-closed guard |
| `APP_ALLOWED_ORIGINS` | Exact comma-separated HTTPS origins; no wildcard |
| `APP_SECURE_COOKIES` | `true` |
| `APP_AUTH_PUBLIC_BASE_URL` | Exact HTTPS frontend base used in email links; its origin must be allowed |
| `APP_AUTH_EMAIL_MODE` | `smtp` |
| `APP_AUTH_EMAIL_FROM` / `APP_AUTH_EMAIL_FROM_NAME` | Verified sender identity and reviewed display name |
| `APP_AUTH_DELIVERY_WORKER_ENABLED` | `true` |
| `APP_AUTH_DELIVERY_POLL_MS` | Reviewed poll period; current default is `1000` ms |
| `APP_AUTH_TEST_DELIVERY_ENABLED` | `false` |
| `APP_SECURITY_CSRF_ENABLED` | `true` |
| `FLYWAY_ENABLED` | `true` |
| `SMTP_HOST` / `SMTP_PORT` | Approved provider-neutral endpoint and port |
| `SMTP_AUTH` | `true` |
| `SMTP_STARTTLS_ENABLED` / `SMTP_STARTTLS_REQUIRED` | both `true` |
| SMTP connect/read/write timeouts | Positive and shorter than the two-minute outbox lease; current contract is `10000` ms each |
| `APP_TRUSTED_PROXY_REGEX` | Only the actual internal reverse-proxy peers for that environment |

The production guard refuses startup when cookies/CSRF/HTTPS origins/public URL, SMTP sender/host,
authenticated mandatory STARTTLS, bounded SMTP timeouts, delivery worker, disabled test mailbox, or
stable fingerprint secret are unsafe. SMTP reachability itself is a runtime health/monitoring gate,
not something startup can prove.

### Secrets

`creator-store-runtime-secrets` must contain the required stage-specific values without
printing or reading them in CI output:

- `DB_URL`, `DB_USER`, and `DB_PASSWORD`;
- an independent stable `APP_AUTH_FINGERPRINT_SECRET` of at least 32 random characters;
- least-privilege provider `SMTP_USERNAME` and `SMTP_PASSWORD`.

Use the environment's secret manager and External Secrets (or the cloud-equivalent mechanism).
Never put values in Git, ConfigMaps, image layers, Terraform outputs, GitHub variables, shell
history, logs, or tickets. Each standard cloud overlay includes its own fail-closed
`auth-runtime.yaml`; `deploy-applications.yml` renders only the selected copy from protected
GitHub Environment variables (`APP_PUBLIC_ORIGIN`, `APP_AUTH_EMAIL_FROM`, `SMTP_HOST`, and
optional `SMTP_PORT`) before Kustomize runs. `k8s/auth-runtime-patch.yaml.example` defines the
nonsecret contract and `k8s/aws-external-secret.yaml.example` defines secret property names only.
The checked-in sentinels remain non-deployable until those reviewed environment variables exist.

The local stack is intentionally different: PostgreSQL 16 plus Mailpit, HTTP localhost origins,
non-Secure cookies, no SMTP authentication/STARTTLS, and a development-only fingerprint value.
Mailpit is bound to localhost for inspection and must never be deployed as a shared-stage relay.

## 6. Local reproduction and verification

Use sibling directory names because Compose build contexts depend on them:

```text
workspace/
├── frontend/       # current frontend candidate
├── backend/        # current backend candidate
└── infrastructure/ # current infrastructure candidate
```

First check out the same feature branch in all three repositories, capture their SHAs, and confirm
the worktrees are clean before reproducing the evidence.

```bash
git -C ../frontend status --short --branch
git -C ../backend status --short --branch
git status --short --branch

# Backend unit/integration suite (currently H2-backed, not PostgreSQL E2E)
(cd ../backend && mvn clean verify)

# Frontend contract/helper tests and production bundle
(cd ../frontend && npm test && npm run build)

# Integrated PostgreSQL 16 + Mailpit SMTP + backend + frontend
make doctor
make up
make smoke
make auth-smoke
make product-smoke
```

`make auth-smoke` creates a unique synthetic account, obtains a real CSRF pair, reads only that
recipient's newest Mailpit messages, proves signup -> verification -> `/me` -> logout -> login ->
forgot/reset -> old session revoked -> old password rejected -> new password accepted, and rejects
reset-token replay. It removes its temporary cookie jar and does not print passwords or tokens.
Use only synthetic identities. `make down` stops containers while preserving the named PostgreSQL
volume; database destruction is deliberately not part of this handoff.

For manual browser verification, use `http://localhost:3000` and inspect mail only at
`http://localhost:8025`. The detailed positive and negative checklist is in
[`AUTHENTICATION_E2E.md`](AUTHENTICATION_E2E.md).

## 7. Evidence available at handoff

| Check | 2026-10-10 result | Evidence boundary |
|---|---|---|
| Backend `mvn clean verify` | **PASS — 100 tests, 0 failures, 0 errors, 0 skipped** | Completed by the coordinating final verification on the current backend working tree; Surefire reports record the same totals. These are not real-PostgreSQL or real-SMTP E2E evidence. |
| Backend dependency resolution | **PASS** | Spring Boot `4.0.8` resolves Spring Framework `7.0.9`; Tomcat is pinned to `11.0.26`; Bouncy Castle to `1.86`; application Jackson 3 to `3.1.7`; and Flyway's separate Jackson 2 core/databind stack to `2.21.7`. The repackaged JAR contains those two patched Jackson stacks. |
| Frontend `npm test` | **PASS — 48/48** | Re-run on the current frontend working tree. Tests are primarily API/helper/contract tests, not a complete browser suite. |
| Frontend `npm run build` | **PASS** | Re-run on the current frontend working tree; 30 modules transformed and a production bundle was emitted. A build is not a deployment. |
| Backend/frontend/infrastructure diff whitespace checks | **PASS after final handoff edit** | `git diff --check` passed in all three repositories; the new untracked handoff also passed a no-index whitespace check. |
| Real PostgreSQL 16 + Mailpit SMTP lifecycle | **PASS** | Coordinating final runtime used the exact final local backend/frontend images and proved registration, required verification, email arrival, verification, authenticated `/me`, logout/revocation, login, generic reset request, reset mail, reset, old-session/password rejection, new-password acceptance, and replay rejection. Mailpit is an SMTP sink, not an external provider. |
| Controlled local Flyway upgrade | **PASS** | The exact committed final image was first capped at Flyway target V2; a marker row was inserted; the same image without the cap applied V3, preserved the marker, and exposed a UUID `lease_token`. This is not yet a production-copy restore test. |
| Blank PostgreSQL 16 V1–V3 migration | **PASS** | The exact final backend image became healthy on a brand-new database, recorded Flyway versions 1, 2, and 3, and created the seven checked core auth tables: accounts, password credentials, sessions, verification/reset tokens, security events, and delivery outbox. |
| Frontend container/proxy policy | **PASS** | Runtime checks saw `no-store` and `no-referrer` on `/verify-email`, did not apply `no-store` to fingerprinted JavaScript, and received JSON `200` through the NGINX proxy for `/api/v1/auth/csrf`. |
| Changed/untracked secret hygiene | **PASS, read-only scan** | No high-confidence private key, cloud/GitHub token, JWT, payment-provider secret, credential-bearing URL, or untracked binary was found. This does not replace repository secret scanning. |
| Representative deployed-schema baseline + V2/V3 upgrade | **PENDING** | Required release gate; must use a recoverable snapshot/copy. |
| Shared HTTPS stage + approved real SMTP provider | **NOT RUN** | Required before public or production use. |
| AWS deployment of this candidate | **NOT RUN** | No candidate commits, published image digests, migration record, or post-deploy verifier exists. |
| GitHub pull-request quality checks | **PASS** | Backend `verify`, frontend `build`, and infrastructure `validate-local-stack` plus `validate-terraform` passed on their current feature-branch commits. A green PR check is not a deployment. |

The exact local images used by the final runtime checks were
`creator-store-backend:auth-v1-security-final` with local image ID
`sha256:899edc13bdb5b9914ed96365ebc6593e332d3d302d8dbedb845eeb223591a93e` and
`creator-store-frontend:auth-v1-security-final` with local image ID
`sha256:576fb38d5e5a661e0777f548a778834bb9472d24b84fc31ea0889ef5d0d450ea`.
These IDs identify the locally tested images; they are not published registry digests or substitutes
for committed source SHAs and signed release provenance.

## 8. AWS live mismatch

The reachable disposable AWS endpoint is not this candidate. The 2026-10-10 completeness ledger
records the following frozen synthetic-data release in `us-east-2`:

| Item | Recorded deployed identity |
|---|---|
| Public origin | `http://77.112.61.68` |
| Frontend source / image | `6eee4556f0dc02f6ad2dafe5758d5a4e646f8461` / `sha256:16a25daf02c9e1d562b278d13906215786a7a743cf16ba91390293db0d35277d` |
| Backend source / image | `3a1ae4286a66e531333d6ee512d34821870144c1` / `sha256:1a0c2f4d720199a48c22885c4ff4f9898740b5394785bb58a479d2624dc7535e` |
| Infrastructure source | `1cd0b072905e5ee155e25e9575a32e1f2d5a0c5e` |
| Applied infrastructure marker | `d130d37d64c7ea413cd60a56fb7716a1335d1f62` |
| Database migration state | `NONE-startup-DDL` |

Read-only probes recorded around `2026-10-10T20:30Z` and `2026-10-10T20:59:41Z` returned HTTP
`200` for selected public routes. HTTPS timed out with status `000`. No usable AWS read identity was
available to re-read control-plane state, so current instances, RDS state, secret objects, release
markers, and costs remain unverified. The original disposable-stack deadline was 2026-09-15; an
authorized operator must explicitly extend/recreate or destroy it.

That frozen release is HTTP-only, uses older backend/frontend code and startup DDL, and lacks this
candidate's verified-email/SMTP/Flyway/security cutover. Public-route `200` responses do not prove
authentication, email delivery, database migration, current artifacts, or production readiness.

## 9. Deployment gates

Do not deploy this slice by copying working trees or pointing the old endpoint at mutable tags.
Close these gates in order:

1. **Freeze source:** review all modified and untracked files; commit and push each repository;
   run required CI; record exact source SHAs, image digests, SBOM/provenance, and this infrastructure
   revision.
2. **Prove migrations:** preserve the passing local blank/V3-upgrade evidence, then pass the
   representative deployed-schema path, capture its V3 Flyway history and pre-migration snapshot,
   and rehearse restore/forward-fix.
3. **Prepare HTTPS:** provision reviewed domain/DNS, certificate, HTTPS redirect, exact allowed
   origins, Secure cookies, trusted proxy boundaries, ingress policy, and WAF/rate controls.
4. **Prepare email/secrets:** verify sender/domain, approved SMTP credentials, mandatory STARTTLS,
   bounce/complaint/suppression/quota operations, stable fingerprint secret, External Secrets
   synchronization, rotation owner, and alarms. Keep the test-delivery endpoint disabled.
5. **Reconcile deployment automation:** the generic `deploy-applications.yml` now renders the
   selected cloud's fail-closed auth patch from protected environment variables, rejects remaining
   placeholders, and checks secret key names, but it still does not itself prove the
   applied SSM infrastructure marker, cloud identity/cluster acquisition, source-to-image digest
   mapping, canary analysis, or automatic rollback. Use/reconcile the stricter AWS-specific release
   path before treating the workflow as production-capable. A deployment remains blocked until the
   selected protected GitHub Environment contains reviewed nonsecret values and the cluster Secret
   exposes every required key; do not bypass either check.
6. **Cut over compatibly:** use a protected environment and approved change, verify the exact
   applied infrastructure SHA, deploy exact digests with a Recreate strategy, and prevent an old
   image from starting against the cutover by accident.
7. **Run acceptance:** on HTTPS with the approved mail provider, use at least two fresh synthetic
   users to prove registration, delivery, verification, login/logout, session inventory and
   cross-account revocation denial, forgot/reset, old-session/password invalidation, expired and
   replayed tokens, CSRF rejection, enumeration-safe responses, and unauthorized protected APIs.
8. **Observe and roll back:** monitor auth success/failure/rate-limit events, outbox age/retries/dead
   rows, SMTP failures, 4xx/5xx, latency, database health, and alarms. Record previous healthy
   digests and an owner. Never roll back schema destructively or roll back to the known insecure
   frozen AWS auth release as a routine response.
9. **Verify live state:** with fresh MFA-backed short-lived AWS access, resolve the exact
   account/region/resources, deadline decision, infrastructure marker, image digests, Flyway
   version, runtime config/secret versions, TLS, and post-deploy synthetic results.

## 10. Known residual gaps

The local SMTP/PostgreSQL lifecycle now passes, but the following remain open:

- the feature-branch candidate is not yet reviewed, merged, published as immutable registry
  images, or deployed;
- a representative deployed startup-DDL baseline/upgrade, snapshot/restore, and shared-stage N-1
  application compatibility proof is incomplete;
- SES or another approved external SMTP provider, sender verification, bounce/complaint handling,
  quotas, delivery alarms, and shared-stage browser E2E are unproven;
- rate guards are in-memory per application instance; distributed edge/Redis controls are still
  required before horizontal scale;
- MFA/passkeys, recovery codes, breached-password screening, email-change confirmation, and
  account deletion/recovery are not implemented;
- pending outbox tokens are stored in recoverable plaintext until sent, consumed, superseded,
  expired, or terminally failed; application-level encryption is a future hardening item;
- the legacy `/api/auth/*` surface remains and must be removed after client migration;
- frontend coverage is not yet React component, full browser/device, accessibility, or adversarial
  security coverage;
- `/health` is process liveness and does not prove PostgreSQL or SMTP readiness;
- session device/location labels are deliberately coarse and do not provide a mature security
  investigation experience;
- outbox/auth metrics, dashboards, paging, delivery-dead-letter operations, penetration testing,
  and a tested incident/rollback drill are not complete;
- the checked-in ExternalSecret contract and fail-closed cloud auth patches are not proof that a
  target cluster has External Secrets, least-privilege access, correct secret values, or configured
  protected GitHub Environment variables;
- the disposable AWS environment remains HTTP-only, stale, past its original deadline, and
  control-plane-unverified.

Authentication completion does not close the independent commerce, fulfillment, storage,
reporting, privacy/legal, availability, and provider-readiness blockers in
[`VERIFIED_COMPLETENESS_LEDGER_2026-10-10.md`](VERIFIED_COMPLETENESS_LEDGER_2026-10-10.md).
