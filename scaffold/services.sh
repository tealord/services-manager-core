#!/usr/bin/env bash

# fail early
set -euo pipefail

# resolve paths
SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

# ensure submodules are present and up to date
git -C "$SCRIPT_DIR" submodule update --init --recursive

# delegate to core
exec "$SCRIPT_DIR/services-manager-core/services.sh" "$@"
