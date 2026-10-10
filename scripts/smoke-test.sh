#!/usr/bin/env bash
set -euo pipefail

WEB_BASE_URL="${WEB_BASE_URL:-http://localhost:3000}"
API_BASE_URL="${API_BASE_URL:-http://localhost:8080}"
BROWSER_ORIGIN="${BROWSER_ORIGIN:-$WEB_BASE_URL}"
MAILPIT_BASE_URL="${MAILPIT_BASE_URL:-http://localhost:8025}"
ATTEMPTS="${SMOKE_ATTEMPTS:-60}"
EXPECTED_PAYMENTS_MODE="${EXPECTED_PAYMENTS_MODE:-disabled}"
EXPECTED_INSTAGRAM_MODE="${EXPECTED_INSTAGRAM_MODE:-disabled}"

wait_for() {
  local url="$1"
  local label="$2"
  local attempt
  for ((attempt=1; attempt<=ATTEMPTS; attempt++)); do
    if curl --fail --silent --show-error "$url" >/dev/null 2>&1; then
      printf 'PASS  %s is reachable\n' "$label"
      return
    fi
    sleep 2
  done
  printf 'FAIL  %s did not become ready: %s\n' "$label" "$url" >&2
  exit 1
}

assert_contains() {
  local label="$1"
  local body="$2"
  local expected="$3"
  if printf '%s' "$body" | grep -Fq "$expected"; then
    printf 'PASS  %s\n' "$label"
  else
    printf 'FAIL  %s: response did not contain %s\n' "$label" "$expected" >&2
    exit 1
  fi
}

