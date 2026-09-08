#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  deploy-aws-ephemeral.sh TEST_ID EXPECTED_ACCOUNT_ID INFRA_SHA BACKEND_SHA BACKEND_DIGEST FRONTEND_SHA FRONTEND_DIGEST [AWS_REGION]

The script deploys exact GHCR image digests to the disposable EKS stack and reads
the RDS connection values from Standard-tier SSM parameters. It never prints
the database password.
EOF
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
EXPECTED_CLUSTER_NAME="creator-store-$TEST_ID"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

for command_name in aws git kubectl curl grep mktemp rm sed; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'Missing required command: %s\n' "$command_name" >&2
    exit 1
  }
done

[[ "$TEST_ID" =~ ^[a-z0-9-]{3,16}$ ]] || {
  printf 'TEST_ID must contain 3-16 lowercase letters, digits, or hyphens.\n' >&2
  exit 1
}

[[ "$EXPECTED_ACCOUNT_ID" =~ ^[0-9]{12}$ ]] || {
  printf 'EXPECTED_ACCOUNT_ID must contain exactly 12 digits.\n' >&2
  exit 1
}

for release_sha in "$INFRA_SHA" "$BACKEND_SHA" "$FRONTEND_SHA"; do
  [[ "$release_sha" =~ ^[0-9a-f]{40}$ ]] || {
    printf 'Each source SHA must contain exactly 40 lowercase hexadecimal characters.\n' >&2
    exit 1
  }
done

for image_digest in "$BACKEND_DIGEST" "$FRONTEND_DIGEST"; do
  [[ "$image_digest" =~ ^sha256:[0-9a-f]{64}$ ]] || {
    printf 'Each application digest must use the immutable sha256:<64 lowercase hex> form.\n' >&2
    exit 1
  }
done

repository_status="$(git -C "$REPOSITORY_ROOT" status --porcelain=v1 --untracked-files=normal)"
if [ -n "$repository_status" ]; then
  printf 'Refusing to deploy from a dirty infrastructure checkout. Commit or remove all tracked and untracked changes first.\n' >&2
  exit 1
fi
unset repository_status

actual_infra_sha="$(git -C "$REPOSITORY_ROOT" rev-parse HEAD)"
if [ "$actual_infra_sha" != "$INFRA_SHA" ]; then
  printf 'Checked-out infrastructure SHA %s does not match requested SHA %s.\n' \
    "$actual_infra_sha" "$INFRA_SHA" >&2
  exit 1
fi

ACTUAL_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
if [ "$ACTUAL_ACCOUNT_ID" != "$EXPECTED_ACCOUNT_ID" ]; then
  printf 'Refusing to deploy to unexpected AWS account %s.\n' "$ACTUAL_ACCOUNT_ID" >&2
  exit 1
fi

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

CLUSTER_NAME="$(get_parameter eks-cluster-name)"
DEPLOYED_INFRA_SHA="$(get_parameter infrastructure-release)"
DB_URL="$(get_parameter database-url)"
DB_USER="$(get_parameter database-username)"
EXPIRES_AT="$(get_parameter expires-at)"

if [ "$CLUSTER_NAME" != "$EXPECTED_CLUSTER_NAME" ]; then
  printf 'SSM returned unexpected EKS cluster name %s; expected %s.\n' \
    "$CLUSTER_NAME" "$EXPECTED_CLUSTER_NAME" >&2
  exit 1
fi

if [ "$DEPLOYED_INFRA_SHA" != "$INFRA_SHA" ]; then
  printf 'AWS infrastructure marker %s does not match requested SHA %s.\n' \
    "$DEPLOYED_INFRA_SHA" "$INFRA_SHA" >&2
  exit 1
fi

read -r EKS_ARN EKS_STATUS EKS_ENDPOINT EKS_TAG_PROJECT EKS_TAG_ENVIRONMENT \
  EKS_TAG_TEST_ID EKS_TAG_MANAGED_BY EKS_TAG_INFRA_SHA EKS_TAG_EXPIRES_AT <<< "$(
    aws eks describe-cluster \
      --region "$AWS_REGION" \
      --name "$CLUSTER_NAME" \
      --query 'cluster.[arn,status,endpoint,tags.Project,tags.Environment,tags.TestId,tags.ManagedBy,tags.InfrastructureRelease,tags.ExpiresAt]' \
      --output text
  )"

EXPECTED_EKS_ARN="arn:aws:eks:$AWS_REGION:$EXPECTED_ACCOUNT_ID:cluster/$CLUSTER_NAME"
if [ "$EKS_ARN" != "$EXPECTED_EKS_ARN" ]; then
  printf 'EKS ARN does not match the expected account, region, and cluster: %s\n' "$EKS_ARN" >&2
  exit 1
