#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  verify-aws-ephemeral.sh TEST_ID EXPECTED_ACCOUNT_ID INFRA_SHA BACKEND_DIGEST FRONTEND_DIGEST [AWS_REGION]
  verify-aws-ephemeral.sh --post-destroy TEST_ID EXPECTED_ACCOUNT_ID [AWS_REGION]

Live mode verifies the AWS, K3s, storage, immutable-release, and public app
contracts without reading SecureString values. --post-destroy performs a
read-only orphan audit and never deletes resources.
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

assert_count() {
  local label="$1"
  local value="$2"
  [[ "$value" =~ ^[0-9]+$ ]] || fail "$label returned a non-numeric count: $value"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

MODE="live"
if [ "${1:-}" = "--post-destroy" ]; then
  MODE="post-destroy"
  shift
fi

if { [ "$MODE" = "live" ] && { [ "$#" -lt 5 ] || [ "$#" -gt 6 ]; }; } || \
   { [ "$MODE" = "post-destroy" ] && { [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; }; }; then
  usage >&2
  exit 2
fi

TEST_ID="$1"
EXPECTED_ACCOUNT_ID="$2"
if [ "$MODE" = "live" ]; then
  INFRA_SHA="$3"
  BACKEND_DIGEST="$4"
  FRONTEND_DIGEST="$5"
  AWS_REGION="${6:-us-east-2}"
else
  AWS_REGION="${3:-us-east-2}"
fi

STACK_NAME="creator-store-$TEST_ID"
PARAMETER_PREFIX="/creator-store/ephemeral/$TEST_ID"
EXPECTED_NODE_TYPE="t3a.medium"
EXPECTED_DATABASE_CLASS="db.t4g.micro"
EXPECTED_NODE_PORT="30080"

[[ "$TEST_ID" =~ ^[a-z0-9-]{3,16}$ ]] || fail "invalid TEST_ID"
[[ "$EXPECTED_ACCOUNT_ID" =~ ^[0-9]{12}$ ]] || fail "invalid EXPECTED_ACCOUNT_ID"
[[ "$AWS_REGION" == "us-east-2" ]] || fail "the disposable verification is locked to us-east-2"
if [ "$MODE" = "live" ]; then
  [[ "$INFRA_SHA" =~ ^[0-9a-f]{40}$ ]] || fail "invalid infrastructure SHA"
  [[ "$BACKEND_DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]] || fail "invalid backend digest"
  [[ "$FRONTEND_DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]] || fail "invalid frontend digest"
fi

require_command aws
ACTUAL_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
[ "$ACTUAL_ACCOUNT_ID" = "$EXPECTED_ACCOUNT_ID" ] || fail "refusing to verify unexpected AWS account $ACTUAL_ACCOUNT_ID"
pass "AWS account guard matched $EXPECTED_ACCOUNT_ID"

tagged_resource_count() {
  aws resourcegroupstaggingapi get-resources \
    --region "$AWS_REGION" \
    --tag-filters "Key=TestId,Values=$TEST_ID" \
    --resource-type-filters "$@" \
    --query 'length(ResourceTagMappingList)' \
    --output text
}

verify_post_destroy() {
  local eks_count rds_count ec2_count ebs_count eni_count eip_count nat_count
  local vpc_count subnet_count route_table_count igw_count security_group_count
  local load_balancer_count ssm_count role_count profile_count db_count
  local db_subnet_group_count db_parameter_group_count orphan_total

  eks_count="$(tagged_resource_count eks:cluster)"
  rds_count="$(tagged_resource_count rds:db)"
  ec2_count="$(aws ec2 describe-instances \
    --region "$AWS_REGION" \
    --filters "Name=tag:TestId,Values=$TEST_ID" \
      'Name=instance-state-name,Values=pending,running,shutting-down,stopping,stopped' \
    --query 'length(Reservations[].Instances[])' --output text)"
  ebs_count="$(aws ec2 describe-volumes --region "$AWS_REGION" \
    --filters "Name=tag:TestId,Values=$TEST_ID" --query 'length(Volumes)' --output text)"
  eni_count="$(aws ec2 describe-network-interfaces --region "$AWS_REGION" \
    --filters "Name=tag:TestId,Values=$TEST_ID" --query 'length(NetworkInterfaces)' --output text)"
  eip_count="$(aws ec2 describe-addresses --region "$AWS_REGION" \
    --filters "Name=tag:TestId,Values=$TEST_ID" --query 'length(Addresses)' --output text)"
  nat_count="$(aws ec2 describe-nat-gateways --region "$AWS_REGION" \
    --filter "Name=tag:TestId,Values=$TEST_ID" \
      'Name=state,Values=pending,failed,available,deleting' \
    --query 'length(NatGateways)' --output text)"
  vpc_count="$(aws ec2 describe-vpcs --region "$AWS_REGION" \
    --filters "Name=tag:TestId,Values=$TEST_ID" --query 'length(Vpcs)' --output text)"
  subnet_count="$(aws ec2 describe-subnets --region "$AWS_REGION" \
    --filters "Name=tag:TestId,Values=$TEST_ID" --query 'length(Subnets)' --output text)"
  route_table_count="$(aws ec2 describe-route-tables --region "$AWS_REGION" \
    --filters "Name=tag:TestId,Values=$TEST_ID" --query 'length(RouteTables)' --output text)"
  igw_count="$(aws ec2 describe-internet-gateways --region "$AWS_REGION" \
    --filters "Name=tag:TestId,Values=$TEST_ID" --query 'length(InternetGateways)' --output text)"
  security_group_count="$(aws ec2 describe-security-groups --region "$AWS_REGION" \
    --filters "Name=tag:TestId,Values=$TEST_ID" --query 'length(SecurityGroups)' --output text)"
  load_balancer_count="$(tagged_resource_count \
    elasticloadbalancing:loadbalancer \
    elasticloadbalancing:loadbalancer/app \
    elasticloadbalancing:loadbalancer/net \
    elasticloadbalancing:loadbalancer/gwy)"
  ssm_count="$(aws ssm describe-parameters --region "$AWS_REGION" \
    --parameter-filters "Key=tag:TestId,Option=Equals,Values=$TEST_ID" \
    --query 'length(Parameters)' --output text)"

  if aws iam get-role --role-name "$STACK_NAME-k3s" >/dev/null 2>&1; then role_count=1; else role_count=0; fi
  if aws iam get-instance-profile --instance-profile-name "$STACK_NAME-k3s" >/dev/null 2>&1; then profile_count=1; else profile_count=0; fi
  if aws rds describe-db-instances --region "$AWS_REGION" --db-instance-identifier "$STACK_NAME" >/dev/null 2>&1; then db_count=1; else db_count=0; fi
  if aws rds describe-db-subnet-groups --region "$AWS_REGION" --db-subnet-group-name "$STACK_NAME" >/dev/null 2>&1; then db_subnet_group_count=1; else db_subnet_group_count=0; fi
  if aws rds describe-db-parameter-groups --region "$AWS_REGION" --db-parameter-group-name "$STACK_NAME" >/dev/null 2>&1; then db_parameter_group_count=1; else db_parameter_group_count=0; fi

  for named_count in \
    "$eks_count" "$rds_count" "$ec2_count" "$ebs_count" "$eni_count" "$eip_count" \
    "$nat_count" "$vpc_count" "$subnet_count" "$route_table_count" "$igw_count" \
    "$security_group_count" "$load_balancer_count" "$ssm_count" "$role_count" \
    "$profile_count" "$db_count" "$db_subnet_group_count" "$db_parameter_group_count"; do
    assert_count "post-destroy resource count" "$named_count"
  done

  printf '\nPost-destroy orphan audit for TestId=%s in %s:\n' "$TEST_ID" "$AWS_REGION"
  printf '  EKS=%s RDS-tags=%s DB=%s EC2=%s EBS=%s ENI=%s EIP=%s NAT=%s LB=%s\n' \
    "$eks_count" "$rds_count" "$db_count" "$ec2_count" "$ebs_count" "$eni_count" \
    "$eip_count" "$nat_count" "$load_balancer_count"
  printf '  VPC=%s subnets=%s routes=%s IGW=%s SG=%s SSM=%s role=%s profile=%s DB-groups=%s/%s\n' \
    "$vpc_count" "$subnet_count" "$route_table_count" "$igw_count" \
    "$security_group_count" "$ssm_count" "$role_count" "$profile_count" \
    "$db_subnet_group_count" "$db_parameter_group_count"

  orphan_total=$((eks_count + rds_count + ec2_count + ebs_count + eni_count + eip_count + nat_count + vpc_count + subnet_count + route_table_count + igw_count + security_group_count + load_balancer_count + ssm_count + role_count + profile_count + db_count + db_subnet_group_count + db_parameter_group_count))
  [ "$orphan_total" -eq 0 ] || fail "$orphan_total scoped resource(s) remain; no deletion was attempted"
  pass "no scoped K3s, RDS, network, IAM, EKS, or SSM resources remain"
}

if [ "$MODE" = "post-destroy" ]; then
  verify_post_destroy
  exit 0
fi

for command_name in awk curl git grep jq mktemp rm seq sha256sum sleep; do
  require_command "$command_name"
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
[ -z "$(git -C "$REPOSITORY_ROOT" status --porcelain=v1 --untracked-files=normal)" ] || fail "refusing to verify from a dirty infrastructure checkout"
assert_equal "checked-out infrastructure SHA" "$(git -C "$REPOSITORY_ROOT" rev-parse HEAD)" "$INFRA_SHA"

get_parameter() {
  aws ssm get-parameter --region "$AWS_REGION" --name "$PARAMETER_PREFIX/$1" \
    --query 'Parameter.Value' --output text
}

INSTANCE_ID="$(get_parameter k3s-instance-id)"
K3S_VERSION="$(get_parameter k3s-version)"
PUBLIC_ORIGIN="$(get_parameter public-origin)"
EXPIRES_AT="$(get_parameter expires-at)"
assert_equal "SSM infrastructure marker" "$(get_parameter infrastructure-release)" "$INFRA_SHA"
assert_equal "SSM K3s version" "$K3S_VERSION" "v1.35.8+k3s1"
[[ "$INSTANCE_ID" =~ ^i-[0-9a-f]+$ ]] || fail "SSM returned an invalid instance ID"
[[ "$PUBLIC_ORIGIN" =~ ^http://([0-9]{1,3}\.){3}[0-9]{1,3}:30080$ ]] || fail "SSM returned an invalid public origin"
[ -n "$EXPIRES_AT" ] && [ "$EXPIRES_AT" != "None" ] || fail "expiration marker is missing"
pass "expiration marker exists at $PARAMETER_PREFIX/expires-at"

INSTANCE_DESCRIPTION="$(aws ec2 describe-instances --region "$AWS_REGION" --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].[State.Name,InstanceType,PublicIpAddress,VpcId,SubnetId,RootDeviceName]' \
  --output text)"
read -r INSTANCE_STATE INSTANCE_TYPE PUBLIC_IP VPC_ID SUBNET_ID ROOT_DEVICE_NAME <<< "$INSTANCE_DESCRIPTION"
assert_equal "K3s instance state" "$INSTANCE_STATE" "running"
assert_equal "K3s instance type" "$INSTANCE_TYPE" "$EXPECTED_NODE_TYPE"
assert_equal "public origin" "$PUBLIC_ORIGIN" "http://$PUBLIC_IP:$EXPECTED_NODE_PORT"
[[ "$VPC_ID" =~ ^vpc-[0-9a-f]+$ ]] || fail "invalid VPC ID"
[[ "$SUBNET_ID" =~ ^subnet-[0-9a-f]+$ ]] || fail "invalid subnet ID"

for tag_pair in \
  "Project=creator-store" "Environment=ephemeral-test" "TestId=$TEST_ID" \
  "ManagedBy=Terraform" "InfrastructureRelease=$INFRA_SHA" "ExpiresAt=$EXPIRES_AT"; do
  TAG_NAME="${tag_pair%%=*}"
  TAG_EXPECTED="${tag_pair#*=}"
  TAG_ACTUAL="$(aws ec2 describe-tags --region "$AWS_REGION" \
    --filters "Name=resource-id,Values=$INSTANCE_ID" "Name=key,Values=$TAG_NAME" \
    --query 'Tags[0].Value' --output text)"
  assert_equal "K3s $TAG_NAME tag" "$TAG_ACTUAL" "$TAG_EXPECTED"
done

ROOT_VOLUME_ID="$(aws ec2 describe-instances --region "$AWS_REGION" --instance-ids "$INSTANCE_ID" \
  --query "Reservations[0].Instances[0].BlockDeviceMappings[?DeviceName=='$ROOT_DEVICE_NAME'].Ebs.VolumeId | [0]" \
  --output text)"
ROOT_VOLUME_DESCRIPTION="$(aws ec2 describe-volumes --region "$AWS_REGION" --volume-ids "$ROOT_VOLUME_ID" \
  --query 'Volumes[0].[VolumeType,Size,Encrypted]' --output text)"
read -r ROOT_VOLUME_TYPE ROOT_VOLUME_SIZE ROOT_VOLUME_ENCRYPTED <<< "$ROOT_VOLUME_DESCRIPTION"
assert_equal "root volume type" "$ROOT_VOLUME_TYPE" "gp3"
assert_equal "root volume size GiB" "$ROOT_VOLUME_SIZE" "40"
[[ "$ROOT_VOLUME_ENCRYPTED" == "True" || "$ROOT_VOLUME_ENCRYPTED" == "true" ]] || fail "root volume is not encrypted"
pass "root volume is encrypted"

EIP_DESCRIPTION="$(aws ec2 describe-addresses --region "$AWS_REGION" \
  --filters "Name=instance-id,Values=$INSTANCE_ID" \
  --query 'Addresses[0].[PublicIp,AllocationId,AssociationId]' --output text)"
read -r EIP_PUBLIC_IP EIP_ALLOCATION_ID EIP_ASSOCIATION_ID <<< "$EIP_DESCRIPTION"
assert_equal "Elastic IP" "$EIP_PUBLIC_IP" "$PUBLIC_IP"
[[ "$EIP_ALLOCATION_ID" =~ ^eipalloc-[0-9a-f]+$ ]] || fail "Elastic IP allocation is missing"
[[ "$EIP_ASSOCIATION_ID" =~ ^eipassoc-[0-9a-f]+$ ]] || fail "Elastic IP association is missing"
pass "Elastic IP is allocated and associated"

DATABASE_DESCRIPTION="$(aws rds describe-db-instances --region "$AWS_REGION" \
  --db-instance-identifier "$STACK_NAME" \
  --query 'DBInstances[0].[DBInstanceStatus,PubliclyAccessible,MultiAZ,DBInstanceClass,StorageType,AllocatedStorage,StorageEncrypted,DBSubnetGroup.VpcId,DBInstanceArn]' \
  --output text)"
read -r DATABASE_STATUS DATABASE_PUBLIC DATABASE_MULTI_AZ DATABASE_CLASS DATABASE_STORAGE_TYPE DATABASE_STORAGE_SIZE DATABASE_ENCRYPTED DATABASE_VPC_ID DATABASE_ARN <<< "$DATABASE_DESCRIPTION"
assert_equal "RDS status" "$DATABASE_STATUS" "available"
[[ "$DATABASE_PUBLIC" == "False" || "$DATABASE_PUBLIC" == "false" ]] || fail "RDS must remain private"
pass "RDS is private"
[[ "$DATABASE_MULTI_AZ" == "False" || "$DATABASE_MULTI_AZ" == "false" ]] || fail "RDS must remain Single-AZ"
pass "RDS is Single-AZ"
assert_equal "RDS class" "$DATABASE_CLASS" "$EXPECTED_DATABASE_CLASS"
assert_equal "RDS storage type" "$DATABASE_STORAGE_TYPE" "gp3"
assert_equal "RDS storage GiB" "$DATABASE_STORAGE_SIZE" "20"
[[ "$DATABASE_ENCRYPTED" == "True" || "$DATABASE_ENCRYPTED" == "true" ]] || fail "RDS storage is not encrypted"
pass "RDS storage is encrypted"
assert_equal "RDS VPC" "$DATABASE_VPC_ID" "$VPC_ID"
assert_equal "RDS TestId tag" "$(aws rds list-tags-for-resource --region "$AWS_REGION" \
  --resource-name "$DATABASE_ARN" --query "TagList[?Key=='TestId'].Value | [0]" --output text)" "$TEST_ID"

assert_equal "tagged EKS cluster count" "$(tagged_resource_count eks:cluster)" "0"
EKS_NAME_COUNT="$(aws eks list-clusters --region "$AWS_REGION" --output json \
  | jq --arg name "$STACK_NAME" '[.clusters[] | select(. == $name)] | length')"
assert_equal "same-name EKS cluster count" "$EKS_NAME_COUNT" "0"
NAT_COUNT="$(aws ec2 describe-nat-gateways --region "$AWS_REGION" \
  --filter "Name=vpc-id,Values=$VPC_ID" 'Name=state,Values=pending,failed,available,deleting' \
  --query 'length(NatGateways)' --output text)"
V2_LB_COUNT="$(aws elbv2 describe-load-balancers --region "$AWS_REGION" \
  --query "length(LoadBalancers[?VpcId=='$VPC_ID'])" --output text)"
CLASSIC_LB_COUNT="$(aws elb describe-load-balancers --region "$AWS_REGION" \
  --query "length(LoadBalancerDescriptions[?VPCId=='$VPC_ID'])" --output text)"
assert_equal "NAT Gateway count" "$NAT_COUNT" "0"
assert_equal "ALB/NLB/Gateway Load Balancer count" "$V2_LB_COUNT" "0"
assert_equal "Classic Load Balancer count" "$CLASSIC_LB_COUNT" "0"

SECURITY_GROUPS="$(aws ec2 describe-instances --region "$AWS_REGION" --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].SecurityGroups[].GroupId' --output text)"
[ -n "$SECURITY_GROUPS" ] && [ "$SECURITY_GROUPS" != "None" ] || fail "K3s instance has no security group"
INGRESS_RULE_COUNT=0
for SECURITY_GROUP_ID in $SECURITY_GROUPS; do
  RULES_JSON="$(aws ec2 describe-security-group-rules --region "$AWS_REGION" \
    --filters "Name=group-id,Values=$SECURITY_GROUP_ID" 'Name=is-egress,Values=false' \
    --query 'SecurityGroupRules' --output json)"
  CURRENT_RULE_COUNT="$(jq 'length' <<< "$RULES_JSON")"
  INGRESS_RULE_COUNT=$((INGRESS_RULE_COUNT + CURRENT_RULE_COUNT))
  jq -e --argjson port "$EXPECTED_NODE_PORT" '
    all(.[];
      .IpProtocol == "tcp" and
      .FromPort == $port and
      .ToPort == $port and
      (.CidrIpv4 | type == "string" and test("^([0-9]{1,3}\\.){3}[0-9]{1,3}/32$")) and
      (.CidrIpv6 == null) and
      (.ReferencedGroupInfo == null) and
      (.PrefixListId == null)
    )
  ' <<< "$RULES_JSON" >/dev/null || fail "K3s ingress contains a rule other than TCP 30080 from IPv4 /32"
done
[ "$INGRESS_RULE_COUNT" -ge 1 ] || fail "no allowlisted NodePort ingress rule exists"
pass "all $INGRESS_RULE_COUNT inbound rule(s) are TCP 30080 from IPv4 /32; ports 22 and 6443 are closed"

SSM_STATUS="$(aws ssm describe-instance-information --region "$AWS_REGION" \
  --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
  --query 'InstanceInformationList[0].PingStatus' --output text)"
assert_equal "SSM node status" "$SSM_STATUS" "Online"

NODE_HELPER="$SCRIPT_DIR/verify-k3s-node.sh"
[ -f "$NODE_HELPER" ] || fail "node verification helper is missing"
NODE_HELPER_SHA256="$(sha256sum "$NODE_HELPER" | awk '{print $1}')"
REMOTE_HELPER_URL="https://raw.githubusercontent.com/kvsram/creator-link-store-infrastructure/$INFRA_SHA/scripts/verify-k3s-node.sh"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/creator-store-ssm-verify.XXXXXX")"
cleanup() {
  if [[ "${TEMP_DIR:-}" == "${TMPDIR:-/tmp}"/creator-store-ssm-verify.* ]] && [ -d "$TEMP_DIR" ]; then
    rm -rf -- "$TEMP_DIR"
  fi
}
trap cleanup EXIT

REMOTE_COMMAND="$(cat <<EOF
set -eu
helper=/var/tmp/creator-store-verify-k3s-node.sh
trap 'rm -f -- "\$helper"' EXIT
curl --fail --silent --show-error --location --retry 5 '$REMOTE_HELPER_URL' --output "\$helper"
printf '%s  %s\n' '$NODE_HELPER_SHA256' "\$helper" | sha256sum --check --strict -
chmod 0700 "\$helper"
"\$helper" '$TEST_ID' '$EXPECTED_ACCOUNT_ID' '$INFRA_SHA' '$BACKEND_DIGEST' '$FRONTEND_DIGEST' '$AWS_REGION'
EOF
)"
jq -n --arg command "$REMOTE_COMMAND" '{commands: [$command]}' > "$TEMP_DIR/parameters.json"
COMMAND_ID="$(aws ssm send-command --region "$AWS_REGION" \
  --document-name AWS-RunShellScript --instance-ids "$INSTANCE_ID" \
  --comment "Creator Store read-only K3s verification" --timeout-seconds 900 \
  --parameters "file://$TEMP_DIR/parameters.json" --query 'Command.CommandId' --output text)"
[[ "$COMMAND_ID" =~ ^[0-9a-f-]{36}$ ]] || fail "SSM did not return a valid verification command ID"

COMMAND_STATUS="Pending"
for attempt in $(seq 1 180); do
  COMMAND_STATUS="$(aws ssm get-command-invocation --region "$AWS_REGION" \
    --command-id "$COMMAND_ID" --instance-id "$INSTANCE_ID" \
    --query Status --output text 2>/dev/null || true)"
  case "$COMMAND_STATUS" in
    Success) break ;;
    Pending|InProgress|Delayed|"") ;;
    *)
      aws ssm get-command-invocation --region "$AWS_REGION" --command-id "$COMMAND_ID" \
        --instance-id "$INSTANCE_ID" --query '[StandardOutputContent,StandardErrorContent]' --output text || true
      fail "SSM verification command ended with status $COMMAND_STATUS"
      ;;
  esac
  [ "$attempt" -lt 180 ] || fail "SSM verification command did not finish within 15 minutes"
  sleep 5
done
aws ssm get-command-invocation --region "$AWS_REGION" --command-id "$COMMAND_ID" \
  --instance-id "$INSTANCE_ID" --query 'StandardOutputContent' --output text

WEB_BODY="$(curl --fail --silent --show-error --connect-timeout 5 --max-time 20 \
  "$PUBLIC_ORIGIN/dashboard/")"
grep -Fq '<div id="root"></div>' <<< "$WEB_BODY" || fail "public frontend contract failed"
pass "frontend is healthy through restricted public NodePort"
API_BODY="$(curl --fail --silent --show-error --connect-timeout 5 --max-time 20 \
  "$PUBLIC_ORIGIN/api/public/alex")"
grep -Fq '"handle":"alex"' <<< "$API_BODY" || fail "public API contract failed"
pass "backend and database are healthy through the public frontend proxy"

printf '\nLive disposable K3s stack verification passed.\n'
printf 'K3s: 1 x %s (%s)\nRDS: 1 x %s, private Single-AZ\n' \
  "$EXPECTED_NODE_TYPE" "$K3S_VERSION" "$EXPECTED_DATABASE_CLASS"
printf 'EKS: 0\nNAT Gateways: 0\nLoad balancers: 0\nURL: %s\nExpires: %s\n' \
  "$PUBLIC_ORIGIN" "$EXPIRES_AT"
