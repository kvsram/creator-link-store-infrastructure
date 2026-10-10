#!/usr/bin/env bash
set -euo pipefail

API_BASE_URL="${API_BASE_URL:-http://localhost:8080}"
BROWSER_ORIGIN="${BROWSER_ORIGIN:-http://localhost:3000}"
MAILPIT_BASE_URL="${MAILPIT_BASE_URL:-http://localhost:8025}"
ATTEMPTS="${AUTH_SMOKE_ATTEMPTS:-60}"
COOKIE_JAR="$(mktemp)"
trap 'rm -f "$COOKIE_JAR"' EXIT

pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1" >&2; exit 1; }

wait_for() {
  local url="$1" label="$2" attempt
  for ((attempt=1; attempt<=ATTEMPTS; attempt++)); do
    if curl --fail --silent --show-error "$url" >/dev/null 2>&1; then
      pass "$label is reachable"
      return
    fi
    sleep 1
  done
  fail "$label did not become ready"
}

fetch_csrf() {
  local response
  response="$(curl --fail --silent --show-error -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
    "$API_BASE_URL/api/v1/auth/csrf")"
  CSRF_TOKEN="$(printf '%s' "$response" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')"
  CSRF_HEADER_NAME="$(printf '%s' "$response" | sed -n 's/.*"headerName":"\([^"]*\)".*/\1/p')"
  [ -n "$CSRF_TOKEN" ] && [ -n "$CSRF_HEADER_NAME" ] || fail "CSRF bootstrap failed"
}

request_json() {
  local method="$1" path="$2" payload="${3:-}"
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
  local label="$1" expected="$2"
  [ "$HTTP_STATUS" = "$expected" ] || fail "$label returned HTTP $HTTP_STATUS"
  pass "$label"
}

assert_contains() {
  local label="$1" expected="$2"
  printf '%s' "$HTTP_BODY" | grep -Fq "$expected" || fail "$label returned an unexpected body"
  pass "$label"
}

wait_for_mail_token() {
  local route="$1" label="$2" attempt body
  MAIL_TOKEN=""
  for ((attempt=1; attempt<=ATTEMPTS; attempt++)); do
    body="$(curl --silent --show-error --get \
      --data-urlencode "query=to:$SMOKE_EMAIL" \
      "$MAILPIT_BASE_URL/view/latest.txt" 2>/dev/null || true)"
    # The test may run on a non-default local port. Match the route and token while the exact
    # public origin remains enforced by the API configuration and browser CORS checks.
    # Current links place the credential in a URL fragment so it never reaches HTTP access logs.
    # Accept query links too so the smoke test can validate an in-place upgrade with older mail.
    MAIL_TOKEN="$(printf '%s\n' "$body" | sed -nE \
      "s#.*/${route}[?#]token=([A-Za-z0-9_-]+).*#\\1#p" | head -n 1)"
    if [ -n "$MAIL_TOKEN" ]; then
      pass "$label arrived in Mailpit"
      return
    fi
    sleep 1
  done
  fail "$label did not arrive for the synthetic account"
}

wait_for "$API_BASE_URL/health" "API"
wait_for "$MAILPIT_BASE_URL/readyz" "Mailpit"

RUN_KEY="$(date +%s)_$$"
SMOKE_HANDLE="auth_$RUN_KEY"
SMOKE_EMAIL="$SMOKE_HANDLE@example.test"
SMOKE_PASSWORD="LocalAuthOnly123!"
SMOKE_NEW_PASSWORD="LocalAuthReset123!"

fetch_csrf
request_json POST /api/v1/auth/registrations \
  "{\"handle\":\"$SMOKE_HANDLE\",\"displayName\":\"Auth Smoke Creator\",\"email\":\"$SMOKE_EMAIL\",\"password\":\"$SMOKE_PASSWORD\"}"
assert_status "registration accepted" 202
assert_contains "registration requires verification" '"verificationRequired":true'

wait_for_mail_token verify-email "verification email"
request_json POST /api/v1/auth/email-verifications "{\"token\":\"$MAIL_TOKEN\"}"
assert_status "email verified" 200

me_status="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
  -b "$COOKIE_JAR" "$API_BASE_URL/api/v1/auth/me")"
[ "$me_status" = "200" ] || fail "verified session could not read /me"
pass "verified session can read /me"

fetch_csrf
request_json DELETE /api/v1/auth/sessions/current
assert_status "logout revokes the session" 200
me_status="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
  -b "$COOKIE_JAR" "$API_BASE_URL/api/v1/auth/me")"
[ "$me_status" = "401" ] || fail "logged-out session still reached /me"
pass "logged-out session is rejected"

fetch_csrf
request_json POST /api/v1/auth/sessions \
  "{\"handleOrEmail\":\"$SMOKE_EMAIL\",\"password\":\"$SMOKE_PASSWORD\"}"
assert_status "verified account can log in" 200

fetch_csrf
request_json POST /api/v1/auth/password-reset-requests "{\"email\":\"$SMOKE_EMAIL\"}"
assert_status "password reset request accepted" 202
assert_contains "password reset response is generic" '"accepted":true'

wait_for_mail_token reset-password "password reset email"
RESET_TOKEN="$MAIL_TOKEN"
# Authentication state can rotate the CSRF cookie. Re-bootstrap before the next browser mutation,
# matching the frontend client's automatic one-time refresh behavior.
fetch_csrf
request_json POST /api/v1/auth/password-resets \
  "{\"token\":\"$RESET_TOKEN\",\"newPassword\":\"$SMOKE_NEW_PASSWORD\"}"
assert_status "password reset completed" 200

me_status="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
  -b "$COOKIE_JAR" "$API_BASE_URL/api/v1/auth/me")"
[ "$me_status" = "401" ] || fail "password reset did not revoke the old session"
pass "password reset revokes the old session"

fetch_csrf
request_json POST /api/v1/auth/sessions \
  "{\"handleOrEmail\":\"$SMOKE_EMAIL\",\"password\":\"$SMOKE_PASSWORD\"}"
assert_status "old password is rejected" 401
request_json POST /api/v1/auth/sessions \
  "{\"handleOrEmail\":\"$SMOKE_EMAIL\",\"password\":\"$SMOKE_NEW_PASSWORD\"}"
assert_status "new password is accepted" 200

fetch_csrf
request_json POST /api/v1/auth/password-resets \
  "{\"token\":\"$RESET_TOKEN\",\"newPassword\":\"$SMOKE_PASSWORD\"}"
assert_status "reset token replay is rejected" 400

printf '\nAuthentication smoke test passed for one synthetic local account.\n'