fi
if [ "$EKS_STATUS" != "ACTIVE" ]; then
  printf 'EKS cluster %s is not ACTIVE; current status is %s.\n' "$CLUSTER_NAME" "$EKS_STATUS" >&2
  exit 1
fi

verify_eks_tag() {
  local tag_name="$1"
  local actual_value="$2"
  local expected_value="$3"
  if [ "$actual_value" != "$expected_value" ]; then
    printf 'EKS tag %s is %s; expected %s. Refusing deployment.\n' \
      "$tag_name" "$actual_value" "$expected_value" >&2
    exit 1
  fi
}

verify_eks_tag Project "$EKS_TAG_PROJECT" creator-store
verify_eks_tag Environment "$EKS_TAG_ENVIRONMENT" ephemeral-test
verify_eks_tag TestId "$EKS_TAG_TEST_ID" "$TEST_ID"
verify_eks_tag ManagedBy "$EKS_TAG_MANAGED_BY" Terraform
verify_eks_tag InfrastructureRelease "$EKS_TAG_INFRA_SHA" "$INFRA_SHA"
verify_eks_tag ExpiresAt "$EKS_TAG_EXPIRES_AT" "$EXPIRES_AT"

RELEASE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/creator-store-release.XXXXXX")"
cleanup() {
  if [[ "$RELEASE_DIR" == "${TMPDIR:-/tmp}"/creator-store-release.* ]]; then
    rm -rf -- "$RELEASE_DIR"
  fi
}
trap cleanup EXIT
umask 077

KUBECONFIG="$RELEASE_DIR/kubeconfig"
KUBE_CONTEXT="creator-store-ephemeral-$TEST_ID-$EXPECTED_ACCOUNT_ID-$AWS_REGION"
export KUBECONFIG
aws eks update-kubeconfig \
  --region "$AWS_REGION" \
  --name "$CLUSTER_NAME" \
  --alias "$KUBE_CONTEXT" \
  --kubeconfig "$KUBECONFIG" >/dev/null

ACTUAL_KUBE_CONTEXT="$(kubectl config current-context)"
if [ "$ACTUAL_KUBE_CONTEXT" != "$KUBE_CONTEXT" ]; then
  printf 'Temporary kubeconfig selected context %s; expected %s.\n' \
    "$ACTUAL_KUBE_CONTEXT" "$KUBE_CONTEXT" >&2
  exit 1
fi

KUBE_SERVER="$(kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.server}')"
if [ "$KUBE_SERVER" != "$EKS_ENDPOINT" ]; then
  printf 'Temporary kubeconfig endpoint does not match the verified EKS endpoint.\n' >&2
  exit 1
fi
kubectl --context "$KUBE_CONTEXT" get --raw=/version >/dev/null

WORKER_IP_TEXT="$(aws ec2 describe-instances \
  --region "$AWS_REGION" \
  --filters \
    "Name=tag:eks:cluster-name,Values=$CLUSTER_NAME" \
    'Name=instance-state-name,Values=running' \
  --query 'Reservations[].Instances[].PublicIpAddress' \
  --output text)"

WORKER_IPS=()
read -r -a WORKER_IPS <<< "$WORKER_IP_TEXT"
if [ "${#WORKER_IPS[@]}" -ne 1 ]; then
  printf 'Expected exactly one running worker public IPv4 address; found %s.\n' \
    "${#WORKER_IPS[@]}" >&2
  exit 1
fi
WORKER_IP="${WORKER_IPS[0]}"
unset WORKER_IP_TEXT WORKER_IPS

