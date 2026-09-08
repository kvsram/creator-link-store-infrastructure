#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  verify-aws-ephemeral.sh TEST_ID EXPECTED_ACCOUNT_ID [AWS_REGION]
  verify-aws-ephemeral.sh --post-destroy TEST_ID EXPECTED_ACCOUNT_ID [AWS_REGION]

The default mode verifies the live disposable stack and requires EKS API
reachability for workload, storage, and public application tests.
--post-destroy performs a read-only orphan audit for resources tagged with
TestId; it never deletes resources or reads SecureString values.
EOF
}

fail() {
  printf 'FAIL  %s\n' "$*" >&2
  exit 1
}

pass() {
  printf 'PASS  %s\n' "$*"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
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

MODE="live"
if [ "${1:-}" = "--post-destroy" ]; then
  MODE="post-destroy"
  shift
fi

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  usage >&2
  exit 2
fi

TEST_ID="$1"
EXPECTED_ACCOUNT_ID="$2"
AWS_REGION="${3:-us-east-2}"
STACK_NAME="creator-store-$TEST_ID"
PARAMETER_PREFIX="/creator-store/ephemeral/$TEST_ID"
EXPECTED_NODE_TYPE="t3a.medium"
EXPECTED_DATABASE_CLASS="db.t4g.micro"
EXPECTED_NODE_PORT="30080"
NAMESPACE="creator-store"

[[ "$TEST_ID" =~ ^[a-z0-9-]{3,16}$ ]] || \
  fail "TEST_ID must contain 3-16 lowercase letters, digits, or hyphens"
[[ "$EXPECTED_ACCOUNT_ID" =~ ^[0-9]{12}$ ]] || \
  fail "EXPECTED_ACCOUNT_ID must contain exactly 12 digits"

require_command aws

actual_account_id="$(aws sts get-caller-identity --query Account --output text)"
[ "$actual_account_id" = "$EXPECTED_ACCOUNT_ID" ] || \
  fail "refusing to verify unexpected AWS account $actual_account_id"
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
  local eks_count rds_count ec2_count ebs_count eni_count nat_count vpc_count
  local security_group_count load_balancer_count ssm_count orphan_total

  eks_count="$(tagged_resource_count eks:cluster)"
  rds_count="$(tagged_resource_count rds:db)"
  ec2_count="$(aws ec2 describe-instances \
    --region "$AWS_REGION" \
    --filters \
      "Name=tag:TestId,Values=$TEST_ID" \
      'Name=instance-state-name,Values=pending,running,shutting-down,stopping,stopped' \
    --query 'length(Reservations[].Instances[])' \
    --output text)"
  ebs_count="$(aws ec2 describe-volumes \
    --region "$AWS_REGION" \
    --filters "Name=tag:TestId,Values=$TEST_ID" \
    --query 'length(Volumes)' \
    --output text)"
  eni_count="$(aws ec2 describe-network-interfaces \
    --region "$AWS_REGION" \
    --filters "Name=tag:TestId,Values=$TEST_ID" \
    --query 'length(NetworkInterfaces)' \
    --output text)"
  nat_count="$(aws ec2 describe-nat-gateways \
    --region "$AWS_REGION" \
    --filter \
      "Name=tag:TestId,Values=$TEST_ID" \
      'Name=state,Values=pending,failed,available,deleting' \
    --query 'length(NatGateways)' \
    --output text)"
  vpc_count="$(aws ec2 describe-vpcs \
    --region "$AWS_REGION" \
    --filters "Name=tag:TestId,Values=$TEST_ID" \
    --query 'length(Vpcs)' \
    --output text)"
  security_group_count="$(aws ec2 describe-security-groups \
    --region "$AWS_REGION" \
    --filters "Name=tag:TestId,Values=$TEST_ID" \
    --query 'length(SecurityGroups)' \
    --output text)"
  load_balancer_count="$(tagged_resource_count \
    elasticloadbalancing:loadbalancer \
    elasticloadbalancing:loadbalancer/app \
    elasticloadbalancing:loadbalancer/net \
    elasticloadbalancing:loadbalancer/gwy)"
  ssm_count="$(aws ssm describe-parameters \
    --region "$AWS_REGION" \
    --parameter-filters "Key=tag:TestId,Option=Equals,Values=$TEST_ID" \
    --query 'length(Parameters)' \
    --output text)"

  assert_count "tagged EKS cluster count" "$eks_count"
  assert_count "tagged RDS instance count" "$rds_count"
  assert_count "tagged EC2 instance count" "$ec2_count"
  assert_count "tagged EBS volume count" "$ebs_count"
  assert_count "tagged ENI count" "$eni_count"
  assert_count "tagged NAT Gateway count" "$nat_count"
  assert_count "tagged VPC count" "$vpc_count"
  assert_count "tagged security group count" "$security_group_count"
  assert_count "tagged load balancer count" "$load_balancer_count"
  assert_count "tagged SSM parameter count" "$ssm_count"

  printf '\nPost-destroy orphan audit for TestId=%s in %s:\n' "$TEST_ID" "$AWS_REGION"
  printf '  EKS clusters:       %s\n' "$eks_count"
  printf '  RDS instances:      %s\n' "$rds_count"
  printf '  EC2 instances:      %s\n' "$ec2_count"
  printf '  EBS volumes:        %s\n' "$ebs_count"
  printf '  network interfaces: %s\n' "$eni_count"
  printf '  NAT Gateways:       %s\n' "$nat_count"
  printf '  VPCs:               %s\n' "$vpc_count"
  printf '  security groups:    %s\n' "$security_group_count"
  printf '  load balancers:     %s\n' "$load_balancer_count"
  printf '  SSM parameters:     %s\n' "$ssm_count"

  orphan_total=$((eks_count + rds_count + ec2_count + ebs_count + eni_count + nat_count + vpc_count + security_group_count + load_balancer_count + ssm_count))
  [ "$orphan_total" -eq 0 ] || \
    fail "$orphan_total tagged resource(s) remain; no deletion was attempted"
  pass "no tagged EKS, RDS, EC2, EBS, ENI, NAT, VPC, security-group, load-balancer, or SSM resources remain"
}

