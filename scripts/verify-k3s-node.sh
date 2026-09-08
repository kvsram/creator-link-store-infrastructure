#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  verify-k3s-node.sh TEST_ID EXPECTED_ACCOUNT_ID INFRA_SHA BACKEND_DIGEST FRONTEND_DIGEST [AWS_REGION]

Runs read-only workload checks locally on the K3s node through SSM.
EOF
}

fail() {
  printf 'FAIL  %s\n' "$*" >&2
  exit 1
}

pass() {
  printf 'PASS  %s\n' "$*"
}

assert_equal() {
  local label="$1"
  local actual="$2"
  local expected="$3"
  [ "$actual" = "$expected" ] || fail "$label: expected '$expected', found '$actual'"
  pass "$label is $expected"
}

if [ "$#" -lt 5 ] || [ "$#" -gt 6 ]; then
  usage >&2
  exit 2
fi

TEST_ID="$1"
EXPECTED_ACCOUNT_ID="$2"
INFRA_SHA="$3"
BACKEND_DIGEST="$4"
FRONTEND_DIGEST="$5"
AWS_REGION="${6:-us-east-2}"
PARAMETER_PREFIX="/creator-store/ephemeral/$TEST_ID"
NAMESPACE="creator-store"
NODE_PORT="30080"
BACKEND_IMAGE="ghcr.io/kvsram/creator-link-store-backend@$BACKEND_DIGEST"
FRONTEND_IMAGE="ghcr.io/kvsram/creator-link-store-frontend@$FRONTEND_DIGEST"

