#!/bin/bash

# normalize hostname for docker network
hostname2dockername() {
  echo "${1//./-}"
}

# extract and export env vars for given service
load_env_vars() {
  local service="$1"
  local env_exists
  env_exists=$(yq ".services.\"$service\".env" "$DEPLOYMENT_FILE")
  
  if [[ "$env_exists" != "null" ]]; then
    local keys
    keys=$(yq ".services.\"$service\".env | keys | .[]" "$DEPLOYMENT_FILE")
    for key in $keys; do
      export "$key"=$(yq -r ".services.\"$service\".env.\"$key\"" "$DEPLOYMENT_FILE")
    done
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

# render_compose function
render_compose() {
  load_env_vars "$SERVICE"
  
  # Generate base compose content
  local base_compose
  base_compose=$(env \
    NAME="$NAME" \
    SERVICE="$SERVICE" \
    VERSION="$VERSION" \
    NETWORKS="$NETWORKS" \
    NETWORK_DEFINITIONS="$NETWORK_DEFINITIONS" \
    envsubst < "$TEMPLATE_DIR/docker-compose.yml")
  
  # Apply compose modifications
  modify_compose "$SERVICE" "$base_compose"
}

# Generate networks configuration for docker-compose
generate_networks() {
  local service="$1"
  local networks_list
  
  NETWORKS=""
  NETWORK_DEFINITIONS=""
  
  networks_list=$(yq -r ".services.\"$service\".networks[]?" "$DEPLOYMENT_FILE" 2>/dev/null)
  
  if [[ -n "$networks_list" ]]; then
    local first_network=true
    local first_definition=true
    
    while IFS= read -r network; do
      # Networks for services section
      if [[ "$first_network" == true ]]; then
        NETWORKS+="- $network"
        first_network=false
      else
        NETWORKS+=$'\n'"      - $network"
      fi
      
      # Network definitions for networks section
      if [[ "$first_definition" == true ]]; then
        NETWORK_DEFINITIONS+="$network:"$'\n'"    external: true"
        first_definition=false
      else
        NETWORK_DEFINITIONS+=$'\n'"  $network:"$'\n'"    external: true"
      fi
    done <<< "$networks_list"
  fi
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

# envsubst_fallback: expand ${VAR} and ${VAR:-default} using current shell env
# Usage:
#   envsubst_fallback < input.tpl > output
#   envsubst_fallback path/to/input.tpl > output
# Notes:
# - Uses Bash parameter expansion via eval per line to support :- fallback.
# - Template lines must not contain command substitutions or arbitrary code.
# - Intended for controlled template files only.
envsubst_fallback() {
  local _file="${1:-}"
  if [[ -n "$_file" ]]; then
    while IFS= read -r _line; do
      eval "printf '%s\\n' \"$_line\""
    done < "$_file"
  else
    while IFS= read -r _line; do
      eval "printf '%s\\n' \"$_line\""
    done
  fi
}