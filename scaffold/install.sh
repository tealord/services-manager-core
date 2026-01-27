#!/usr/bin/env bash

# fail early
set -euo pipefail

# resolve paths
SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
TARGET_DIR="$(realpath "$SCRIPT_DIR/../..")"

cp "$SCRIPT_DIR/services.yaml.example" "$TARGET_DIR/services.yaml"
cp "$SCRIPT_DIR/.env.example" "$TARGET_DIR/.env"
cp "$SCRIPT_DIR/.gitignore" "$TARGET_DIR/.gitignore"
cp "$SCRIPT_DIR/services.sh" "$TARGET_DIR/services.sh"

chmod +x "$TARGET_DIR/services.sh"
mkdir "$TARGET_DIR/templates"

echo "Service Manager scaffold installed in $TARGET_DIR"
