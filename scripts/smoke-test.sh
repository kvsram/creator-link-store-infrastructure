#!/usr/bin/env bash
set -euo pipefail

WEB_BASE_URL="${WEB_BASE_URL:-http://localhost:3000}"
API_BASE_URL="${API_BASE_URL:-http://localhost:8080}"
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

wait_for "$API_BASE_URL/health" "API"
wait_for "$WEB_BASE_URL/dashboard/" "web"

COOKIE_JAR="$(mktemp)"
trap 'rm -f "$COOKIE_JAR"' EXIT
SMOKE_HANDLE="smoke_$(date +%s)_$$"
SMOKE_EMAIL="${SMOKE_HANDLE}@example.test"
SMOKE_PASSWORD="LocalSmokeOnly123!"

health="$(curl --fail --silent --show-error "$API_BASE_URL/health")"
assert_contains "health contract" "$health" '"status":"ok"'

public_store="$(curl --fail --silent --show-error "$API_BASE_URL/api/public/alex")"
assert_contains "public demo creator" "$public_store" '"handle":"alex"'
assert_contains "public store uses INR" "$public_store" '"currency":"INR"'

unauthenticated_status="$(curl --silent --output /dev/null --write-out '%{http_code}' "$API_BASE_URL/api/v1/dashboard")"
test "$unauthenticated_status" = "401" || { printf 'FAIL  protected dashboard returned %s\n' "$unauthenticated_status" >&2; exit 1; }
printf 'PASS  protected dashboard rejects anonymous requests\n'

curl --fail --silent --show-error -H 'Content-Type: application/json' \
  --data "{\"handle\":\"$SMOKE_HANDLE\",\"displayName\":\"Smoke Creator\",\"email\":\"$SMOKE_EMAIL\",\"password\":\"$SMOKE_PASSWORD\"}" \
  "$API_BASE_URL/api/auth/register" >/dev/null
curl --fail --silent --show-error -c "$COOKIE_JAR" -H 'Content-Type: application/json' \
  --data "{\"handleOrEmail\":\"$SMOKE_EMAIL\",\"password\":\"$SMOKE_PASSWORD\"}" \
  "$API_BASE_URL/api/auth/login" >/dev/null

dashboard="$(curl --fail --silent --show-error -b "$COOKIE_JAR" "$API_BASE_URL/api/v1/dashboard?creatorId=1")"
assert_contains "dashboard contract" "$dashboard" '"checklist"'
assert_contains "session tenant overrides forged creatorId" "$dashboard" "Smoke Creator's Store"

store="$(curl --fail --silent --show-error -b "$COOKIE_JAR" "$API_BASE_URL/api/v1/store")"
assert_contains "new India store defaults to INR" "$store" '"currency":"INR"'

autodm_rule="$(curl --fail --silent --show-error -b "$COOKIE_JAR" -H 'Content-Type: application/json' \
  --data '{"instagramAccountId":"smoke-professional-account","mediaId":"smoke-media","keywords":["guide","link"],"matchMode":"any","replyText":"Here is your requested guide.","active":false}' \
  "$API_BASE_URL/api/v1/automations/instagram-comment-rules")"
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

printf '\nSmoke test passed. This proves the project contract documented in docs/FEATURE_PARITY.md; it does not prove private Stan response parity.\n'
