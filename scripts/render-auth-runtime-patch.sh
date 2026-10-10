#!/usr/bin/env bash
set -euo pipefail

PATCH_PATH="${1:-}"

: "${APP_PUBLIC_ORIGIN:?Set APP_PUBLIC_ORIGIN to the environment HTTPS origin}"
: "${APP_AUTH_EMAIL_FROM:?Set APP_AUTH_EMAIL_FROM to the verified sender address}"
: "${SMTP_HOST:?Set SMTP_HOST to the approved provider hostname}"
SMTP_PORT="${SMTP_PORT:-587}"
APP_PUBLIC_ORIGIN="${APP_PUBLIC_ORIGIN%/}"

fail() { printf 'FAIL  %s\n' "$1" >&2; exit 1; }

[[ "$APP_PUBLIC_ORIGIN" =~ ^https://[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?(:[0-9]{1,5})?$ ]] \
  || fail "APP_PUBLIC_ORIGIN must be one HTTPS origin without a path"
[[ "$APP_PUBLIC_ORIGIN" != *".invalid"* && "$APP_PUBLIC_ORIGIN" != *"localhost"* ]] \
  || fail "APP_PUBLIC_ORIGIN must be a deployable public origin"
[[ "$APP_AUTH_EMAIL_FROM" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] \
  || fail "APP_AUTH_EMAIL_FROM must be a valid sender address"
[[ "$APP_AUTH_EMAIL_FROM" != *".invalid" ]] \
  || fail "APP_AUTH_EMAIL_FROM still uses a fail-closed domain"
[[ "$SMTP_HOST" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] \
  || fail "SMTP_HOST must be a hostname"
[[ "$SMTP_HOST" != *".invalid" && "$SMTP_HOST" != "localhost" ]] \
  || fail "SMTP_HOST must be a deployable provider endpoint"
[[ "$SMTP_PORT" =~ ^[0-9]{1,5}$ ]] && (( SMTP_PORT >= 1 && SMTP_PORT <= 65535 )) \
  || fail "SMTP_PORT must be in the range 1-65535"
[ -n "$PATCH_PATH" ] || fail "pass the selected environment overlay auth-runtime.yaml path"
[ -f "$PATCH_PATH" ] || fail "authentication runtime patch is missing: $PATCH_PATH"

TEMP_FILE="$(mktemp "${TMPDIR:-/tmp}/creator-store-auth-runtime.XXXXXX")"
trap 'rm -f "$TEMP_FILE"' EXIT

awk -v origin="$APP_PUBLIC_ORIGIN" -v sender="$APP_AUTH_EMAIL_FROM" \
    -v smtp_host="$SMTP_HOST" -v smtp_port="$SMTP_PORT" '
  {
    gsub("https://app.creator-store.example.invalid", origin)
    gsub("no-reply@creator-store.example.invalid", sender)
    gsub("smtp.provider.example.invalid", smtp_host)
    if ($0 ~ /SMTP_PORT:/) sub(/"587"/, "\"" smtp_port "\"")
    print
  }
' "$PATCH_PATH" > "$TEMP_FILE"

if grep -q '\.invalid' "$TEMP_FILE"; then
  fail "authentication runtime patch still contains fail-closed values"
fi
mv "$TEMP_FILE" "$PATCH_PATH"
trap - EXIT
printf 'PASS  rendered nonsecret authentication runtime for %s\n' "$APP_PUBLIC_ORIGIN"
