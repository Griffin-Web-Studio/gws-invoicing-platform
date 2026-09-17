#!/usr/bin/env bash

# Detects an available container engine and its compose integration, then
# runs a fresh rebuild of the whole stack: down -v (clean slate) then
# up --build. Podman is preferred when both are available (this project's
# primary target); override with `./scripts/compose-up.sh docker` or the
# CONTAINER_ENGINE env var.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

resolve_compose() {
  case "$1" in
    podman)
      if command -v podman-compose &>/dev/null; then
        echo "podman-compose"
      elif command -v podman &>/dev/null && podman compose version &>/dev/null 2>&1; then
        echo "podman compose"
      fi
      ;;
    docker)
      if command -v docker &>/dev/null && docker compose version &>/dev/null 2>&1; then
        echo "docker compose"
      elif command -v docker-compose &>/dev/null; then
        echo "docker-compose"
      fi
      ;;
  esac
}

requested="${1:-${CONTAINER_ENGINE:-}}"
engine=""
compose_cmd=""

if [ -n "$requested" ]; then
  compose_cmd="$(resolve_compose "$requested")"
  if [ -z "$compose_cmd" ]; then
    echo "error: '$requested' has no working compose integration on this machine." >&2
    exit 1
  fi
  engine="$requested"
else
  for candidate in podman docker; do
    compose_cmd="$(resolve_compose "$candidate")"
    if [ -n "$compose_cmd" ]; then
      engine="$candidate"
      break
    fi
  done
fi

if [ -z "$engine" ]; then
  echo "error: no working container engine found." >&2
  echo "       install one of:" >&2
  echo "         - podman + podman-compose (or podman's own compose plugin)" >&2
  echo "         - docker with the compose plugin (or the standalone docker-compose)" >&2
  exit 1
fi

echo "Using $engine via: $compose_cmd"
echo ""

read -ra compose_argv <<< "$compose_cmd"

"${compose_argv[@]}" down -v
"${compose_argv[@]}" up --build
