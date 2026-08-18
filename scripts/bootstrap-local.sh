#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_ROOT="$(cd "$INFRA_ROOT/.." && pwd)"

clone_if_missing() {
  local name="$1"
  local url="$2"
  local target="$WORKSPACE_ROOT/$name"

  if [ -e "$target" ] && [ ! -d "$target/.git" ]; then
    printf 'Cannot use %s: it exists but is not a Git checkout.\n' "$target" >&2
    exit 1
  fi
  if [ -d "$target/.git" ]; then
    printf 'Using existing %s checkout.\n' "$name"
    return
  fi
  printf 'Cloning %s into %s\n' "$url" "$target"
  git clone "$url" "$target"
}

printf 'Preparing Creator Link Store workspace at %s\n' "$WORKSPACE_ROOT"
clone_if_missing frontend https://github.com/kvsram/creator-link-store-frontend.git
clone_if_missing backend https://github.com/kvsram/creator-link-store-backend.git

"$SCRIPT_DIR/doctor.sh"
for attempt in 1 2 3; do
  if docker compose -f "$INFRA_ROOT/local/docker-compose.yml" up -d --build; then
    break
  fi
  if [ "$attempt" -eq 3 ]; then
    printf 'Container build/start failed after %s attempts. Check registry/network access and Docker logs.\n' "$attempt" >&2
    exit 1
  fi
  printf 'Container build/start attempt %s failed; retrying after a short registry backoff.\n' "$attempt" >&2
  sleep $((attempt * 5))
done
"$SCRIPT_DIR/smoke-test.sh"

printf '\nLocal environment is ready:\n'
printf '  Admin:        http://localhost:3000/dashboard/\n'
printf '  Public store: http://localhost:3000/alex\n'
printf '  API health:   http://localhost:8080/health\n'