fetch_csrf() {
  local response
  response="$(curl --fail --silent --show-error -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
    "$API_BASE_URL/api/v1/auth/csrf")"
  CSRF_TOKEN="$(printf '%s' "$response" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')"
  CSRF_HEADER_NAME="$(printf '%s' "$response" | sed -n 's/.*"headerName":"\([^"]*\)".*/\1/p')"
  [ -n "$CSRF_TOKEN" ] && [ -n "$CSRF_HEADER_NAME" ] || {
    printf 'FAIL  CSRF bootstrap returned an unexpected response\n' >&2
    exit 1
  }
}

request_json() {
  local method="$1"
  local path="$2"
  local payload="${3:-}"
  local curl_args=(--silent --show-error -b "$COOKIE_JAR" -c "$COOKIE_JAR"
    --request "$method" -H "Origin: $BROWSER_ORIGIN"
    -H "$CSRF_HEADER_NAME: $CSRF_TOKEN" --write-out $'\n%{http_code}')
  if [ -n "$payload" ]; then
    curl_args+=(-H 'Content-Type: application/json' --data "$payload")
  fi
  HTTP_RESPONSE="$(curl "${curl_args[@]}" "$API_BASE_URL$path")"
  HTTP_STATUS="${HTTP_RESPONSE##*$'\n'}"
  HTTP_BODY="${HTTP_RESPONSE%$'\n'*}"
}

assert_status() {
  local label="$1"
  local expected="$2"
  if [ "$HTTP_STATUS" = "$expected" ]; then
    printf 'PASS  %s\n' "$label"
  else
    printf 'FAIL  %s returned HTTP %s instead of %s: %s\n' \
      "$label" "$HTTP_STATUS" "$expected" "$HTTP_BODY" >&2
    exit 1
  fi
}

wait_for_mail_token() {
  local route="$1"
  local label="$2"
  local attempt body
  MAIL_TOKEN=""
  for ((attempt=1; attempt<=ATTEMPTS; attempt++)); do
    body="$(curl --silent --show-error --get \
      --data-urlencode "query=to:$SMOKE_EMAIL" \
      "$MAILPIT_BASE_URL/view/latest.txt" 2>/dev/null || true)"
    MAIL_TOKEN="$(printf '%s\n' "$body" | sed -nE \
      "s#.*http://localhost:3000/${route}\\?token=([A-Za-z0-9_-]+).*#\\1#p" | head -n 1)"
    if [ -n "$MAIL_TOKEN" ]; then
      printf 'PASS  %s arrived in Mailpit\n' "$label"
      return
    fi
    sleep 1
  done
  printf 'FAIL  %s did not arrive for %s\n' "$label" "$SMOKE_EMAIL" >&2
  exit 1
}

wait_for "$API_BASE_URL/health" "API"
wait_for "$WEB_BASE_URL/dashboard/" "web"
wait_for "$MAILPIT_BASE_URL/readyz" "Mailpit"

COOKIE_JAR="$(mktemp)"
trap 'rm -f "$COOKIE_JAR"' EXIT
SMOKE_HANDLE="smoke_$(date +%s)_$$"
SMOKE_EMAIL="${SMOKE_HANDLE}@example.test"
SMOKE_PASSWORD="LocalSmokeOnly123!"
SMOKE_NEW_PASSWORD="LocalSmokeReset123!"

health="$(curl --fail --silent --show-error "$API_BASE_URL/health")"
assert_contains "health contract" "$health" '"status":"ok"'

public_store="$(curl --fail --silent --show-error "$API_BASE_URL/api/public/alex")"
assert_contains "public demo creator" "$public_store" '"handle":"alex"'
assert_contains "public store uses INR" "$public_store" '"currency":"INR"'

unauthenticated_status="$(curl --silent --output /dev/null --write-out '%{http_code}' "$API_BASE_URL/api/v1/dashboard")"
test "$unauthenticated_status" = "401" || { printf 'FAIL  protected dashboard returned %s\n' "$unauthenticated_status" >&2; exit 1; }
printf 'PASS  protected dashboard rejects anonymous requests\n'

fetch_csrf
request_json POST /api/v1/auth/registrations \
  "{\"handle\":\"$SMOKE_HANDLE\",\"displayName\":\"Smoke Creator\",\"email\":\"$SMOKE_EMAIL\",\"password\":\"$SMOKE_PASSWORD\"}"
assert_status "registration is accepted without creating a session" 202
assert_contains "registration requires verification" "$HTTP_BODY" '"verificationRequired":true'

request_json POST /api/v1/auth/sessions \
  "{\"handleOrEmail\":\"$SMOKE_EMAIL\",\"password\":\"$SMOKE_PASSWORD\"}"
assert_status "unverified account cannot sign in" 403

wait_for_mail_token verify-email "verification email"
request_json POST /api/v1/auth/email-verifications "{\"token\":\"$MAIL_TOKEN\"}"
assert_status "verification consumes the email token and authenticates" 200
assert_contains "verified account is active" "$HTTP_BODY" '"emailVerified":true'

fetch_csrf
request_json DELETE /api/v1/auth/sessions/current
assert_status "logout revokes the current session" 200
fetch_csrf
request_json POST /api/v1/auth/sessions \
  "{\"handleOrEmail\":\"$SMOKE_EMAIL\",\"password\":\"$SMOKE_PASSWORD\"}"
assert_status "verified account can sign in" 200
printf 'PASS  configured browser origin can complete signup, verification, logout, and login\n'

dashboard="$(curl --fail --silent --show-error -b "$COOKIE_JAR" "$API_BASE_URL/api/v1/dashboard?creatorId=1")"
assert_contains "dashboard contract" "$dashboard" '"checklist"'
assert_contains "session tenant overrides forged creatorId" "$dashboard" "Smoke Creator's Store"

store="$(curl --fail --silent --show-error -b "$COOKIE_JAR" "$API_BASE_URL/api/v1/store")"
assert_contains "new India store defaults to INR" "$store" '"currency":"INR"'

fetch_csrf
request_json POST /api/v1/automations/instagram-comment-rules \
  '{"instagramAccountId":"smoke-professional-account","mediaId":"smoke-media","keywords":["guide","link"],"matchMode":"any","replyText":"Here is your requested guide.","active":false}'
assert_status "inactive AutoDM rule can be submitted safely" 201
autodm_rule="$HTTP_BODY"
assert_contains "inactive AutoDM rule can be persisted safely" "$autodm_rule" '"created":true'
autodm_rules="$(curl --fail --silent --show-error -b "$COOKIE_JAR" "$API_BASE_URL/api/v1/automations/instagram-comment-rules")"
assert_contains "AutoDM rule is scoped to authenticated creator" "$autodm_rules" '"media_id":"smoke-media"'

payments="$(curl --fail --silent --show-error "$API_BASE_URL/api/v1/payments/config")"
assert_contains "payment boundary is explicit" "$payments" '"real_money":true'
assert_contains "expected local payment mode" "$payments" "\"mode\":\"$EXPECTED_PAYMENTS_MODE\""

instagram="$(curl --fail --silent --show-error "$API_BASE_URL/api/v1/integrations/instagram/config")"
assert_contains "Instagram boundary is explicit" "$instagram" '"external_service":true'
assert_contains "expected local Instagram mode" "$instagram" "\"mode\":\"$EXPECTED_INSTAGRAM_MODE\""

if [ "$EXPECTED_PAYMENTS_MODE" = "disabled" ]; then
  checkout_response="$(curl --silent --show-error --write-out $'\n%{http_code}' \
    -H 'Content-Type: application/json' \
    -H 'Idempotency-Key: local-disabled-smoke-check' \
    --data '{"creatorId":1,"productId":1,"provider":"razorpay"}' \
    "$API_BASE_URL/api/v1/checkout/sessions")"
  checkout_status="${checkout_response##*$'\n'}"
  checkout_body="${checkout_response%$'\n'*}"
  if [ "$checkout_status" != "503" ]; then
    printf 'FAIL  disabled checkout returned HTTP %s instead of 503\n' "$checkout_status" >&2
    exit 1
  fi
  assert_contains "disabled checkout cannot create a charge" "$checkout_body" 'no charge was attempted'
else
  printf 'SKIP  checkout creation is side-effecting in %s mode; use the provider sandbox runbook\n' "$EXPECTED_PAYMENTS_MODE"
fi

admin_html="$(curl --fail --silent --show-error "$WEB_BASE_URL/dashboard/")"
assert_contains "admin SPA is served" "$admin_html" '<div id="root"></div>'

fetch_csrf
request_json POST /api/v1/auth/password-reset-requests "{\"email\":\"$SMOKE_EMAIL\"}"
assert_status "password reset request is accepted generically" 202
assert_contains "password reset response does not expose account details" "$HTTP_BODY" '"accepted":true'
wait_for_mail_token reset-password "password reset email"
RESET_TOKEN="$MAIL_TOKEN"
request_json POST /api/v1/auth/password-resets \
  "{\"token\":\"$RESET_TOKEN\",\"newPassword\":\"$SMOKE_NEW_PASSWORD\"}"
assert_status "password reset consumes the one-time token" 200

session_status="$(curl --silent --output /dev/null --write-out '%{http_code}' \
  -b "$COOKIE_JAR" "$API_BASE_URL/api/v1/auth/me")"
test "$session_status" = "401" || {
  printf 'FAIL  password reset did not revoke the pre-reset session (HTTP %s)\n' "$session_status" >&2
  exit 1
}
printf 'PASS  password reset revokes pre-reset sessions\n'

fetch_csrf
request_json POST /api/v1/auth/sessions \
  "{\"handleOrEmail\":\"$SMOKE_EMAIL\",\"password\":\"$SMOKE_PASSWORD\"}"
assert_status "old password fails after reset" 401
request_json POST /api/v1/auth/sessions \
  "{\"handleOrEmail\":\"$SMOKE_EMAIL\",\"password\":\"$SMOKE_NEW_PASSWORD\"}"
assert_status "new password succeeds after reset" 200
fetch_csrf
request_json POST /api/v1/auth/password-resets \
  "{\"token\":\"$RESET_TOKEN\",\"newPassword\":\"$SMOKE_PASSWORD\"}"
assert_status "consumed reset token cannot be replayed" 400

printf '\nSmoke test passed, including the Mailpit-backed authentication lifecycle. This proves the project contract documented in docs/FEATURE_PARITY.md; it does not prove private Stan response parity.\n'
