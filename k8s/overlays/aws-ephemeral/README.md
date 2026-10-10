# AWS ephemeral K3s overlay

This overlay is only for the short-lived, single-node K3s/RDS feature test. It
exposes the frontend through host port `80`, keeps NodePort `30080` for
node-local checks, keeps the backend internal, uses
one replica per application, uses a `Recreate` rollout for both workloads, and
stores uploads with K3s's built-in `local-path` provisioner on the encrypted
EC2 root disk. The API autoscaler and disruption budget from the shared base
are deliberately removed: this low-scale test release must never create a
second API pod.

The frontend Nginx pod is also the public edge for this overlay. It applies
per-client-IP connection and request limits with no additional AWS service:

- normal API traffic: 15 requests/second with a burst of 30;
- storefront pages and static assets: 30 requests/second with a burst of 60;
- login/session creation: 5 POST requests/minute with a burst of 5;
- registration: 2 POST requests/minute with a burst of 2;
- verification resend and password-reset request: 3 POST requests/minute with
  a burst of 3;
- email-verification and password-reset token submission: 10 POST
  requests/minute with a burst of 10;
- checkout creation and Razorpay return verification: 5 requests/minute with
  a burst of 5;
- anonymous product lead capture: 5 requests/minute with a burst of 5;
- best-effort storefront view analytics: 30 requests/second with a burst of 60.

Storefront assets have a separate, larger budget so one page load does not
consume the API budget. Signed provider webhooks are excluded from per-IP
request limits because providers can share egress IPs; the 30-connections-per-IP
cap still applies. A rejected request receives HTTP `429`.
Authenticated session listing and revocation do not consume the login budget;
they continue to use the general authenticated API budget. `OPTIONS` requests
also do not consume identity-write budgets.
The storefront must treat a `429` from `POST /api/events/view` as a dropped
best-effort analytics event and continue loading normally.

These limits mitigate one abusive client or a small number of source addresses;
they are not a complete defense against a distributed denial-of-service attack.
Before a public production launch, put a managed edge such as CloudFront with
AWS WAF in front and keep the application edge reachable only from that trusted
path.

This client-IP policy is safe only for the current direct-to-EC2 topology. The
edge uses the socket peer (`$remote_addr`) and overwrites incoming
`X-Forwarded-For`; it never trusts a caller-supplied forwarding header. If an
ALB, CloudFront, Cloudflare, or another reverse proxy is added later, configure
Nginx `set_real_ip_from` with only that proxy's controlled source ranges before
using the forwarded address as the rate-limit key. Otherwise all visitors will
share the proxy's address and one visitor could exhaust the shared budget.

The deployment helper runs `nginx -t` in a temporary Pod made from the exact
immutable frontend image and these two configuration files before it changes
either application workload. The live verifier also checks normalized and
alternate spellings of the login, registration, uniqueness, checkout, and
payment-verification paths. From the operator machine it calls `/health` with a
spoofed forwarding header and confirms the edge-observed TCP peer is instead an
exact `/32` in the Terraform-managed security-group allowlist.

Render and apply through `scripts/deploy-aws-ephemeral.sh`. The checked-in YAML
contains placeholders instead of credentials or mutable image tags; the SSM
node helper replaces them only with exact image digests and the Terraform
public origin. Use only synthetic test credentials because this endpoint is
restricted HTTP.

Application/config rollout and Terraform state are independently pinned. The
deployer compares the applied infrastructure SHA to the existing SSM marker
and EC2 tag, while fetching this overlay and its node helper from a separate
exact manifest SHA. Do not overwrite Terraform's marker or tag to deploy a new
manifest revision.
