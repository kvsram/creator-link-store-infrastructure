#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_ROOT="$(cd "$INFRA_ROOT/.." && pwd)"
failures=0

pass() { printf 'PASS  %s\n' "$1"; }
warn() { printf 'WARN  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1" >&2; failures=$((failures + 1)); }

check_command() {
  if command -v "$1" >/dev/null 2>&1; then
    pass "$1 is installed"
  else
    fail "$1 is required"
  fi
}

printf 'Creator Link Store local environment doctor\n'
printf 'Workspace: %s\n\n' "$WORKSPACE_ROOT"

check_command git
check_command docker
check_command curl

if command -v docker >/dev/null 2>&1; then
  if docker compose version >/dev/null 2>&1; then
    pass "Docker Compose v2 is available"
  else
    fail "Docker Compose v2 is required (the command must be: docker compose)"
  fi

  if docker info >/dev/null 2>&1; then
    pass "Docker engine is running"
  else
    fail "Docker is installed but its engine is not reachable; start Docker Desktop or dockerd"
  fi
fi

for component in frontend backend infrastructure; do
  if [ -d "$WORKSPACE_ROOT/$component" ]; then
    pass "$component directory exists"
  else
    fail "$WORKSPACE_ROOT/$component is missing"
  fi
done

for required_file in \
  "$WORKSPACE_ROOT/frontend/Dockerfile" \
  "$WORKSPACE_ROOT/frontend/package-lock.json" \
  "$WORKSPACE_ROOT/backend/Dockerfile" \
  "$WORKSPACE_ROOT/backend/pom.xml" \
  "$INFRA_ROOT/local/docker-compose.yml"; do
  if [ -f "$required_file" ]; then
    pass "found ${required_file#$WORKSPACE_ROOT/}"
  else
    fail "required file is missing: $required_file"
  fi
done

if command -v lsof >/dev/null 2>&1; then
  for port in 3000 8080 5432; do
    if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
      warn "port $port is already in use (this is normal when the local stack is already running)"
    else
      pass "port $port is available"
    fi
  done
fi

if [ "$failures" -ne 0 ]; then
  printf '\nDoctor found %s blocking problem(s).\n' "$failures" >&2
  exit 1
fi

printf '\nDoctor passed. Run: make up && make smoke\n'
