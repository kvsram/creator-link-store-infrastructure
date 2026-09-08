#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  deploy-k3s-node.sh TEST_ID EXPECTED_ACCOUNT_ID INFRA_SHA BACKEND_SHA BACKEND_DIGEST FRONTEND_SHA FRONTEND_DIGEST [AWS_REGION]

This helper runs as root on the disposable K3s node through SSM Run Command.
It reads the database secret locally, deploys immutable images, and never prints
the database password.
EOF
}

fail() {
  printf 'FAIL  %s\n' "$*" >&2
  exit 1
}

if [ "$#" -lt 7 ] || [ "$#" -gt 8 ]; then
  usage >&2
  exit 2
fi

TEST_ID="$1"
EXPECTED_ACCOUNT_ID="$2"
INFRA_SHA="$3"
BACKEND_SHA="$4"
BACKEND_DIGEST="$5"
FRONTEND_SHA="$6"
FRONTEND_DIGEST="$7"
AWS_REGION="${8:-us-east-2}"
PARAMETER_PREFIX="/creator-store/ephemeral/$TEST_ID"
NAMESPACE="creator-store"
NODE_PORT="30080"
REPOSITORY_URL="https://github.com/kvsram/creator-link-store-infrastructure.git"

[ "$(id -u)" -eq 0 ] || fail "the node deployment helper must run as root"
[[ "$TEST_ID" =~ ^[a-z0-9-]{3,16}$ ]] || fail "invalid TEST_ID"
[[ "$EXPECTED_ACCOUNT_ID" =~ ^[0-9]{12}$ ]] || fail "invalid EXPECTED_ACCOUNT_ID"
[[ "$AWS_REGION" == "us-east-2" ]] || fail "the disposable deployment is locked to us-east-2"

for release_sha in "$INFRA_SHA" "$BACKEND_SHA" "$FRONTEND_SHA"; do
  [[ "$release_sha" =~ ^[0-9a-f]{40}$ ]] || fail "each source SHA must contain 40 lowercase hexadecimal characters"
done
for image_digest in "$BACKEND_DIGEST" "$FRONTEND_DIGEST"; do
  [[ "$image_digest" =~ ^sha256:[0-9a-f]{64}$ ]] || fail "each image digest must use sha256:<64 lowercase hex>"
done
# SSM can become Online before cloud-init finishes installing Git, jq, and K3s.
# Wait for the bootstrap marker before validating those dependencies so an early
# Run Command waits safely instead of failing during the short startup race.
for ((attempt = 1; attempt <= 180; attempt++)); do
  if [ -f /var/lib/creator-store/bootstrap-complete ] && \
    command -v k3s >/dev/null 2>&1 && \
    k3s kubectl get --raw=/readyz >/dev/null 2>&1; then
    break
  fi
  if [ "$attempt" -eq 180 ]; then
    systemctl status k3s --no-pager || true
    fail "K3s bootstrap did not become ready within 15 minutes"
  fi
  sleep 5
done

for command_name in aws curl git grep jq k3s mktemp rm sed seq sha256sum; do
  command -v "$command_name" >/dev/null 2>&1 || fail "missing required command after bootstrap: $command_name"
done

METADATA_TOKEN="$(curl --fail --silent --show-error --request PUT \
  --header 'X-aws-ec2-metadata-token-ttl-seconds: 60' \
  http://169.254.169.254/latest/api/token)"
IDENTITY_DOCUMENT="$(curl --fail --silent --show-error \
  --header "X-aws-ec2-metadata-token: $METADATA_TOKEN" \
  http://169.254.169.254/latest/dynamic/instance-identity/document)"
ACTUAL_ACCOUNT_ID="$(jq -r '.accountId' <<< "$IDENTITY_DOCUMENT")"
ACTUAL_INSTANCE_ID="$(jq -r '.instanceId' <<< "$IDENTITY_DOCUMENT")"
ACTUAL_REGION="$(jq -r '.region' <<< "$IDENTITY_DOCUMENT")"
unset METADATA_TOKEN IDENTITY_DOCUMENT

[ "$ACTUAL_ACCOUNT_ID" = "$EXPECTED_ACCOUNT_ID" ] || fail "instance account guard failed"
[ "$ACTUAL_REGION" = "$AWS_REGION" ] || fail "instance region guard failed"
[[ "$ACTUAL_INSTANCE_ID" =~ ^i-[0-9a-f]+$ ]] || fail "instance identity document returned an invalid instance ID"

