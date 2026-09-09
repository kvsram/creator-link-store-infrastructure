#!/usr/bin/env bash

# Pure policy check shared by the live AWS verifier and its fixture tests.
# The caller supplies the complete set of inbound security-group rules as JSON.
aws_ephemeral_ingress_policy_matches() {
  local access_mode="$1"
  local expected_http_port="$2"
  local rules_json="$3"
  local rule_count

  case "$access_mode" in
    allowlisted|public-test) ;;
    *) return 2 ;;
  esac

  [[ "$expected_http_port" =~ ^[0-9]+$ ]] || return 2
  jq -e 'type == "array"' <<< "$rules_json" >/dev/null 2>&1 || return 2
  rule_count="$(jq 'length' <<< "$rules_json")"
  [ "$rule_count" -ge 1 ] || return 1

  # Reject SSH, the Kubernetes API, NodePorts, IPv6, group references, prefix
  # lists, port ranges, UDP, and every other ingress path in both modes.
  jq -e --argjson port "$expected_http_port" '
    all(.[];
      .IpProtocol == "tcp" and
      .FromPort == $port and
      .ToPort == $port and
      (.CidrIpv4 | type == "string") and
      (.CidrIpv6 == null) and
      (.ReferencedGroupInfo == null) and
      (.PrefixListId == null)
    )
  ' <<< "$rules_json" >/dev/null || return 1

  if [ "$access_mode" = "public-test" ]; then
    [ "$rule_count" -eq 1 ] || return 1
    jq -e 'all(.[]; .CidrIpv4 == "0.0.0.0/0")' <<< "$rules_json" >/dev/null
    return
  fi

  [ "$rule_count" -le 5 ] || return 1
  jq -e '
    all(.[];
      .CidrIpv4 != "0.0.0.0/0" and
      (.CidrIpv4 | test("^([0-9]{1,3}\\.){3}[0-9]{1,3}/32$"))
    )
  ' <<< "$rules_json" >/dev/null
}
