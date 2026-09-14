#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_ROOT="$(cd "$INFRA_ROOT/.." && pwd)"
GIT_REF="${CREATOR_STORE_GIT_REF:-}"

usage() {
  cat <<'EOF'
Usage: bootstrap-local.sh [--ref BRANCH]

Clone missing frontend/backend siblings from BRANCH, then build and smoke-test
the local stack. Existing checkouts are never switched or modified; when a
branch is requested they must already be on that branch.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --ref)
      [ "$#" -ge 2 ] || { printf '%s\n' '--ref requires a branch name.' >&2; exit 2; }
      GIT_REF="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ -n "$GIT_REF" ] && ! [[ "$GIT_REF" =~ ^[A-Za-z0-9._/-]+$ ]]; then
  printf 'Invalid branch name: %s\n' "$GIT_REF" >&2
  exit 2
fi

clone_if_missing() {
  local name="$1"
  local url="$2"
  local target="$WORKSPACE_ROOT/$name"

  if [ -e "$target" ] && [ ! -d "$target/.git" ]; then
    printf 'Cannot use %s: it exists but is not a Git checkout.\n' "$target" >&2
    exit 1
  fi
  if [ -d "$target/.git" ]; then
    if [ -n "$GIT_REF" ]; then
      local current_ref
      current_ref="$(git -C "$target" branch --show-current)"
      if [ "$current_ref" != "$GIT_REF" ]; then
        printf 'Existing %s checkout is on %s, but --ref requested %s. Switch it explicitly after preserving local changes.\n' \
          "$name" "${current_ref:-detached HEAD}" "$GIT_REF" >&2
        exit 1
      fi
    fi
    printf 'Using existing %s checkout.\n' "$name"
    return
  fi
  printf 'Cloning %s into %s\n' "$url" "$target"
  if [ -n "$GIT_REF" ]; then
    git clone --branch "$GIT_REF" --single-branch "$url" "$target"
  else
    git clone "$url" "$target"
  fi
}

printf 'Preparing Creator Link Store workspace at %s\n' "$WORKSPACE_ROOT"
if [ -n "$GIT_REF" ]; then
  printf 'Requested application branch: %s\n' "$GIT_REF"
fi
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