get_parameter() {
  local name="$1"
  local decrypt="${2:-false}"
  local decrypt_argument=()
  if [ "$decrypt" = "true" ]; then
    decrypt_argument=(--with-decryption)
  fi
  aws ssm get-parameter \
    --region "$AWS_REGION" \
    --name "$PARAMETER_PREFIX/$name" \
    "${decrypt_argument[@]}" \
    --query 'Parameter.Value' \
    --output text
}

DEPLOYED_INSTANCE_ID="$(get_parameter k3s-instance-id)"
DEPLOYED_INFRA_SHA="$(get_parameter infrastructure-release)"
K3S_VERSION="$(get_parameter k3s-version)"
PUBLIC_ORIGIN="$(get_parameter public-origin)"
EXPIRES_AT="$(get_parameter expires-at)"

[ "$DEPLOYED_INSTANCE_ID" = "$ACTUAL_INSTANCE_ID" ] || fail "SSM instance marker does not match this node"
[ "$DEPLOYED_INFRA_SHA" = "$INFRA_SHA" ] || fail "SSM infrastructure marker does not match the requested SHA"
[[ "$K3S_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+\+k3s[0-9]+$ ]] || fail "SSM returned an invalid K3s version"
[[ "$PUBLIC_ORIGIN" =~ ^http://([0-9]{1,3}\.){3}[0-9]{1,3}:30080$ ]] || fail "SSM returned an invalid public origin"
[ -n "$EXPIRES_AT" ] && [ "$EXPIRES_AT" != "None" ] || fail "expiration marker is missing"

grep -Fxq "$K3S_VERSION" /var/lib/creator-store/bootstrap-complete || \
  fail "K3s bootstrap marker does not match the requested version"

RELEASE_DIR="$(mktemp -d /var/tmp/creator-store-release.XXXXXX)"
cleanup() {
  unset DB_PASSWORD || true
  if [[ "${RELEASE_DIR:-}" == /var/tmp/creator-store-release.* ]] && [ -d "$RELEASE_DIR" ]; then
    rm -rf -- "$RELEASE_DIR"
  fi
}
trap cleanup EXIT
umask 077

git -c advice.detachedHead=false clone --quiet --filter=blob:none --no-checkout \
  "$REPOSITORY_URL" "$RELEASE_DIR/infrastructure"
git -C "$RELEASE_DIR/infrastructure" fetch --quiet --depth=1 origin "$INFRA_SHA"
git -C "$RELEASE_DIR/infrastructure" checkout --quiet --detach FETCH_HEAD
ACTUAL_INFRA_SHA="$(git -C "$RELEASE_DIR/infrastructure" rev-parse HEAD)"
[ "$ACTUAL_INFRA_SHA" = "$INFRA_SHA" ] || fail "fetched infrastructure checkout does not match the requested SHA"

DB_URL="$(get_parameter database-url)"
DB_USER="$(get_parameter database-username)"
DB_PASSWORD="$(get_parameter database-password true)"
[ -n "$DB_URL" ] && [ "$DB_URL" != "None" ] || fail "database URL is missing"
[ -n "$DB_USER" ] && [ "$DB_USER" != "None" ] || fail "database username is missing"
[ -n "$DB_PASSWORD" ] && [ "$DB_PASSWORD" != "None" ] || fail "database password is missing"

k3s kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml \
  | k3s kubectl apply -f - >/dev/null

DB_ENV_FILE="$RELEASE_DIR/database.env"
{
  printf 'DB_URL=%s\n' "$DB_URL"
  printf 'DB_USER=%s\n' "$DB_USER"
  printf 'DB_PASSWORD=%s\n' "$DB_PASSWORD"
} > "$DB_ENV_FILE"
unset DB_URL DB_USER DB_PASSWORD

k3s kubectl -n "$NAMESPACE" create secret generic creator-store-runtime-secrets \
  --from-env-file="$DB_ENV_FILE" \
  --dry-run=client -o yaml \
  | k3s kubectl apply -f - >/dev/null
rm -f -- "$DB_ENV_FILE"

BACKEND_IMAGE="ghcr.io/kvsram/creator-link-store-backend@$BACKEND_DIGEST"
FRONTEND_IMAGE="ghcr.io/kvsram/creator-link-store-frontend@$FRONTEND_DIGEST"
k3s kubectl kustomize "$RELEASE_DIR/infrastructure/k8s/overlays/aws-ephemeral" \
  > "$RELEASE_DIR/source.yaml"
sed \
  -e "s#ghcr.io/kvsram/creator-link-store-backend:replace-with-sha#$BACKEND_IMAGE#g" \
  -e "s#ghcr.io/kvsram/creator-link-store-frontend:replace-with-sha#$FRONTEND_IMAGE#g" \
  -e "s#http://replace-with-worker-ip:30080#$PUBLIC_ORIGIN#g" \
  -e "s#replace-with-test-id#$TEST_ID#g" \
  -e "s#replace-with-expires-at#$EXPIRES_AT#g" \
  "$RELEASE_DIR/source.yaml" > "$RELEASE_DIR/release.yaml"

if grep -Eq 'replace-with|ghcr.io/kvsram/creator-link-store-(backend|frontend):' "$RELEASE_DIR/release.yaml"; then
  fail "rendered release still contains a placeholder or mutable image tag"
fi
[ "$(grep -Fc "$BACKEND_IMAGE" "$RELEASE_DIR/release.yaml")" -eq 1 ] || fail "rendered release does not contain the requested backend digest exactly once"
[ "$(grep -Fc "$FRONTEND_IMAGE" "$RELEASE_DIR/release.yaml")" -eq 1 ] || fail "rendered release does not contain the requested frontend digest exactly once"

k3s kubectl apply --dry-run=server -f "$RELEASE_DIR/release.yaml" >/dev/null
k3s kubectl apply -f "$RELEASE_DIR/release.yaml"

for attempt in $(seq 1 120); do
  PVC_STATE="$(k3s kubectl -n "$NAMESPACE" get pvc creator-store-uploads \
    -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  if [ "$PVC_STATE" = "Bound" ]; then
    break
  fi
  if [ "$attempt" -eq 120 ]; then
    k3s kubectl -n "$NAMESPACE" describe pvc creator-store-uploads || true
    fail "uploads PVC did not become Bound within 10 minutes"
  fi
  sleep 5
done

k3s kubectl -n "$NAMESPACE" rollout status deployment/creator-store-api --timeout=10m
k3s kubectl -n "$NAMESPACE" rollout status deployment/creator-store-web --timeout=7m

DEPLOYED_BACKEND_IMAGE="$(k3s kubectl -n "$NAMESPACE" get deployment creator-store-api \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="api")].image}')"
DEPLOYED_FRONTEND_IMAGE="$(k3s kubectl -n "$NAMESPACE" get deployment creator-store-web \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="web")].image}')"
[ "$DEPLOYED_BACKEND_IMAGE" = "$BACKEND_IMAGE" ] || fail "live backend image does not match the requested digest"
[ "$DEPLOYED_FRONTEND_IMAGE" = "$FRONTEND_IMAGE" ] || fail "live frontend image does not match the requested digest"

k3s kubectl -n "$NAMESPACE" create configmap creator-store-release \
  --from-literal=infrastructure_sha="$INFRA_SHA" \
  --from-literal=backend_sha="$BACKEND_SHA" \
  --from-literal=backend_digest="$BACKEND_DIGEST" \
  --from-literal=frontend_sha="$FRONTEND_SHA" \
  --from-literal=frontend_digest="$FRONTEND_DIGEST" \
  --from-literal=public_origin="$PUBLIC_ORIGIN" \
  --from-literal=expires_at="$EXPIRES_AT" \
  --dry-run=client -o yaml \
  | k3s kubectl apply -f - >/dev/null

curl --fail --silent --show-error --retry 20 --retry-delay 3 \
  "http://127.0.0.1:$NODE_PORT/dashboard/" >/dev/null
API_BODY="$(curl --fail --silent --show-error --retry 20 --retry-delay 3 \
  "http://127.0.0.1:$NODE_PORT/api/public/alex")"
grep -Fq '"handle":"alex"' <<< "$API_BODY"

k3s kubectl -n "$NAMESPACE" get deployment,pod,service,persistentvolumeclaim
printf '\nDeployment passed on %s with K3s %s.\n' "$ACTUAL_INSTANCE_ID" "$K3S_VERSION"
printf 'Temporary URL: %s\nMandatory teardown deadline: %s\n' "$PUBLIC_ORIGIN" "$EXPIRES_AT"
