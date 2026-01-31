#!/usr/bin/env bash
set -euo pipefail

# fixed environment
INFISICAL_ENV="prod"

_infisical_load_env() {
  local env_file
  env_file="$(realpath "$(dirname "${BASH_SOURCE[0]}")/../../.env")"

  if [[ ! -f "$env_file" ]]; then
    echo "Infisical .env not found at $env_file" >&2
    exit 1
  fi

  # shellcheck disable=SC1090
  source "$env_file"

  : "${INFISICAL_URL:?INFISICAL_URL not set}"
  : "${INFISICAL_CLIENT_ID:?INFISICAL_CLIENT_ID not set}"
  : "${INFISICAL_CLIENT_SECRET:?INFISICAL_CLIENT_SECRET not set}"
  : "${INFISICAL_WORKSPACE_ID:?INFISICAL_WORKSPACE_ID not set}"
}

_infisical_login() {
  _infisical_load_env

  if ! command -v jq >/dev/null 2>&1; then
    echo "error: 'jq' not found (required for infisical auth/json)" >&2
    return 1
  fi

  local response access_token

  response=$(curl -sSf \
    -X POST \
    -H "Content-Type: application/json" \
    --data "{\"clientId\":\"${INFISICAL_CLIENT_ID}\",\"clientSecret\":\"${INFISICAL_CLIENT_SECRET}\"}" \
    "${INFISICAL_URL}/api/v1/auth/universal-auth/login")

  access_token=$(echo "$response" | jq -r '.accessToken // empty')

  if [[ -z "$access_token" ]]; then
    echo "error: infisical auth failed (no accessToken returned)" >&2
    return 1
  fi

  echo "$access_token"
}

_infisical_auth_header() {
  local token
  token="$(_infisical_login)"
  printf 'Authorization: Bearer %s' "$token"
}

_infisical_uri_encode() {
  local s="$1"
  jq -nr --arg s "$s" '$s|@uri'
}

_infisical_service_to_path_segment() {
  local service="${1:-}"
  local segment

  # Only allow alphanumeric, dashes, underscores.
  segment=$(printf '%s' "$service" | tr -c 'A-Za-z0-9_-' '-')
  segment=${segment#-}
  segment=${segment%-}

  if [[ -z "$segment" ]]; then
    echo "error: invalid service name for secretPath: '$service'" >&2
    return 1
  fi

  printf '%s' "$segment"
}

_infisical_secret_path() {
  local service="${1:-}"

  if [[ -z "$service" ]]; then
    echo "/"
    return 0
  fi

  echo "/$(_infisical_service_to_path_segment "$service")"
}

_infisical_list_folders() {
  _infisical_load_env

  local path="${1:-/}"

  curl -sSf \
    -H "$(_infisical_auth_header)" \
    -G \
    --data-urlencode "projectId=${INFISICAL_WORKSPACE_ID}" \
    --data-urlencode "environment=${INFISICAL_ENV}" \
    --data-urlencode "path=${path}" \
    "${INFISICAL_URL}/api/v2/folders"
}

_infisical_create_folder() {
  _infisical_load_env

  local name="$1"
  local path="${2:-/}"

  curl -sSf \
    -X POST \
    -H "$(_infisical_auth_header)" \
    -H 'Content-Type: application/json' \
    --data "$(jq -n \
      --arg projectId "$INFISICAL_WORKSPACE_ID" \
      --arg environment "$INFISICAL_ENV" \
      --arg name "$name" \
      --arg path "$path" \
      '{projectId:$projectId, environment:$environment, name:$name, path:$path}')" \
    "${INFISICAL_URL}/api/v2/folders" >/dev/null
}

_infisical_ensure_secret_path_exists() {
  _infisical_load_env

  local service="${1:-}"

  # Root always exists.
  if [[ -z "$service" ]]; then
    return 0
  fi

  local folder_name
  folder_name="$(_infisical_service_to_path_segment "$service")"

  # list folders under root and check if our folder exists
  local existing
  existing=$(_infisical_list_folders "/" \
    | jq -r --arg n "$folder_name" '.folders[]? | select((.name? // "") == $n) | .id' \
    | head -n 1)

  if [[ -n "$existing" ]]; then
    return 0
  fi

  _infisical_create_folder "$folder_name" "/"
}

infisical_get() {
  _infisical_load_env

  local key="$1"
  local service="${2:-}"
  _infisical_ensure_secret_path_exists "$service"

  local secret_path
  secret_path="$(_infisical_secret_path "$service")"

  local encoded_secret
  encoded_secret="$(_infisical_uri_encode "$key")"

  curl -sSf \
    -H "$(_infisical_auth_header)" \
    -G \
    --data-urlencode "projectId=${INFISICAL_WORKSPACE_ID}" \
    --data-urlencode "environment=${INFISICAL_ENV}" \
    --data-urlencode "secretPath=${secret_path}" \
    "${INFISICAL_URL}/api/v4/secrets/${encoded_secret}" \
    | jq -r '.secret.secretValue // .secretValue // empty'
}

infisical_list_secrets() {
  _infisical_load_env

  local service="${1:-}"
  _infisical_ensure_secret_path_exists "$service"

  local secret_path
  secret_path="$(_infisical_secret_path "$service")"

  curl -sSf \
    -H "$(_infisical_auth_header)" \
    -G \
    --data-urlencode "projectId=${INFISICAL_WORKSPACE_ID}" \
    --data-urlencode "environment=${INFISICAL_ENV}" \
    --data-urlencode "secretPath=${secret_path}" \
    "${INFISICAL_URL}/api/v4/secrets"
}

infisical_set() {
  _infisical_load_env

  local key="$1"
  local value="$2"
  local service="${3:-}"
  _infisical_ensure_secret_path_exists "$service"

  local secret_path
  secret_path="$(_infisical_secret_path "$service")"

  local encoded_secret
  encoded_secret="$(_infisical_uri_encode "$key")"

  curl -sSf \
    -X POST \
    -H "$(_infisical_auth_header)" \
    -H 'Content-Type: application/json' \
    --data "$(jq -n \
      --arg projectId "$INFISICAL_WORKSPACE_ID" \
      --arg environment "$INFISICAL_ENV" \
      --arg secretValue "$value" \
      --arg secretPath "$secret_path" \
      '{projectId:$projectId, environment:$environment, secretValue:$secretValue, secretPath:$secretPath}')" \
    "${INFISICAL_URL}/api/v4/secrets/${encoded_secret}"
}

infisical_update() {
  _infisical_load_env

  local key="$1"
  local value="$2"
  local service="${3:-}"
  _infisical_ensure_secret_path_exists "$service"

  local secret_path
  secret_path="$(_infisical_secret_path "$service")"

  local encoded_secret
  encoded_secret="$(_infisical_uri_encode "$key")"

  curl -sSf \
    -X PATCH \
    -H "$(_infisical_auth_header)" \
    -H 'Content-Type: application/json' \
    --data "$(jq -n \
      --arg projectId "$INFISICAL_WORKSPACE_ID" \
      --arg environment "$INFISICAL_ENV" \
      --arg secretValue "$value" \
      --arg secretPath "$secret_path" \
      '{projectId:$projectId, environment:$environment, secretValue:$secretValue, secretPath:$secretPath}')" \
    "${INFISICAL_URL}/api/v4/secrets/${encoded_secret}"
}
