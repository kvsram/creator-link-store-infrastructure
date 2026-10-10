# Authentication end-to-end verification

## Local contract

The local stack exercises the real authentication database, Spring Security filter
chain, CSRF protection, opaque session cookies, durable email outbox, delivery
worker, and provider-neutral SMTP adapter. Mailpit is the only fake boundary: it
accepts SMTP inside Docker and exposes the captured messages at
`http://localhost:8025`. It does not send mail to the internet and is not a
production dependency. The automated checks use Mailpit's documented
[`/view/latest.txt?query=...` integration endpoint](https://mailpit.axllent.org/docs/integration/)
to read only the newest message for the unique synthetic recipient.

The relevant local URLs are:

| Purpose | URL |
|---|---|
| Public landing/signup | `http://localhost:3000/` and `http://localhost:3000/signup` |
| Login | `http://localhost:3000/login` |
| Forgot password | `http://localhost:3000/forgot-password` |
| API health | `http://localhost:8080/health` |
| Mailpit inbox | `http://localhost:8025` |

After `make up`, run `make auth-smoke` for an independent automated proof of the
complete lifecycle below. The script creates a unique synthetic account, obtains a
real CSRF cookie/token, polls Mailpit for both one-time links, checks `/me`, logout,
session revocation, old/new password behavior, and token replay. It never prints the
passwords or tokens and removes its temporary cookie jar on exit.

## Manual browser proof

1. Run `make up` and wait for every service to become healthy. Open the Mailpit
   inbox and delete any old messages, or use a unique address such as
   `creator+<timestamp>@example.test`.
2. Sign up with display name, email, optional phone, and a 12–128 character
   passphrase. A public store address may be left blank; the API generates a unique
   one. Expect the UI to say that verification is required, not to open an
   authenticated dashboard session.
3. In Mailpit, open **Verify your Creator Store email** for the exact recipient.
   Click the link. It must open the SPA at `/verify-email?token=...`, consume the
   single-use token, set an opaque `HttpOnly` `cs_session` cookie, and continue to
   onboarding/dashboard.
4. Sign out, sign in with the email and original passphrase, and verify the creator
   can read only their own profile/store data. Wrong credentials must return a
   generic failure. A pending account may be told that verification is required only
   after its password is proven; any email hint must remain masked.
5. Open `/forgot-password`, submit the same email, and expect a generic accepted
   response. Submitting an unknown syntactically valid email must return the same
   public status and response shape; latency distribution is a separate security test.
6. In Mailpit, open the newest **Reset your Creator Store password** message for the
   exact recipient. Click its `/reset-password?token=...` link and choose a different
   12–128 character passphrase.
7. Confirm the old password fails, the new password succeeds, all sessions created
   before the reset are rejected, and reusing either one-time link fails. Keep error
   text generic; never display or log a raw token.

## Direct API and CSRF rule

Browser state-changing requests require both the `XSRF-TOKEN` cookie and the token
in the `X-XSRF-TOKEN` header. A direct test must first call
`GET /api/v1/auth/csrf` with a cookie jar, read the returned `token`, then send that
value as `X-XSRF-TOKEN` with the same cookie jar and an allowed `Origin`. Do not
disable `APP_SECURITY_CSRF_ENABLED` for a test. Webhooks use separately authenticated
CSRF exemptions and are outside this authentication workflow.

Primary endpoints:

| Operation | Method and path | Expected public result |
|---|---|---|
| CSRF bootstrap | `GET /api/v1/auth/csrf` | token plus `XSRF-TOKEN` cookie |
| Signup | `POST /api/v1/auth/registrations` | `202`; verification required; no session |
| Verify email | `POST /api/v1/auth/email-verifications` | `200`; one authenticated session |
| Login | `POST /api/v1/auth/sessions` | `200` or generic authentication failure |
| Current account | `GET /api/v1/auth/me` | authenticated account only |
| Logout | `DELETE /api/v1/auth/sessions/current` | session revoked and cookie cleared |
| Forgot password | `POST /api/v1/auth/password-reset-requests` | generic `202` |
| Reset password | `POST /api/v1/auth/password-resets` | `200`; all sessions/tokens revoked |

## Kubernetes/SMTP contract

The Kubernetes base intentionally cannot start the backend in production: its
production environment flag is paired with disabled email and non-routable
placeholders. Each AWS/Azure/OCI overlay already includes a fail-closed
`auth-runtime.yaml`. The manual deployment workflow replaces its sentinels from the
selected protected GitHub Environment's `APP_PUBLIC_ORIGIN`,
`APP_AUTH_EMAIL_FROM`, `SMTP_HOST`, and optional `SMTP_PORT`, then rejects any
remaining `.invalid` value. `k8s/auth-runtime-patch.yaml.example` documents that
nonsecret contract. `k8s/aws-external-secret.yaml.example` maps the
required secret properties without containing values. The equivalent Azure/OCI
deployment must source the same environment keys from its native secret manager.

Required nonsecret values include an HTTPS public base URL, exact HTTPS allowed
origins, verified sender address/name, SMTP host/port/TLS switches, production mode,
SMTP email mode, secure cookies, and enabled CSRF. Required secrets include the
database credentials, an independent random `APP_AUTH_FINGERPRINT_SECRET` of at
least 32 characters, and provider SMTP credentials. Rotate SMTP credentials and the
fingerprint secret through a planned secret release; rotating the fingerprint secret
changes pseudonymous client fingerprints and must not be treated as a routine config
toggle.

The connection, read, and write SMTP timeouts are each 10 seconds. Keep every
timeout positive and shorter than the two-minute outbox lease. Each claimed row also
has a unique lease token, so a worker that finishes after losing its lease cannot
overwrite the newer worker's delivery state.