if [ "$MODE" = "post-destroy" ]; then
  verify_post_destroy
  exit 0
fi

require_command kubectl
require_command curl
require_command grep

cluster_description="$(aws eks describe-cluster \
  --region "$AWS_REGION" \
  --name "$STACK_NAME" \
  --query '[cluster.status,cluster.resourcesVpcConfig.endpointPublicAccess,cluster.resourcesVpcConfig.endpointPrivateAccess,cluster.resourcesVpcConfig.vpcId,cluster.tags.TestId]' \
  --output text)"
read -r cluster_status cluster_public_access cluster_private_access cluster_vpc_id cluster_test_id <<EOF
$cluster_description
EOF

assert_equal "EKS status" "$cluster_status" "ACTIVE"
case "$cluster_public_access" in
  True|true) pass "EKS public endpoint is enabled" ;;
  *) fail "EKS public endpoint is not enabled" ;;
esac
case "$cluster_private_access" in
  True|true) pass "EKS private endpoint is enabled" ;;
  *) fail "EKS private endpoint is not enabled" ;;
esac
assert_equal "EKS TestId tag" "$cluster_test_id" "$TEST_ID"
[[ "$cluster_vpc_id" =~ ^vpc-[0-9a-f]+$ ]] || \
  fail "EKS returned an invalid VPC ID: $cluster_vpc_id"

cluster_public_cidrs="$(aws eks describe-cluster \
  --region "$AWS_REGION" \
  --name "$STACK_NAME" \
  --query 'cluster.resourcesVpcConfig.publicAccessCidrs' \
  --output text)"