[ "$(id -u)" -eq 0 ] || fail "node verification must run as root"
[[ "$TEST_ID" =~ ^[a-z0-9-]{3,16}$ ]] || fail "invalid TEST_ID"
[[ "$EXPECTED_ACCOUNT_ID" =~ ^[0-9]{12}$ ]] || fail "invalid EXPECTED_ACCOUNT_ID"
[[ "$INFRA_SHA" =~ ^[0-9a-f]{40}$ ]] || fail "invalid infrastructure SHA"
[[ "$BACKEND_DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]] || fail "invalid backend digest"
[[ "$FRONTEND_DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]] || fail "invalid frontend digest"
[[ "$AWS_REGION" == "us-east-2" ]] || fail "the disposable verification is locked to us-east-2"
for command_name in aws curl grep jq k3s stat; do
  command -v "$command_name" >/dev/null 2>&1 || fail "missing required command: $command_name"
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
assert_equal "instance account" "$ACTUAL_ACCOUNT_ID" "$EXPECTED_ACCOUNT_ID"
assert_equal "instance region" "$ACTUAL_REGION" "$AWS_REGION"

get_parameter() {
  aws ssm get-parameter \
    --region "$AWS_REGION" \
    --name "$PARAMETER_PREFIX/$1" \
    --query 'Parameter.Value' \
    --output text
}

assert_equal "SSM instance marker" "$(get_parameter k3s-instance-id)" "$ACTUAL_INSTANCE_ID"
assert_equal "SSM infrastructure marker" "$(get_parameter infrastructure-release)" "$INFRA_SHA"
K3S_VERSION="$(get_parameter k3s-version)"
PUBLIC_ORIGIN="$(get_parameter public-origin)"
[[ "$K3S_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+\+k3s[0-9]+$ ]] || fail "invalid K3s version marker"
[[ "$PUBLIC_ORIGIN" =~ ^http://([0-9]{1,3}\.){3}[0-9]{1,3}:30080$ ]] || fail "invalid public origin marker"
pass "SSM public origin is structurally valid"

[ -f /var/lib/creator-store/bootstrap-complete ] || fail "K3s bootstrap marker is absent"
assert_equal "bootstrap K3s version" "$(cat /var/lib/creator-store/bootstrap-complete)" "$K3S_VERSION"
assert_equal "K3s config mode" "$(stat -c '%a' /etc/rancher/k3s/config.yaml)" "600"
grep -Fxq 'secrets-encryption: true' /etc/rancher/k3s/config.yaml || fail "K3s secrets encryption is not configured"
grep -Fxq 'cluster-cidr: "10.244.0.0/16"' /etc/rancher/k3s/config.yaml || fail "K3s pod CIDR is not the reviewed value"
grep -Fxq 'service-cidr: "10.245.0.0/16"' /etc/rancher/k3s/config.yaml || fail "K3s service CIDR is not the reviewed value"
grep -Fxq 'cluster-dns: "10.245.0.10"' /etc/rancher/k3s/config.yaml || fail "K3s DNS address is not the reviewed value"
pass "K3s configuration has encrypted secrets and non-overlapping CIDRs"

k3s kubectl get --raw=/readyz >/dev/null
pass "Kubernetes API is ready locally"

NODE_DESCRIPTION="$(k3s kubectl get nodes \
  -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.conditions[?(@.type=="Ready")].status}{" "}{.spec.podCIDR}{"\n"}{end}')"
[ "$(printf '%s\n' "$NODE_DESCRIPTION" | grep -c .)" -eq 1 ] || fail "expected exactly one K3s node"
read -r NODE_NAME NODE_READY NODE_POD_CIDR <<< "$NODE_DESCRIPTION"
assert_equal "K3s node readiness" "$NODE_READY" "True"
[[ "$NODE_POD_CIDR" == 10.244.* ]] || fail "node pod CIDR is outside 10.244.0.0/16"
pass "single K3s node $NODE_NAME uses the reviewed pod network"

for deployment_name in creator-store-api creator-store-web; do
  k3s kubectl -n "$NAMESPACE" wait --for=condition=Available \
    "deployment/$deployment_name" --timeout=30s >/dev/null
  DEPLOYMENT_REPLICAS="$(k3s kubectl -n "$NAMESPACE" get deployment "$deployment_name" \
    -o jsonpath='{.spec.replicas}{" "}{.status.updatedReplicas}{" "}{.status.availableReplicas}')"
  read -r DESIRED_REPLICAS UPDATED_REPLICAS AVAILABLE_REPLICAS <<< "$DEPLOYMENT_REPLICAS"
  assert_equal "$deployment_name desired replicas" "$DESIRED_REPLICAS" "1"
  assert_equal "$deployment_name updated replicas" "$UPDATED_REPLICAS" "1"
  assert_equal "$deployment_name available replicas" "$AVAILABLE_REPLICAS" "1"
done

API_SERVICE_TYPE="$(k3s kubectl -n "$NAMESPACE" get service creator-store-api -o jsonpath='{.spec.type}')"
WEB_SERVICE_DESCRIPTION="$(k3s kubectl -n "$NAMESPACE" get service creator-store-web \
  -o jsonpath='{.spec.type}{" "}{.spec.ports[?(@.name=="http")].nodePort}{" "}{.spec.externalTrafficPolicy}')"
read -r WEB_SERVICE_TYPE WEB_NODE_PORT WEB_TRAFFIC_POLICY <<< "$WEB_SERVICE_DESCRIPTION"
assert_equal "API Service type" "$API_SERVICE_TYPE" "ClusterIP"
assert_equal "web Service type" "$WEB_SERVICE_TYPE" "NodePort"
assert_equal "web NodePort" "$WEB_NODE_PORT" "$NODE_PORT"
assert_equal "web external traffic policy" "$WEB_TRAFFIC_POLICY" "Local"

PVC_DESCRIPTION="$(k3s kubectl -n "$NAMESPACE" get persistentvolumeclaim creator-store-uploads \
  -o jsonpath='{.status.phase}{" "}{.spec.storageClassName}{" "}{.spec.accessModes[0]}')"
read -r PVC_PHASE PVC_STORAGE_CLASS PVC_ACCESS_MODE <<< "$PVC_DESCRIPTION"
assert_equal "uploads PVC phase" "$PVC_PHASE" "Bound"
assert_equal "uploads PVC storage class" "$PVC_STORAGE_CLASS" "local-path"
assert_equal "uploads PVC access mode" "$PVC_ACCESS_MODE" "ReadWriteOnce"

DEPLOYED_BACKEND_IMAGE="$(k3s kubectl -n "$NAMESPACE" get deployment creator-store-api \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="api")].image}')"
DEPLOYED_FRONTEND_IMAGE="$(k3s kubectl -n "$NAMESPACE" get deployment creator-store-web \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="web")].image}')"
assert_equal "backend immutable image" "$DEPLOYED_BACKEND_IMAGE" "$BACKEND_IMAGE"
assert_equal "frontend immutable image" "$DEPLOYED_FRONTEND_IMAGE" "$FRONTEND_IMAGE"

assert_equal "release infrastructure SHA" \
  "$(k3s kubectl -n "$NAMESPACE" get configmap creator-store-release -o jsonpath='{.data.infrastructure_sha}')" "$INFRA_SHA"
assert_equal "release backend digest" \
  "$(k3s kubectl -n "$NAMESPACE" get configmap creator-store-release -o jsonpath='{.data.backend_digest}')" "$BACKEND_DIGEST"
assert_equal "release frontend digest" \
  "$(k3s kubectl -n "$NAMESPACE" get configmap creator-store-release -o jsonpath='{.data.frontend_digest}')" "$FRONTEND_DIGEST"
assert_equal "release public origin" \
  "$(k3s kubectl -n "$NAMESPACE" get configmap creator-store-release -o jsonpath='{.data.public_origin}')" "$PUBLIC_ORIGIN"

k3s kubectl -n "$NAMESPACE" get secret creator-store-runtime-secrets >/dev/null
pass "runtime secret exists without exposing its value"
k3s kubectl -n "$NAMESPACE" get networkpolicy api-ingress >/dev/null
pass "API ingress NetworkPolicy exists"

WEB_BODY="$(curl --fail --silent --show-error --connect-timeout 5 --max-time 20 \
  "http://127.0.0.1:$NODE_PORT/dashboard/")"
grep -Fq '<div id="root"></div>' <<< "$WEB_BODY" || fail "local frontend response is invalid"
pass "frontend is healthy through local NodePort"
API_BODY="$(curl --fail --silent --show-error --connect-timeout 5 --max-time 20 \
  "http://127.0.0.1:$NODE_PORT/api/public/alex")"
grep -Fq '"handle":"alex"' <<< "$API_BODY" || fail "proxied API demo contract is invalid"
pass "backend and database are healthy through the frontend proxy"

printf '\nK3s node verification passed for %s.\n' "$ACTUAL_INSTANCE_ID"
