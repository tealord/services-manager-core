#!/bin/bash

# fail early
set -euo pipefail

# resolve paths
SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
ROOT_DIR="$(realpath "$SCRIPT_DIR/..")"

# load functions
source "$SCRIPT_DIR/lib/functions.sh"
source "$SCRIPT_DIR/lib/infisical_api.sh"
source "$SCRIPT_DIR/lib/infisical.sh"

# fixed deployment settings
DEPLOYMENT_FILE="$ROOT_DIR/services.yaml"
DEPLOY_PREFIX="/opt/docker"

# check requirements
if ! command -v yq &> /dev/null; then
  echo "error: 'yq' not found – install with: brew install yq"
  exit 1
fi

# load global env
if [[ -f "$ROOT_DIR/.env" ]]; then
  source "$ROOT_DIR/.env"
else
  echo "error: global .env file not found"
  exit 1
fi

# default args
SERVICE=""
COMMAND=""
COMMAND_ARGS=()

# parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--service)
      SERVICE="$2"
      shift 2
      ;;
    -h|--help)
      COMMAND="help"
      shift
      ;;
    *)
      if [[ -z "$COMMAND" ]]; then
        COMMAND="$1"
        shift
      else
        COMMAND_ARGS+=("$1")
        shift
      fi
      ;;
  esac
done

# require command
if [[ -z "$COMMAND" ]]; then
  echo "error: no command specified"
  echo ""
  "$0" --help
  exit 1
fi

# commands that require a service
NEEDS_SERVICE=("build" "push" "deploy" "start" "stop" "restart" "status" "console" "infisical-get" "infisical-set")

# validate service
if [[ " ${NEEDS_SERVICE[*]} " =~ " $COMMAND " && -z "$SERVICE" ]]; then
  echo "error: service is required for command '$COMMAND'"
  exit 1
fi

# derive target settings
if [[ -n "$SERVICE" ]]; then
  HOST=$(yq -r ".services.\"$SERVICE\".host" "$DEPLOYMENT_FILE")
  TEMPLATE=$(yq -r ".services.\"$SERVICE\".template" "$DEPLOYMENT_FILE")
  VERSION=$(yq -r ".services.\"$SERVICE\".version // \"\"" "$DEPLOYMENT_FILE")
  TARGET_DIR="$DEPLOY_PREFIX/$SERVICE"
  TEMPLATE_DIR="$(resolve_template_dir "$ROOT_DIR" "$TEMPLATE")"
fi

# commands
case "$COMMAND" in

  list)
    yq -r '.services | keys | .[]' "$DEPLOYMENT_FILE"
    ;;

  build)
    cd "$TEMPLATE_DIR"
    docker build -t "$TEMPLATE" .
    ;;

  push)
    login
    docker tag "$TEMPLATE" "$DOCKER_URL/$TEMPLATE"
    docker push "$DOCKER_URL/$TEMPLATE"
    logout
    ;;

  deploy)
    NAME=$(hostname2dockername "$SERVICE")
    ssh "$HOST" "mkdir -p $TARGET_DIR"

    # render and deploy docker-compose.yml
    DOCKER_COMPOSE="$(render_compose)"
    base64=$(printf '%s\n' "$DOCKER_COMPOSE" | base64)
    ssh "$HOST" "echo $base64 | base64 -d > '$TARGET_DIR/docker-compose.yml'"

    # If the template contains a Dockerfile, the image is built locally and pushed to our registry.
    # Therefore the target host must pull (and tag) the image before running docker compose.
    if [[ -f "$TEMPLATE_DIR/Dockerfile" ]]; then
      login "$HOST"
      ssh "$HOST" "docker pull $DOCKER_URL/$TEMPLATE:${VERSION}"
      ssh "$HOST" "docker tag $DOCKER_URL/$TEMPLATE:${VERSION} $TEMPLATE:${VERSION}"
      logout "$HOST"
    fi

    # ensure external networks exist
    external_networks=$(printf '%s\n' "$DOCKER_COMPOSE" \
      | yq -r '.networks // {} | to_entries[] | select(.value.external == true) | (.value.name // .key)' 2>/dev/null)
    if [[ -n "$external_networks" ]]; then
      while IFS= read -r network; do
        ssh "$HOST" "(docker network inspect \"$network\" >/dev/null 2>&1 || docker network create \"$network\")"
      done <<< "$external_networks"
    fi
    ;;

  start)
    infisical_validate_service_env "$SERVICE"
    ENV_PREFIX=$(infisical_env_prefix "$SERVICE")
    ssh "$HOST" "cd $TARGET_DIR && ${ENV_PREFIX} docker compose up -d"
    ;;

  stop)
    ssh "$HOST" "cd $TARGET_DIR && docker compose stop"
    ;;

  restart)
    infisical_validate_service_env "$SERVICE"
    ENV_PREFIX=$(infisical_env_prefix "$SERVICE")
    ssh "$HOST" "cd $TARGET_DIR && docker compose stop && ${ENV_PREFIX} docker compose up -d"
    ;;

  infisical-get)
    infisical_get_service_env "$SERVICE"
    ;;

  infisical-set)
    if [[ ${#COMMAND_ARGS[@]} -ne 2 ]]; then
      echo "usage: $0 -s <service> infisical-set <KEY> <VALUE>"
      exit 1
    fi
    infisical_set_service_env "$SERVICE" "${COMMAND_ARGS[0]}" "${COMMAND_ARGS[1]}"
    ;;

  status)
    ssh "$HOST" "cd $TARGET_DIR && docker compose ps"
    ;;

  console)
    NAME=$(hostname2dockername "$SERVICE")
    ssh -t "$HOST" "cd $TARGET_DIR && docker compose -f $TARGET_DIR/docker-compose.yml exec --user root $NAME sh"
    ;;

  help)
    echo "usage: $0 -s <service> <command>"
    echo ""
    echo "commands:"
    echo "  list          list available templates"
    echo "  build         build docker image for service"
    echo "  push          push docker image to registry"
    echo "  deploy        deploy service to remote host"
    echo "  start         start service remotely"
    echo "  stop          stop service remotely"
    echo "  restart       restart service remotely"
    echo "  status        show remote service status"
    echo "  console       open bash console in service container"
    echo "  infisical-get show infisical env vars for service"
    echo "  infisical-set set infisical env var for service"
    echo "  help          show this help"
    echo ""
    echo "options:"
    echo "  -s, --service <name>  specify the service fqdn"
    echo "  -h, --help            show this help"
    ;;

  *)
    echo "error: unknown command '$COMMAND'"
    exit 1
    ;;
esac