[ -n "$cluster_public_cidrs" ] && [ "$cluster_public_cidrs" != "None" ] || \
  fail "EKS public endpoint has no source CIDR allowlist"
for cidr in $cluster_public_cidrs; do
  [[ "$cidr" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/32$ ]] || \
    fail "EKS public endpoint CIDR must be an IPv4 /32, found $cidr"
done
pass "EKS public endpoint is restricted to IPv4 /32 CIDRs"

database_description="$(aws rds describe-db-instances \
  --region "$AWS_REGION" \
  --db-instance-identifier "$STACK_NAME" \
  --query 'DBInstances[0].[DBInstanceStatus,PubliclyAccessible,MultiAZ,DBInstanceClass,DBInstanceArn]' \
  --output text)"
read -r database_status database_public database_multi_az database_class database_arn <<EOF
$database_description
EOF

assert_equal "RDS status" "$database_status" "available"
case "$database_public" in
  False|false) pass "RDS is private" ;;
  *) fail "RDS must not be publicly accessible" ;;
esac
case "$database_multi_az" in
  False|false) pass "RDS is Single-AZ" ;;
  *) fail "RDS must be Single-AZ for the disposable stack" ;;
esac
assert_equal "RDS instance class" "$database_class" "$EXPECTED_DATABASE_CLASS"

database_test_id="$(aws rds list-tags-for-resource \
  --region "$AWS_REGION" \
  --resource-name "$database_arn" \
  --query "TagList[?Key=='TestId'].Value | [0]" \
  --output text)"
assert_equal "RDS TestId tag" "$database_test_id" "$TEST_ID"

nonterminated_worker_count="$(aws ec2 describe-instances \
  --region "$AWS_REGION" \
  --filters \
    "Name=tag:eks:cluster-name,Values=$STACK_NAME" \
    'Name=instance-state-name,Values=pending,running,shutting-down,stopping,stopped' \
  --query 'length(Reservations[].Instances[])' \
  --output text)"
running_worker_count="$(aws ec2 describe-instances \
  --region "$AWS_REGION" \
  --filters \
    "Name=tag:eks:cluster-name,Values=$STACK_NAME" \
    'Name=instance-state-name,Values=running' \
  --query 'length(Reservations[].Instances[])' \
  --output text)"
assert_equal "non-terminated EKS worker count" "$nonterminated_worker_count" "1"
assert_equal "running EKS worker count" "$running_worker_count" "1"

worker_description="$(aws ec2 describe-instances \
  --region "$AWS_REGION" \
  --filters \
    "Name=tag:eks:cluster-name,Values=$STACK_NAME" \
    'Name=instance-state-name,Values=running' \
  --query 'Reservations[0].Instances[0].[InstanceId,InstanceType,PublicIpAddress]' \
  --output text)"
read -r worker_id worker_type worker_public_ip <<EOF
$worker_description
EOF

