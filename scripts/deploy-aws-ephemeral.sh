#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  deploy-aws-ephemeral.sh TEST_ID EXPECTED_ACCOUNT_ID INFRA_SHA BACKEND_SHA BACKEND_DIGEST FRONTEND_SHA FRONTEND_DIGEST [AWS_REGION]

The operator-side driver validates the disposable AWS stack and deploys exact
GHCR image digests to its K3s node through SSM Run Command. No SSH or public
Kubernetes API is used, and no database secret enters Run Command history.
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
STACK_NAME="creator-store-$TEST_ID"
EXPECTED_NODE_TYPE="t3a.medium"
EXPECTED_DATABASE_CLASS="db.t4g.micro"
EXPECTED_K3S_VERSION="v1.35.8+k3s1"
PUBLIC_HTTP_PORT="80"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

[[ "$TEST_ID" =~ ^[a-z0-9-]{3,16}$ ]] || fail "invalid TEST_ID"
[[ "$EXPECTED_ACCOUNT_ID" =~ ^[0-9]{12}$ ]] || fail "invalid EXPECTED_ACCOUNT_ID"
[[ "$AWS_REGION" == "us-east-2" ]] || fail "the disposable deployment is locked to us-east-2"
for release_sha in "$INFRA_SHA" "$BACKEND_SHA" "$FRONTEND_SHA"; do
  [[ "$release_sha" =~ ^[0-9a-f]{40}$ ]] || fail "each source SHA must contain 40 lowercase hexadecimal characters"
done
for image_digest in "$BACKEND_DIGEST" "$FRONTEND_DIGEST"; do
  [[ "$image_digest" =~ ^sha256:[0-9a-f]{64}$ ]] || fail "each image digest must use sha256:<64 lowercase hex>"
done
for command_name in aws awk curl git grep jq mktemp rm seq sha256sum sleep; do
  command -v "$command_name" >/dev/null 2>&1 || fail "missing required command: $command_name"
done

[ -z "$(git -C "$REPOSITORY_ROOT" status --porcelain=v1 --untracked-files=normal)" ] || \
  fail "refusing to deploy from a dirty infrastructure checkout"
ACTUAL_INFRA_SHA="$(git -C "$REPOSITORY_ROOT" rev-parse HEAD)"
[ "$ACTUAL_INFRA_SHA" = "$INFRA_SHA" ] || fail "checked-out infrastructure SHA does not match the requested SHA"

ACTUAL_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
[ "$ACTUAL_ACCOUNT_ID" = "$EXPECTED_ACCOUNT_ID" ] || fail "refusing to deploy to unexpected AWS account $ACTUAL_ACCOUNT_ID"

get_parameter() {
  aws ssm get-parameter \
    --region "$AWS_REGION" \
    --name "$PARAMETER_PREFIX/$1" \
    --query 'Parameter.Value' \
    --output text
}

INSTANCE_ID="$(get_parameter k3s-instance-id)"
DEPLOYED_INFRA_SHA="$(get_parameter infrastructure-release)"
K3S_VERSION="$(get_parameter k3s-version)"
PUBLIC_ORIGIN="$(get_parameter public-origin)"
EXPIRES_AT="$(get_parameter expires-at)"

