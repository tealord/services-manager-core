#!/usr/bin/env bash

_shell_escape_single_quotes() {
  local s="$1"
  s=${s//\'/\'"\'"\'}
  printf "'%s'" "$s"
}

infisical_list_env_vars() {
  local service="$1"
  yq -r ".services.\"$service\".env // {} | to_entries[] | select(.value.from == \"infisical\") | .key" "$DEPLOYMENT_FILE"
}

infisical_validate_service_env() {
  local service="$1"
  local ignore_env_var="${2:-}"

  local missing=()

  local env_var
  while IFS= read -r env_var; do
    [[ -z "$env_var" ]] && continue
    [[ -n "$ignore_env_var" && "$env_var" == "$ignore_env_var" ]] && continue

    local secret_key
    secret_key=$(yq -r ".services.\"$service\".env.\"$env_var\".key // \"$env_var\"" "$DEPLOYMENT_FILE")

    if ! infisical_get "$secret_key" "$service" >/dev/null 2>&1; then
      missing+=("$env_var")
    fi
  done < <(infisical_list_env_vars "$service")

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "error: missing infisical secrets for service '$service': ${missing[*]}" >&2
    return 1
  fi

  return 0
}

infisical_env_prefix() {
  local service="$1"
  local prefix=""

  local env_var
  while IFS= read -r env_var; do
    [[ -z "$env_var" ]] && continue

    local secret_key
    secret_key=$(yq -r ".services.\"$service\".env.\"$env_var\".key // \"$env_var\"" "$DEPLOYMENT_FILE")

    local secret_value
    secret_value=$(infisical_get "$secret_key" "$service")

    prefix+="$env_var=$(_shell_escape_single_quotes "$secret_value") "
  done < <(infisical_list_env_vars "$service")

  printf '%s' "$prefix"
}

infisical_get_service_env() {
  local service="$1"

  infisical_list_secrets "$service" \
    | jq -r '.secrets[]? | "\(.secretKey)=\(.secretValue)"'
}

infisical_set_service_env() {
  local service="$1"
  local env_var="$2"
  local value="$3"

  local secret_key
  secret_key=$(yq -r ".services.\"$service\".env.\"$env_var\".key // \"$env_var\"" "$DEPLOYMENT_FILE")

  infisical_upsert_service_env "$service" "$secret_key" "$value" >/dev/null
}

infisical_upsert_service_env() {
  local service="$1"
  local secret_key="$2"
  local value="$3"

  if infisical_get "$secret_key" "$service" >/dev/null 2>&1; then
    infisical_update "$secret_key" "$value" "$service"
  else
    infisical_set "$secret_key" "$value" "$service"
  fi
}