[[ "$worker_id" =~ ^i-[0-9a-f]+$ ]] || fail "worker instance ID is invalid: $worker_id"
assert_equal "worker instance type" "$worker_type" "$EXPECTED_NODE_TYPE"
[[ "$worker_public_ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || \
  fail "worker does not have the expected public IPv4 address"
pass "worker has a public IPv4 address"

worker_test_id="$(aws ec2 describe-tags \
  --region "$AWS_REGION" \
  --filters "Name=resource-id,Values=$worker_id" 'Name=key,Values=TestId' \
  --query 'Tags[0].Value' \
  --output text)"
assert_equal "worker TestId tag" "$worker_test_id" "$TEST_ID"

nat_count="$(aws ec2 describe-nat-gateways \
  --region "$AWS_REGION" \
  --filter \
    "Name=vpc-id,Values=$cluster_vpc_id" \
    'Name=state,Values=pending,failed,available,deleting' \
  --query 'length(NatGateways)' \
  --output text)"
v2_load_balancer_count="$(aws elbv2 describe-load-balancers \
  --region "$AWS_REGION" \
  --query "length(LoadBalancers[?VpcId=='$cluster_vpc_id'])" \
  --output text)"
classic_load_balancer_count="$(aws elb describe-load-balancers \
  --region "$AWS_REGION" \
  --query "length(LoadBalancerDescriptions[?VPCId=='$cluster_vpc_id'])" \
  --output text)"
assert_equal "NAT Gateway count in the test VPC" "$nat_count" "0"
assert_equal "ALB/NLB/Gateway Load Balancer count in the test VPC" "$v2_load_balancer_count" "0"
assert_equal "Classic Load Balancer count in the test VPC" "$classic_load_balancer_count" "0"

worker_security_groups="$(aws ec2 describe-instances \
  --region "$AWS_REGION" \
  --instance-ids "$worker_id" \
  --query 'Reservations[0].Instances[0].SecurityGroups[].GroupId' \
  --output text)"
[ -n "$worker_security_groups" ] && [ "$worker_security_groups" != "None" ] || \
  fail "worker has no discoverable security groups"

nodeport_cidr_count=0
for security_group_id in $worker_security_groups; do
  security_group_rules="$(aws ec2 describe-security-group-rules \
    --region "$AWS_REGION" \
    --filters "Name=group-id,Values=$security_group_id" 'Name=is-egress,Values=false' \
    --query 'SecurityGroupRules[].[IpProtocol,FromPort,ToPort,CidrIpv4,CidrIpv6]' \
    --output text)"

  while read -r protocol from_port to_port cidr_ipv4 cidr_ipv6; do
    [ -n "${protocol:-}" ] || continue
    rule_covers_nodeport="false"
    if [ "$protocol" = "-1" ]; then
      rule_covers_nodeport="true"
    elif { [ "$protocol" = "tcp" ] || [ "$protocol" = "6" ]; } && \
      [[ "$from_port" =~ ^[0-9]+$ ]] && [[ "$to_port" =~ ^[0-9]+$ ]] && \
      [ "$from_port" -le "$EXPECTED_NODE_PORT" ] && [ "$to_port" -ge "$EXPECTED_NODE_PORT" ]; then
      rule_covers_nodeport="true"
    fi

    if [ "$rule_covers_nodeport" = "true" ]; then
      [ "${cidr_ipv6:-None}" = "None" ] || \
        fail "NodePort $EXPECTED_NODE_PORT has IPv6 CIDR ingress: $cidr_ipv6"
      if [ "${cidr_ipv4:-None}" != "None" ]; then
        [[ "$cidr_ipv4" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/32$ ]] || \
          fail "NodePort $EXPECTED_NODE_PORT ingress must use IPv4 /32 CIDRs, found $cidr_ipv4"
        nodeport_cidr_count=$((nodeport_cidr_count + 1))
      fi
    fi
  done <<EOF
$security_group_rules
EOF
done

[ "$nodeport_cidr_count" -ge 1 ] || \
  fail "no IPv4 /32 security-group rule allows NodePort $EXPECTED_NODE_PORT"
pass "NodePort $EXPECTED_NODE_PORT is limited to $nodeport_cidr_count IPv4 /32 allowlist rule(s)"

expires_at="$(aws ssm get-parameter \
  --region "$AWS_REGION" \
  --name "$PARAMETER_PREFIX/expires-at" \
  --query 'Parameter.Value' \
  --output text)"
[ -n "$expires_at" ] && [ "$expires_at" != "None" ] || \
  fail "expiration parameter is missing or empty"
pass "expiration marker exists at $PARAMETER_PREFIX/expires-at"

KUBECONFIG_FILE="$(mktemp "${TMPDIR:-/tmp}/creator-store-verify-kubeconfig.XXXXXX")"
cleanup() {
  if [ -n "${KUBECONFIG_FILE:-}" ] && [ -f "$KUBECONFIG_FILE" ]; then
    rm -f -- "$KUBECONFIG_FILE"
  fi
}
trap cleanup EXIT

if aws eks update-kubeconfig \
  --region "$AWS_REGION" \
  --name "$STACK_NAME" \
  --kubeconfig "$KUBECONFIG_FILE" >/dev/null 2>&1 && \
  kubectl --kubeconfig "$KUBECONFIG_FILE" --request-timeout=10s get --raw=/readyz >/dev/null 2>&1; then
  pass "Kubernetes API is reachable"

  for deployment_name in creator-store-api creator-store-web; do
    kubectl --kubeconfig "$KUBECONFIG_FILE" \
      -n "$NAMESPACE" wait --for=condition=Available \
      "deployment/$deployment_name" --timeout=30s >/dev/null
    deployment_replicas="$(kubectl --kubeconfig "$KUBECONFIG_FILE" \
      -n "$NAMESPACE" get deployment "$deployment_name" \
      -o jsonpath='{.spec.replicas}{" "}{.status.updatedReplicas}{" "}{.status.availableReplicas}')"
    read -r desired_replicas updated_replicas available_replicas <<EOF
$deployment_replicas
EOF
    assert_equal "$deployment_name desired replicas" "$desired_replicas" "1"
    assert_equal "$deployment_name updated replicas" "$updated_replicas" "1"
    assert_equal "$deployment_name available replicas" "$available_replicas" "1"
  done

  api_service_type="$(kubectl --kubeconfig "$KUBECONFIG_FILE" \
    -n "$NAMESPACE" get service creator-store-api -o jsonpath='{.spec.type}')"
  web_service_description="$(kubectl --kubeconfig "$KUBECONFIG_FILE" \
    -n "$NAMESPACE" get service creator-store-web \
    -o jsonpath='{.spec.type}{" "}{.spec.ports[?(@.name=="http")].nodePort}')"
  read -r web_service_type web_node_port <<EOF
$web_service_description
EOF
  assert_equal "API Service type" "$api_service_type" "ClusterIP"
  assert_equal "web Service type" "$web_service_type" "NodePort"
  assert_equal "web NodePort" "$web_node_port" "$EXPECTED_NODE_PORT"

  pvc_description="$(kubectl --kubeconfig "$KUBECONFIG_FILE" \
    -n "$NAMESPACE" get persistentvolumeclaim creator-store-uploads \
    -o jsonpath='{.status.phase}{" "}{.spec.storageClassName}{" "}{.spec.accessModes[0]}')"
  read -r pvc_phase pvc_storage_class pvc_access_mode <<EOF
$pvc_description
EOF
  assert_equal "upload PVC phase" "$pvc_phase" "Bound"
  assert_equal "upload PVC storage class" "$pvc_storage_class" "creator-store-gp3"
  assert_equal "upload PVC access mode" "$pvc_access_mode" "ReadWriteOnce"

  public_origin="http://$worker_public_ip:$EXPECTED_NODE_PORT"
  web_body="$(curl --fail --silent --show-error --connect-timeout 5 --max-time 20 \
    "$public_origin/dashboard/")"
  grep -Fq '<div id="root"></div>' <<< "$web_body" || \
    fail "frontend health response did not contain the expected application root"
  pass "frontend is healthy through the restricted NodePort"

  api_body="$(curl --fail --silent --show-error --connect-timeout 5 --max-time 20 \
    "$public_origin/api/public/alex")"
  grep -Fq '"handle":"alex"' <<< "$api_body" || \
    fail "proxied backend health response did not contain the demo creator contract"
  pass "backend and database are healthy through the frontend proxy"
else
  fail "Kubernetes API is not reachable; workload, PVC, and application verification cannot pass"
fi

printf '\nLive disposable-stack verification passed.\n'
printf 'EKS: %s\nRDS: %s\nWorker: 1 x %s\nNAT Gateways: %s\nLoad balancers: 0\nExpires: %s\n' \
  "$cluster_status" "$database_status" "$worker_type" "$nat_count" "$expires_at"