[[ "$INSTANCE_ID" =~ ^i-[0-9a-f]+$ ]] || fail "SSM returned an invalid K3s instance ID"
[ "$DEPLOYED_INFRA_SHA" = "$INFRA_SHA" ] || fail "AWS infrastructure marker does not match the requested SHA"
[ "$K3S_VERSION" = "$EXPECTED_K3S_VERSION" ] || fail "unexpected K3s version $K3S_VERSION"
[[ "$PUBLIC_ORIGIN" =~ ^http://([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || fail "SSM returned an invalid public origin"
[ -n "$EXPIRES_AT" ] && [ "$EXPIRES_AT" != "None" ] || fail "expiration marker is missing"

INSTANCE_DESCRIPTION="$(aws ec2 describe-instances \
  --region "$AWS_REGION" \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].[State.Name,InstanceType,PublicIpAddress,VpcId,IamInstanceProfile.Arn]' \
  --output text)"
read -r INSTANCE_STATE INSTANCE_TYPE PUBLIC_IP VPC_ID INSTANCE_PROFILE_ARN <<< "$INSTANCE_DESCRIPTION"
[ "$INSTANCE_STATE" = "running" ] || fail "K3s instance is $INSTANCE_STATE, not running"
[ "$INSTANCE_TYPE" = "$EXPECTED_NODE_TYPE" ] || fail "K3s instance type is $INSTANCE_TYPE, not $EXPECTED_NODE_TYPE"
[[ "$PUBLIC_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || fail "K3s instance has no public IPv4 address"
[[ "$VPC_ID" =~ ^vpc-[0-9a-f]+$ ]] || fail "K3s instance returned an invalid VPC ID"
[[ "$INSTANCE_PROFILE_ARN" == arn:aws:iam::"$EXPECTED_ACCOUNT_ID":instance-profile/* ]] || fail "K3s instance profile belongs to an unexpected account"
[ "$PUBLIC_ORIGIN" = "http://$PUBLIC_IP" ] || fail "public origin does not match the instance Elastic IP on HTTP port $PUBLIC_HTTP_PORT"

tag_value() {
  aws ec2 describe-tags \
    --region "$AWS_REGION" \
    --filters "Name=resource-id,Values=$INSTANCE_ID" "Name=key,Values=$1" \
    --query 'Tags[0].Value' \
    --output text
}

[ "$(tag_value Project)" = "creator-store" ] || fail "K3s Project tag mismatch"
[ "$(tag_value Environment)" = "ephemeral-test" ] || fail "K3s Environment tag mismatch"
[ "$(tag_value TestId)" = "$TEST_ID" ] || fail "K3s TestId tag mismatch"
[ "$(tag_value ManagedBy)" = "Terraform" ] || fail "K3s ManagedBy tag mismatch"
[ "$(tag_value InfrastructureRelease)" = "$INFRA_SHA" ] || fail "K3s InfrastructureRelease tag mismatch"
[ "$(tag_value ExpiresAt)" = "$EXPIRES_AT" ] || fail "K3s ExpiresAt tag mismatch"

EIP_DESCRIPTION="$(aws ec2 describe-addresses \
  --region "$AWS_REGION" \
  --filters "Name=instance-id,Values=$INSTANCE_ID" \
  --query 'Addresses[0].[PublicIp,AllocationId,AssociationId]' \
  --output text)"
read -r EIP_PUBLIC_IP EIP_ALLOCATION_ID EIP_ASSOCIATION_ID <<< "$EIP_DESCRIPTION"
[ "$EIP_PUBLIC_IP" = "$PUBLIC_IP" ] || fail "instance public IP is not its Terraform-managed Elastic IP"
[[ "$EIP_ALLOCATION_ID" =~ ^eipalloc-[0-9a-f]+$ ]] || fail "Elastic IP allocation is missing"
[[ "$EIP_ASSOCIATION_ID" =~ ^eipassoc-[0-9a-f]+$ ]] || fail "Elastic IP association is missing"

DATABASE_DESCRIPTION="$(aws rds describe-db-instances \
  --region "$AWS_REGION" \
  --db-instance-identifier "$STACK_NAME" \
  --query 'DBInstances[0].[DBInstanceStatus,PubliclyAccessible,MultiAZ,DBInstanceClass]' \
  --output text)"
read -r DATABASE_STATUS DATABASE_PUBLIC DATABASE_MULTI_AZ DATABASE_CLASS <<< "$DATABASE_DESCRIPTION"
[ "$DATABASE_STATUS" = "available" ] || fail "RDS is $DATABASE_STATUS, not available"
[[ "$DATABASE_PUBLIC" == "False" || "$DATABASE_PUBLIC" == "false" ]] || fail "RDS must remain private"
[[ "$DATABASE_MULTI_AZ" == "False" || "$DATABASE_MULTI_AZ" == "false" ]] || fail "RDS must remain Single-AZ"
[ "$DATABASE_CLASS" = "$EXPECTED_DATABASE_CLASS" ] || fail "unexpected RDS class $DATABASE_CLASS"

EKS_CLUSTER_COUNT="$(aws eks list-clusters --region "$AWS_REGION" --output json \
  | jq --arg name "$STACK_NAME" '[.clusters[] | select(. == $name)] | length')"
[ "$EKS_CLUSTER_COUNT" -eq 0 ] || fail "an EKS cluster exists for this test ID; this release is K3s-only"

SSM_STATUS="None"
for attempt in $(seq 1 120); do
  SSM_STATUS="$(aws ssm describe-instance-information \
    --region "$AWS_REGION" \
    --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
    --query 'InstanceInformationList[0].PingStatus' \
    --output text)"
  if [ "$SSM_STATUS" = "Online" ]; then
    break
  fi
  if [ "$attempt" -eq 120 ]; then
    fail "K3s instance did not become SSM Online within 10 minutes; last status: $SSM_STATUS"
  fi
  sleep 5
done

NODE_HELPER="$SCRIPT_DIR/deploy-k3s-node.sh"
[ -f "$NODE_HELPER" ] || fail "node deployment helper is missing"
NODE_HELPER_SHA256="$(sha256sum "$NODE_HELPER" | awk '{print $1}')"
[[ "$NODE_HELPER_SHA256" =~ ^[0-9a-f]{64}$ ]] || fail "could not hash the node deployment helper"
REMOTE_HELPER_URL="https://raw.githubusercontent.com/kvsram/creator-link-store-infrastructure/$INFRA_SHA/scripts/deploy-k3s-node.sh"

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/creator-store-ssm-deploy.XXXXXX")"
cleanup() {
  if [[ "${TEMP_DIR:-}" == "${TMPDIR:-/tmp}"/creator-store-ssm-deploy.* ]] && [ -d "$TEMP_DIR" ]; then
    rm -rf -- "$TEMP_DIR"
  fi
}
trap cleanup EXIT

REMOTE_COMMAND="$(cat <<EOF
set -eu
helper=/var/tmp/creator-store-deploy-k3s-node.sh
trap 'rm -f -- "\$helper"' EXIT
curl --fail --silent --show-error --location --retry 5 '$REMOTE_HELPER_URL' --output "\$helper"
printf '%s  %s\n' '$NODE_HELPER_SHA256' "\$helper" | sha256sum --check --strict -
chmod 0700 "\$helper"
"\$helper" '$TEST_ID' '$EXPECTED_ACCOUNT_ID' '$INFRA_SHA' '$BACKEND_SHA' '$BACKEND_DIGEST' '$FRONTEND_SHA' '$FRONTEND_DIGEST' '$AWS_REGION'
EOF
)"
jq -n --arg command "$REMOTE_COMMAND" '{commands: [$command]}' > "$TEMP_DIR/parameters.json"

COMMAND_ID="$(aws ssm send-command \
  --region "$AWS_REGION" \
  --document-name AWS-RunShellScript \
  --instance-ids "$INSTANCE_ID" \
  --comment "Creator Store K3s ${BACKEND_SHA:0:12} ${FRONTEND_SHA:0:12}" \
  --timeout-seconds 3600 \
  --parameters "file://$TEMP_DIR/parameters.json" \
  --query 'Command.CommandId' \
  --output text)"
[[ "$COMMAND_ID" =~ ^[0-9a-f-]{36}$ ]] || fail "SSM did not return a valid command ID"
printf 'SSM command %s started on %s.\n' "$COMMAND_ID" "$INSTANCE_ID"

COMMAND_STATUS="Pending"
for attempt in $(seq 1 720); do
  COMMAND_STATUS="$(aws ssm get-command-invocation \
    --region "$AWS_REGION" \
    --command-id "$COMMAND_ID" \
    --instance-id "$INSTANCE_ID" \
    --query Status \
    --output text 2>/dev/null || true)"
  case "$COMMAND_STATUS" in
    Success)
      break
      ;;
    Pending|InProgress|Delayed|"")
      ;;
    *)
      aws ssm get-command-invocation \
        --region "$AWS_REGION" \
        --command-id "$COMMAND_ID" \
        --instance-id "$INSTANCE_ID" \
        --query '[StandardOutputContent,StandardErrorContent]' \
        --output text || true
      fail "SSM deployment command ended with status $COMMAND_STATUS"
      ;;
  esac
  if [ "$attempt" -eq 720 ]; then
    fail "SSM deployment command did not finish within 60 minutes"
  fi
  sleep 5
done

aws ssm get-command-invocation \
  --region "$AWS_REGION" \
  --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --query 'StandardOutputContent' \
  --output text

WEB_BODY="$(curl --fail --silent --show-error --retry 30 --retry-delay 3 \
  "$PUBLIC_ORIGIN/dashboard/")"
grep -Fq '<div id="root"></div>' <<< "$WEB_BODY"
API_BODY="$(curl --fail --silent --show-error --retry 30 --retry-delay 3 \
  "$PUBLIC_ORIGIN/api/public/alex")"
grep -Fq '"handle":"alex"' <<< "$API_BODY"

printf '\nDeployment passed through SSM.\nTemporary URL: %s\n' "$PUBLIC_ORIGIN"
printf 'Mandatory teardown deadline: %s\n' "$EXPIRES_AT"
