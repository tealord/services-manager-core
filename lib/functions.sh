#!/bin/bash

# normalize hostname for docker network
hostname2dockername() {
  echo "${1//./-}"
}

# resolve template directory (prefer custom over core)
#
# Lookup order:
#   1) <root>/templates/<template>
#   2) <root>/services-manager-core/templates/<template>
#
# Prints the resolved directory to stdout.
resolve_template_dir() {
  local root_dir="${1:-}"
  local template="${2:-}"

  if [[ -z "$root_dir" || -z "$template" ]]; then
    echo "error: resolve_template_dir requires: <root_dir> <template>" >&2
    return 1
  fi

  local custom_dir="$root_dir/templates/$template"
  local core_dir="$root_dir/services-manager-core/templates/$template"

  if [[ -d "$custom_dir" ]]; then
    echo "$custom_dir"
    return 0
  fi

  if [[ -d "$core_dir" ]]; then
    echo "$core_dir"
    return 0
  fi

  echo "error: template '$template' not found (checked: $custom_dir, $core_dir)" >&2
  return 1
}

# protect_reserved_env_vars: fail-fast guard for reserved/base variables.
# These variables are used internally for templating and/or orchestration.
#
# Usage:
#   protect_reserved_env_vars <service>
protect_reserved_env_vars() {
  local service="${1:-}"
  local reserved=(
    "NAME"
    "SERVICE"
    "VERSION"
    "NETWORKS"
    "NETWORK_DEFINITIONS"
  )

  local keys
  keys=$(yq -r ".services.\"$service\".env // {} | keys | .[]" "$DEPLOYMENT_FILE" 2>/dev/null || true)

  local conflicts=()
  local r
  for r in "${reserved[@]}"; do
    if [[ -n "$keys" ]] && printf '%s\n' "$keys" | grep -Fxq "$r"; then
      conflicts+=("$r")
    fi
  done

  if (( ${#conflicts[@]} > 0 )); then
    echo "error: services.yaml env for '$service' contains reserved keys: ${conflicts[*]}" >&2
    echo "hint: these keys are reserved for internal templating/orchestration; please rename them." >&2
    return 1
  fi
}

# login to docker registry (local or remote)
login() {
  echo "[info] logging in to registry"
  if [[ -n "${1:-}" ]]; then
    ssh "$1" "echo '$DOCKER_PASS' | docker login --username '$DOCKER_USER' --password-stdin '$DOCKER_URL'"
  else
    echo "$DOCKER_PASS" | docker login --username "$DOCKER_USER" --password-stdin "$DOCKER_URL"
  fi
}

# logout from docker registry
logout() {
  echo "[info] logging out from registry"
  if [[ -n "${1:-}" ]]; then
    ssh "$1" "docker logout '$DOCKER_URL'"
  else
    docker logout "$DOCKER_URL"
  fi
}

# render_compose: render compose from template for the current service.
#
# Current refactor goal:
# - Apply only system/base substitutions (NAME/SERVICE/VERSION/NETWORKS/NETWORK_DEFINITIONS)
# - Do NOT substitute service-specific env vars from services.yaml
# - Apply modify_compose after substitution
render_compose() {
  protect_reserved_env_vars "$SERVICE"

  local NETWORKS
  local NETWORK_DEFINITIONS
  NETWORKS="$(generate_networks "$SERVICE")"
  NETWORK_DEFINITIONS="$(generate_network_definitions "$SERVICE")"

  # Generate base compose content (system vars only)
  local base_compose
  base_compose=$(env \
    NAME="$NAME" \
    SERVICE="$SERVICE" \
    VERSION="$VERSION" \
    NETWORKS="$NETWORKS" \
    NETWORK_DEFINITIONS="$NETWORK_DEFINITIONS" \
    envsubst "\$NAME \$SERVICE \$VERSION \$NETWORKS \$NETWORK_DEFINITIONS" < "$TEMPLATE_DIR/docker-compose.yml")

  # Apply compose modifications
  modify_compose "$SERVICE" "$base_compose"
}

# generate_networks: generates the YAML list fragment used under `services.<svc>.networks:`
# Returns a multi-line string, intended to be inserted at 6-space indentation level.
generate_networks() {
  local service="$1"

  local out=""
  local first_network=true

  while IFS= read -r network; do
    if [[ -z "$network" || "$network" == "null" ]]; then
      continue
    fi

    if [[ "$first_network" == true ]]; then
      out+="- $network"
      first_network=false
    else
      out+=$'\n'"      - $network"
    fi
  done < <(yq -r ".services.\"$service\".networks[]?" "$DEPLOYMENT_FILE" 2>/dev/null || true)

  printf '%s' "$out"
}

# generate_network_definitions: generates the YAML map fragment used under top-level `networks:`
# Returns a multi-line string, intended to be inserted at 2-space indentation level.
generate_network_definitions() {
  local service="$1"

  local out=""
  local first_definition=true

  while IFS= read -r network; do
    if [[ -z "$network" || "$network" == "null" ]]; then
      continue
    fi

    if [[ "$first_definition" == true ]]; then
      out+="$network:"$'\n'"    external: true"
      first_definition=false
    else
      out+=$'\n'"  $network:"$'\n'"    external: true"
    fi
  done < <(yq -r ".services.\"$service\".networks[]?" "$DEPLOYMENT_FILE" 2>/dev/null || true)

  printf '%s' "$out"
}

# modify_compose function
modify_compose() {
  local service="$1"
  local compose_content="$2"

  local add_entries
  add_entries=$(yq -o=json ".services[\"$service\"].modify.add // {}" "$DEPLOYMENT_FILE")

  while IFS= read -r entry; do
    local key value
    key=$(echo "$entry" | base64 --decode | jq -r '.key')
    value=$(echo "$entry" | base64 --decode | jq -r '.value')
    compose_content=$(echo "$compose_content" | yq ".${key} += [\"$value\"]")
  done < <(echo "$add_entries" | jq -r 'to_entries[] | @base64')

  echo "$compose_content"
}