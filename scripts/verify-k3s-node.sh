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
PUBLIC_HTTP_PORT="80"
BACKEND_IMAGE="ghcr.io/kvsram/creator-link-store-backend@$BACKEND_DIGEST"
FRONTEND_IMAGE="ghcr.io/kvsram/creator-link-store-frontend@$FRONTEND_DIGEST"

[ "$(id -u)" -eq 0 ] || fail "node verification must run as root"
[[ "$TEST_ID" =~ ^[a-z0-9-]{3,16}$ ]] || fail "invalid TEST_ID"
[[ "$EXPECTED_ACCOUNT_ID" =~ ^[0-9]{12}$ ]] || fail "invalid EXPECTED_ACCOUNT_ID"
[[ "$INFRA_SHA" =~ ^[0-9a-f]{40}$ ]] || fail "invalid infrastructure SHA"
[[ "$BACKEND_DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]] || fail "invalid backend digest"
[[ "$FRONTEND_DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]] || fail "invalid frontend digest"
[[ "$AWS_REGION" == "us-east-2" ]] || fail "the disposable verification is locked to us-east-2"
for command_name in aws awk curl grep jq k3s stat tr; do
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
[[ "$PUBLIC_ORIGIN" =~ ^http://([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || fail "invalid public origin marker"
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
WEB_DEPLOYMENT_DESCRIPTION="$(k3s kubectl -n "$NAMESPACE" get deployment creator-store-web \
  -o jsonpath='{.spec.strategy.type}{" "}{.spec.template.spec.containers[?(@.name=="web")].ports[?(@.name=="http")].hostPort}')"
read -r WEB_DEPLOYMENT_STRATEGY WEB_HOST_PORT <<< "$WEB_DEPLOYMENT_DESCRIPTION"
WEB_SERVICE_DESCRIPTION="$(k3s kubectl -n "$NAMESPACE" get service creator-store-web \
  -o jsonpath='{.spec.type}{" "}{.spec.ports[?(@.name=="http")].nodePort}{" "}{.spec.externalTrafficPolicy}')"
read -r WEB_SERVICE_TYPE WEB_NODE_PORT WEB_TRAFFIC_POLICY <<< "$WEB_SERVICE_DESCRIPTION"
assert_equal "API Service type" "$API_SERVICE_TYPE" "ClusterIP"
assert_equal "web deployment strategy" "$WEB_DEPLOYMENT_STRATEGY" "Recreate"
assert_equal "web hostPort" "$WEB_HOST_PORT" "$PUBLIC_HTTP_PORT"
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

EDGE_PROXY_CONFIG="$(k3s kubectl -n "$NAMESPACE" get configmap creator-store-edge-proxy \
  -o jsonpath='{.data.default\.conf}')"
grep -Fq 'limit_req_status 429;' <<< "$EDGE_PROXY_CONFIG" || fail "edge proxy does not return 429 for rate limits"
grep -Fq 'zone=login_per_ip:1m rate=5r/m;' <<< "$EDGE_PROXY_CONFIG" || fail "login rate-limit zone is missing"
grep -Fq 'zone=lead_per_ip:1m rate=5r/m;' <<< "$EDGE_PROXY_CONFIG" || fail "lead rate-limit zone is missing"
grep -Fq 'zone=view_per_ip:1m rate=30r/s;' <<< "$EDGE_PROXY_CONFIG" || fail "view rate-limit zone is missing"
grep -Fq '/auth(?:;[^/]*)?/register' <<< "$EDGE_PROXY_CONFIG" || fail "registration rate-limit location is missing"
grep -Fq '/checkout(?:;[^/]*)?/sessions' <<< "$EDGE_PROXY_CONFIG" || fail "checkout rate-limit location is missing"
grep -Fq '/products(?:;[^/]*)?/[0-9]+(?:;[^/]*)?/leads' <<< "$EDGE_PROXY_CONFIG" || fail "lead rate-limit location is missing"
grep -Fq '/events(?:;[^/]*)?/view' <<< "$EDGE_PROXY_CONFIG" || fail "view rate-limit location is missing"
pass "edge proxy has reviewed general, identity, checkout, lead, and analytics limits"

PROXY_PARAMS="$(k3s kubectl -n "$NAMESPACE" get configmap creator-store-proxy-params \
  -o jsonpath='{.data.proxy_params}')"
grep -Fq 'proxy_set_header X-Forwarded-For $remote_addr;' <<< "$PROXY_PARAMS" || \
  fail "edge proxy does not overwrite X-Forwarded-For with the direct peer"
! grep -Fq 'proxy_add_x_forwarded_for' <<< "$PROXY_PARAMS" || \
  fail "edge proxy trusts or appends a caller-controlled forwarding chain"
pass "edge proxy uses the direct TCP peer as its non-spoofable client identity"

EDGE_PROXY_MOUNT="$(k3s kubectl -n "$NAMESPACE" get deployment creator-store-web \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="web")].volumeMounts[?(@.name=="edge-proxy-config")].mountPath}')"
PROXY_PARAMS_MOUNT="$(k3s kubectl -n "$NAMESPACE" get deployment creator-store-web \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="web")].volumeMounts[?(@.name=="proxy-params")].mountPath}')"
assert_equal "edge proxy config mount" "$EDGE_PROXY_MOUNT" "/etc/nginx/conf.d/default.conf"
assert_equal "proxy parameters mount" "$PROXY_PARAMS_MOUNT" "/etc/nginx/proxy_params"

LIVE_NGINX_CONFIG="$(k3s kubectl -n "$NAMESPACE" exec deployment/creator-store-web -- nginx -T 2>&1)" || \
  fail "live Nginx configuration does not pass nginx -T"
grep -Fq 'limit_req zone=login_per_ip burst=5 nodelay;' <<< "$LIVE_NGINX_CONFIG" || \
  fail "live Nginx configuration is not using the login rate limit"
grep -Fq 'proxy_set_header X-Forwarded-For $remote_addr;' <<< "$LIVE_NGINX_CONFIG" || \
  fail "live Nginx configuration is not using the reviewed client-IP forwarding policy"
pass "live Nginx parsed and loaded the reviewed edge policy"

WEB_BODY="$(curl --fail --silent --show-error --connect-timeout 5 --max-time 20 \
  "http://127.0.0.1:$NODE_PORT/dashboard/")"
grep -Fq '<div id="root"></div>' <<< "$WEB_BODY" || fail "local frontend response is invalid"
pass "frontend is healthy through local NodePort"
API_BODY="$(curl --fail --silent --show-error --connect-timeout 5 --max-time 20 \
  "http://127.0.0.1:$NODE_PORT/api/public/alex")"
grep -Fq '"handle":"alex"' <<< "$API_BODY" || fail "proxied API demo contract is invalid"
pass "backend and database are healthy through the frontend proxy"

assert_rate_policy() {
  local path="$1"
  local expected_policy="$2"
  local response_headers actual_policy
  response_headers="$(curl --silent --show-error --path-as-is \
    --dump-header - --output /dev/null --connect-timeout 5 --max-time 20 \
    "http://127.0.0.1:$NODE_PORT$path")"
  actual_policy="$(awk 'tolower($1) == "x-ratelimit-policy:" {print $2; exit}' \
    <<< "$response_headers" | tr -d '\r')"
  assert_equal "rate-limit policy for $path" "$actual_policy" "$expected_policy"
}

# Nginx matches against a normalized URI. These probes ensure common alternate
# spellings cannot fall through from a sensitive budget to generic /api limits.
for path in \
  '/api/auth/login' \
  '/api/auth/login/' \
  '/api//auth/login' \
  '/api/auth/./login' \
  '/api/auth/%6cogin' \
  '/api/auth/login;probe=1' \
  '/api;probe=1/auth/login' \
  '/api/auth;probe=1/login'; do
  assert_rate_policy "$path" login
done
for path in \
  '/api/auth/register' \
  '/api/auth/register/' \
  '/api//auth/register' \
  '/api/auth/./register' \
  '/api/auth/register;probe=1' \
  '/api;probe=1/auth/register' \
  '/api/auth;probe=1/register' \
  '/api/v1/authentication/check-unique-taken' \
  '/api/v1/authentication/check-unique-taken/' \
  '/api/v1/authentication/check-unique-taken;probe=1' \
  '/api/v1/authentication;probe=1/check-unique-taken'; do
  assert_rate_policy "$path" register
done
for path in \
  '/api/v1/checkout/sessions' \
  '/api/v1/checkout/sessions/' \
  '/api//v1/checkout/sessions' \
  '/api/v1/checkout/./sessions' \
  '/api/v1/checkout/sessions;probe=1' \
  '/api/v1/checkout;probe=1/sessions' \
  '/api/v1/payments/razorpay/verify' \
  '/api/v1/payments/razorpay/verify/' \
  '/api/v1/payments/razorpay/verify;probe=1' \
  '/api/v1/payments/razorpay;probe=1/verify'; do
  assert_rate_policy "$path" checkout
done
for path in \
  '/api/public/products/42/leads' \
  '/api/public/products/42/leads/' \
  '/api//public/products/42/leads' \
  '/api/public/products/./42/leads' \
  '/api/public;probe=1/products/42/leads' \
  '/api/public/products/42;probe=1/leads' \
  '/api/public/products/42/leads;probe=1'; do
  assert_rate_policy "$path" lead
done
for path in \
  '/api/events/view' \
  '/api/events/view/' \
  '/api//events/view' \
  '/api/events/./view' \
  '/api;probe=1/events/view' \
  '/api/events;probe=1/view' \
  '/api/events/view;probe=1'; do
  assert_rate_policy "$path" view
done
pass "sensitive path normalization stays in the strict rate-limit policies"

LEAD_RATE_LIMITED=false
for attempt in $(seq 1 12); do
  LEAD_STATUS="$(curl --silent --output /dev/null --write-out '%{http_code}' \
    --connect-timeout 5 --max-time 20 \
    "http://127.0.0.1:$NODE_PORT/api/public/products/42/leads")"
  if [ "$LEAD_STATUS" = "429" ]; then
    LEAD_RATE_LIMITED=true
    break
  fi
done
[ "$LEAD_RATE_LIMITED" = "true" ] || fail "anonymous lead burst did not trigger an HTTP 429"
pass "anonymous lead rate limit rejects an excessive same-IP burst with HTTP 429"

RATE_LIMITED=false
for attempt in $(seq 1 12); do
  LOGIN_STATUS="$(curl --silent --output /dev/null --write-out '%{http_code}' \
    --connect-timeout 5 --max-time 20 \
    --header 'Content-Type: application/json' \
    --data '{"handleOrEmail":"rate-limit-probe","password":"invalid"}' \
    "http://127.0.0.1:$NODE_PORT/api/auth/login")"
  if [ "$LOGIN_STATUS" = "429" ]; then
    RATE_LIMITED=true
    break
  fi
done
[ "$RATE_LIMITED" = "true" ] || fail "login burst did not trigger an HTTP 429"
pass "login rate limit rejects an excessive same-IP burst with HTTP 429"

printf '\nK3s node verification passed for %s.\n' "$ACTUAL_INSTANCE_ID"
