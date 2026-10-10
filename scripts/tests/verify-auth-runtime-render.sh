#!/usr/bin/env bash
set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/creator-store-auth-render.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

cp -R "$REPOSITORY_ROOT/k8s" "$TEMP_DIR/k8s"
for cloud in aws azure oci; do
  APP_PUBLIC_ORIGIN=https://dev.creators.example \
  APP_AUTH_EMAIL_FROM=security@creators.example \
  SMTP_HOST=smtp.creators.example \
  SMTP_PORT=2525 \
    "$REPOSITORY_ROOT/scripts/render-auth-runtime-patch.sh" \
      "$TEMP_DIR/k8s/overlays/$cloud/auth-runtime.yaml"
  kubectl kustomize "$TEMP_DIR/k8s/overlays/$cloud" > "$TEMP_DIR/$cloud.yaml"
  grep -q 'APP_ALLOWED_ORIGINS: https://dev.creators.example' "$TEMP_DIR/$cloud.yaml"
  grep -q 'APP_AUTH_PUBLIC_BASE_URL: https://dev.creators.example' "$TEMP_DIR/$cloud.yaml"
  grep -q 'APP_AUTH_EMAIL_FROM: security@creators.example' "$TEMP_DIR/$cloud.yaml"
  grep -q 'SMTP_HOST: smtp.creators.example' "$TEMP_DIR/$cloud.yaml"
  grep -q 'SMTP_PORT: "2525"' "$TEMP_DIR/$cloud.yaml"
  ! grep -q '\.invalid' "$TEMP_DIR/$cloud.yaml"
done

printf 'PASS  rendered authentication runtime for AWS, Azure, and OCI overlays\n'
