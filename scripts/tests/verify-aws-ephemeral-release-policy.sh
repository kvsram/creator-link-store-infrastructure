#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RENDERED_RELEASE="${1:-}"
TEMP_DIR=""

fail() {
  printf 'FAIL  %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ "${TEMP_DIR:-}" == "${TMPDIR:-/tmp}"/creator-store-release-policy.* ]] && [ -d "$TEMP_DIR" ]; then
    rm -rf -- "$TEMP_DIR"
  fi
}
trap cleanup EXIT

if [ -z "$RENDERED_RELEASE" ]; then
  command -v kubectl >/dev/null 2>&1 || fail "kubectl is required when no rendered release path is supplied"
  TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/creator-store-release-policy.XXXXXX")"
  RENDERED_RELEASE="$TEMP_DIR/aws-ephemeral.yaml"
  kubectl kustomize "$REPOSITORY_ROOT/k8s/overlays/aws-ephemeral" > "$RENDERED_RELEASE"
fi
[ -s "$RENDERED_RELEASE" ] || fail "rendered AWS ephemeral release is missing or empty"

# Parse only top-level Kubernetes metadata/spec fields from kubectl's canonical
# Kustomize output. This avoids a loose repository-wide replicas/strategy count
# accidentally passing because an unrelated workload has the desired values.
awk '
  function finish_document() {
    if (kind == "Deployment" && name == "creator-store-api") {
      api_deployments++
      if (replicas != "1") {
        printf "FAIL  API replicas must be 1, found %s\n", replicas > "/dev/stderr"
        failed = 1
      }
      if (strategy != "Recreate") {
        printf "FAIL  API rollout strategy must be Recreate, found %s\n", strategy > "/dev/stderr"
        failed = 1
      }
    }
    if (kind == "HorizontalPodAutoscaler" && name == "creator-store-api") {
      api_hpas++
    }
    kind = ""
    name = ""
    replicas = ""
    strategy = ""
    in_metadata = 0
    in_strategy = 0
  }
  $0 == "---" { finish_document(); next }
  /^kind: / { kind = substr($0, 7); next }
  $0 == "metadata:" { in_metadata = 1; next }
  $0 == "spec:" { in_metadata = 0; next }
  in_metadata && /^  name: / { name = substr($0, 9); next }
  kind == "Deployment" && name == "creator-store-api" && /^  replicas: / {
    replicas = substr($0, 13)
    next
  }
  kind == "Deployment" && name == "creator-store-api" && $0 == "  strategy:" {
    in_strategy = 1
    next
  }
  in_strategy && /^    type: / {
    strategy = substr($0, 11)
    in_strategy = 0
    next
  }
  END {
    finish_document()
    if (api_deployments != 1) {
      printf "FAIL  expected exactly one API Deployment, found %d\n", api_deployments > "/dev/stderr"
      failed = 1
    }
    if (api_hpas != 0) {
      printf "FAIL  API HPA must be absent, found %d\n", api_hpas > "/dev/stderr"
      failed = 1
    }
    exit failed
  }
' "$RENDERED_RELEASE"

EDGE_CONFIG="$REPOSITORY_ROOT/k8s/overlays/aws-ephemeral/files/default.conf"
[ -s "$EDGE_CONFIG" ] || fail "edge configuration is missing"

require_edge_text() {
  grep -Fq -- "$1" "$EDGE_CONFIG" || fail "edge configuration is missing: $1"
}

require_edge_text 'map $request_method $auth_write_limit_key {'
require_edge_text 'POST $binary_remote_addr;'
require_edge_text 'limit_req_zone $auth_write_limit_key zone=login_per_ip:1m rate=5r/m;'
require_edge_text 'limit_req_zone $auth_write_limit_key zone=register_per_ip:1m rate=2r/m;'
require_edge_text 'limit_req_zone $auth_write_limit_key zone=auth_recovery_per_ip:1m rate=3r/m;'
require_edge_text 'limit_req_zone $auth_write_limit_key zone=auth_token_per_ip:1m rate=10r/m;'
require_edge_text '/auth(?:;[^/]*)?/sessions(?:;[^/]*)?/?$'
require_edge_text '/auth(?:;[^/]*)?/registrations(?:;[^/]*)?/?$'
require_edge_text '/auth(?:;[^/]*)?/email-verifications(?:;[^/]*)?/resend'
require_edge_text '/auth(?:;[^/]*)?/password-reset-requests'
require_edge_text '/auth(?:;[^/]*)?/email-verifications(?:;[^/]*)?/?$'
require_edge_text '/auth(?:;[^/]*)?/password-resets'

DEPLOY_HELPER="$REPOSITORY_ROOT/scripts/deploy-k3s-node.sh"
grep -Fq 'delete horizontalpodautoscaler creator-store-api' "$DEPLOY_HELPER" || \
  fail "node deploy helper does not remove a legacy API HPA"
grep -Fq 'RENDERED_API_POLICY' "$DEPLOY_HELPER" || \
  fail "node deploy helper does not preflight the rendered API replica/strategy policy"
grep -Fq 'API_RELEASE_POLICY' "$DEPLOY_HELPER" || \
  fail "node deploy helper does not verify the live API replica/strategy policy"

OPERATOR_DEPLOY="$REPOSITORY_ROOT/scripts/deploy-aws-ephemeral.sh"
OPERATOR_VERIFY="$REPOSITORY_ROOT/scripts/verify-aws-ephemeral.sh"
NODE_VERIFY="$REPOSITORY_ROOT/scripts/verify-k3s-node.sh"
grep -Fq 'APPLIED_INFRA_SHA MANIFEST_SHA' "$OPERATOR_DEPLOY" || \
  fail "operator deploy contract does not separate infrastructure and manifest SHAs"
grep -Fq '$MANIFEST_SHA/scripts/deploy-k3s-node.sh' "$OPERATOR_DEPLOY" || \
  fail "operator deploy helper is not pinned to the manifest SHA"
grep -Fq '"$DEPLOYED_INFRA_SHA" = "$APPLIED_INFRA_SHA"' "$DEPLOY_HELPER" || \
  fail "node deploy helper does not preserve the applied-infrastructure guard"
grep -Fq 'manifest_sha="$MANIFEST_SHA"' "$DEPLOY_HELPER" || \
  fail "release evidence does not record the manifest SHA"
grep -Fq '$MANIFEST_SHA/scripts/verify-k3s-node.sh' "$OPERATOR_VERIFY" || \
  fail "operator verifier is not pinned to the manifest SHA"
grep -Fq '.data.manifest_sha' "$NODE_VERIFY" || \
  fail "node verifier does not validate the deployed manifest SHA"
if grep -Eq 'ssm put-parameter|ec2 create-tags' "$OPERATOR_DEPLOY" "$DEPLOY_HELPER"; then
  fail "application deployment must not rewrite Terraform SSM markers or EC2 tags"
fi

printf 'PASS  AWS ephemeral API release and identity edge policies\n'