if [[ ! "$WORKER_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf 'Could not discover a running worker public IPv4 address. Found: %s\n' "$WORKER_IP" >&2
  exit 1
fi

PUBLIC_ORIGIN="http://$WORKER_IP:$NODE_PORT"
BACKEND_IMAGE="ghcr.io/kvsram/creator-link-store-backend@$BACKEND_DIGEST"
FRONTEND_IMAGE="ghcr.io/kvsram/creator-link-store-frontend@$FRONTEND_DIGEST"

kubectl --context "$KUBE_CONTEXT" create namespace "$NAMESPACE" --dry-run=client -o yaml \
  | kubectl --context "$KUBE_CONTEXT" apply -f - >/dev/null

DB_ENV_FILE="$RELEASE_DIR/database.env"
{
  printf 'DB_URL=%s\n' "$DB_URL"
  printf 'DB_USER=%s\n' "$DB_USER"
  printf 'DB_PASSWORD='
  get_parameter database-password true
} > "$DB_ENV_FILE"
unset DB_URL DB_USER

kubectl --context "$KUBE_CONTEXT" -n "$NAMESPACE" \
  create secret generic creator-store-runtime-secrets \
  --from-env-file="$DB_ENV_FILE" \
  --dry-run=client -o yaml \
  | kubectl --context "$KUBE_CONTEXT" apply -f - >/dev/null
rm -f -- "$DB_ENV_FILE"

kubectl kustomize "$REPOSITORY_ROOT/k8s/overlays/aws-ephemeral" > "$RELEASE_DIR/source.yaml"
sed \
  -e "s#ghcr.io/kvsram/creator-link-store-backend:replace-with-sha#$BACKEND_IMAGE#g" \
  -e "s#ghcr.io/kvsram/creator-link-store-frontend:replace-with-sha#$FRONTEND_IMAGE#g" \
  -e "s#http://replace-with-worker-ip:30080#$PUBLIC_ORIGIN#g" \
  -e "s#replace-with-test-id#$TEST_ID#g" \
  -e "s#replace-with-expires-at#$EXPIRES_AT#g" \
  "$RELEASE_DIR/source.yaml" > "$RELEASE_DIR/release.yaml"

if grep -Eq 'replace-with|ghcr.io/kvsram/creator-link-store-(backend|frontend):' "$RELEASE_DIR/release.yaml"; then
  printf 'Rendered release still contains a placeholder or mutable image tag.\n' >&2
  exit 1
fi
if [ "$(grep -Fc "$BACKEND_IMAGE" "$RELEASE_DIR/release.yaml")" -ne 1 ]; then
  printf 'Rendered release does not contain the requested backend digest.\n' >&2
  exit 1
fi
if [ "$(grep -Fc "$FRONTEND_IMAGE" "$RELEASE_DIR/release.yaml")" -ne 1 ]; then
  printf 'Rendered release does not contain the requested frontend digest.\n' >&2
  exit 1
fi

kubectl --context "$KUBE_CONTEXT" apply --dry-run=server -f "$RELEASE_DIR/release.yaml" >/dev/null
kubectl --context "$KUBE_CONTEXT" apply -f "$RELEASE_DIR/release.yaml"
kubectl --context "$KUBE_CONTEXT" -n "$NAMESPACE" rollout status deployment/creator-store-api --timeout=8m
kubectl --context "$KUBE_CONTEXT" -n "$NAMESPACE" rollout status deployment/creator-store-web --timeout=5m

DEPLOYED_BACKEND_IMAGE="$(kubectl --context "$KUBE_CONTEXT" -n "$NAMESPACE" \
  get deployment creator-store-api -o jsonpath='{.spec.template.spec.containers[?(@.name=="api")].image}')"
DEPLOYED_FRONTEND_IMAGE="$(kubectl --context "$KUBE_CONTEXT" -n "$NAMESPACE" \
  get deployment creator-store-web -o jsonpath='{.spec.template.spec.containers[?(@.name=="web")].image}')"
if [ "$DEPLOYED_BACKEND_IMAGE" != "$BACKEND_IMAGE" ] || [ "$DEPLOYED_FRONTEND_IMAGE" != "$FRONTEND_IMAGE" ]; then
  printf 'Live deployments do not reference the requested immutable image digests.\n' >&2
  exit 1
fi

kubectl --context "$KUBE_CONTEXT" -n "$NAMESPACE" create configmap creator-store-release \
  --from-literal=infrastructure_sha="$INFRA_SHA" \
  --from-literal=backend_sha="$BACKEND_SHA" \
  --from-literal=backend_digest="$BACKEND_DIGEST" \
  --from-literal=frontend_sha="$FRONTEND_SHA" \
  --from-literal=frontend_digest="$FRONTEND_DIGEST" \
  --from-literal=public_origin="$PUBLIC_ORIGIN" \
  --from-literal=expires_at="$EXPIRES_AT" \
  --dry-run=client -o yaml | kubectl --context "$KUBE_CONTEXT" apply -f - >/dev/null

curl --fail --silent --show-error --retry 20 --retry-delay 3 \
  "$PUBLIC_ORIGIN/dashboard/" >/dev/null

kubectl --context "$KUBE_CONTEXT" -n "$NAMESPACE" get deployment,pod,service,persistentvolumeclaim
printf '\nDeployment passed. Temporary URL: %s\n' "$PUBLIC_ORIGIN"
printf 'Mandatory teardown deadline: %s\n' "$EXPIRES_AT"
