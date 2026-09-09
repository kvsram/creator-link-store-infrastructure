#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/aws-ephemeral-ingress-policy.sh
source "$SCRIPT_DIR/../lib/aws-ephemeral-ingress-policy.sh"

pass_count=0

rule() {
  local protocol="$1" from_port="$2" to_port="$3" ipv4="$4"
  local ipv6="${5:-}" group_id="${6:-}" prefix_list_id="${7:-}"
  jq -n --arg protocol "$protocol" --argjson from_port "$from_port" \
    --argjson to_port "$to_port" --arg ipv4 "$ipv4" --arg ipv6 "$ipv6" \
    --arg group_id "$group_id" --arg prefix_list_id "$prefix_list_id" '
      {IpProtocol: $protocol, FromPort: $from_port, ToPort: $to_port,
       CidrIpv4: (if $ipv4 == "" then null else $ipv4 end),
       CidrIpv6: (if $ipv6 == "" then null else $ipv6 end),
       ReferencedGroupInfo: (if $group_id == "" then null else {GroupId: $group_id} end),
       PrefixListId: (if $prefix_list_id == "" then null else $prefix_list_id end)}'
}

rules() { jq -s '.'; }

expect_accept() {
  aws_ephemeral_ingress_policy_matches "$2" 80 "$3" || {
    printf 'FAIL  expected acceptance: %s\n' "$1" >&2; exit 1;
  }
  pass_count=$((pass_count + 1))
}

expect_reject() {
  if aws_ephemeral_ingress_policy_matches "$2" 80 "$3"; then
    printf 'FAIL  expected rejection: %s\n' "$1" >&2; exit 1
  fi
  pass_count=$((pass_count + 1))
}

ALLOWLIST_ONE="$(rule tcp 80 80 198.51.100.10/32 | rules)"
ALLOWLIST_TWO="$({ rule tcp 80 80 198.51.100.10/32; rule tcp 80 80 203.0.113.20/32; } | rules)"
PUBLIC_HTTP="$(rule tcp 80 80 0.0.0.0/0 | rules)"
PUBLIC_PLUS_ALLOWLIST="$({ rule tcp 80 80 0.0.0.0/0; rule tcp 80 80 198.51.100.10/32; } | rules)"

expect_accept "one /32 in allowlisted mode" allowlisted "$ALLOWLIST_ONE"
expect_accept "multiple /32s in allowlisted mode" allowlisted "$ALLOWLIST_TWO"
expect_accept "one world-open TCP/80 rule in public-test mode" public-test "$PUBLIC_HTTP"
expect_reject "world-open rule in default mode" allowlisted "$PUBLIC_HTTP"
expect_reject "public rule mixed with allowlist" public-test "$PUBLIC_PLUS_ALLOWLIST"
expect_reject "allowlisted rule while public mode is expected" public-test "$ALLOWLIST_ONE"
expect_reject "no inbound rules" allowlisted '[]'
expect_reject "SSH ingress" public-test "$(rule tcp 22 22 0.0.0.0/0 | rules)"
expect_reject "Kubernetes API ingress" public-test "$(rule tcp 6443 6443 0.0.0.0/0 | rules)"
expect_reject "K3s NodePort ingress" public-test "$(rule tcp 30080 30080 0.0.0.0/0 | rules)"
expect_reject "HTTP port range" public-test "$(rule tcp 80 81 0.0.0.0/0 | rules)"
expect_reject "UDP ingress" public-test "$(rule udp 80 80 0.0.0.0/0 | rules)"
expect_reject "IPv6 ingress" public-test "$(rule tcp 80 80 '' ::/0 | rules)"
expect_reject "security-group ingress" public-test "$(rule tcp 80 80 '' '' sg-0123456789abcdef0 | rules)"
expect_reject "prefix-list ingress" public-test "$(rule tcp 80 80 '' '' '' pl-0123456789abcdef0 | rules)"

SIX_ALLOWLIST_RULES="$(for octet in 10 11 12 13 14 15; do rule tcp 80 80 "198.51.100.$octet/32"; done | rules)"
expect_reject "more than five allowlisted addresses" allowlisted "$SIX_ALLOWLIST_RULES"

printf 'PASS  %s AWS ephemeral ingress-policy fixture tests\n' "$pass_count"
