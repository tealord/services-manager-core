#!/usr/bin/env bash

# fail early
set -euo pipefail

# resolve paths
SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
CORE_DIR="$SCRIPT_DIR/services-manager-core"

cmd="${1:-}"

if [[ "$cmd" == "update-core" ]]; then
  echo "Updating services-manager-core…"
  git -C "$CORE_DIR" fetch origin
  git -C "$CORE_DIR" checkout main
  git -C "$CORE_DIR" pull --ff-only
  git -C "$SCRIPT_DIR" add services-manager-core
  git -C "$SCRIPT_DIR" commit -m "Update services-manager-core"
  exit 0
fi

# default: ensure correct pinned version
git -C "$SCRIPT_DIR" submodule update --init --recursive

exec "$CORE_DIR/services.sh" "$@"
