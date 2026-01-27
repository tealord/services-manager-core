#!/bin/bash

# fail early
set -euo pipefail

# resolve paths
SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
ROOT_DIR="$(realpath "$SCRIPT_DIR/..")"

# load functions
source "$SCRIPT_DIR/lib/functions.sh"

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
        echo "error: unknown argument: $1"
        exit 1
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
NEEDS_SERVICE=("build" "push" "deploy" "start" "stop" "restart" "status" "console")

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

  # Generate networks configuration
  generate_networks "$SERVICE"

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

    # pull and tag image
    if grep "image: ${TEMPLATE}:\${VERSION}" "$TEMPLATE_DIR/docker-compose.yml" >/dev/null 2>&1; then
      login "$HOST"
      ssh "$HOST" "docker pull $DOCKER_URL/$TEMPLATE:${VERSION}"
      ssh "$HOST" "docker tag $DOCKER_URL/$TEMPLATE:${VERSION} $TEMPLATE:${VERSION}"
      logout "$HOST"
    fi

    # ensure networks exist
    networks_to_create=()

    # get networks from template
    if grep "\${NAME}_net" "$TEMPLATE_DIR/docker-compose.yml" >/dev/null 2>&1; then
        networks_to_create+=("${NAME}_net")
    fi

    # get networks from config
    config_networks=$(yq -r ".services.\"$SERVICE\".networks[]?" "$DEPLOYMENT_FILE" 2>/dev/null)
    if [[ -n "$config_networks" ]]; then
        while IFS= read -r network; do
            networks_to_create+=("$network")
        done <<< "$config_networks"
    fi

    # create networks missing networks
    if [[ ${#networks_to_create[@]} -gt 0 ]]; then
        for network in "${networks_to_create[@]}"; do
            ssh "$HOST" "(docker network inspect $network >/dev/null 2>&1 || docker network create $network)"
        done
    fi

    # render all .env files
    for env_file in "$TEMPLATE_DIR"/.env*; do
        if [[ -f "$env_file" ]]; then
            env_filename=$(basename "$env_file")
            echo "[info] rendering $env_filename"
            load_env_vars "$SERVICE"
            envsubst_fallback < "$env_file" | ssh "$HOST" "cat > '$TARGET_DIR/$env_filename'"
        fi
    done

    # render docker-compose
    base64=$(render_compose | base64)
    ssh "$HOST" "echo $base64 | base64 -d > '$TARGET_DIR/docker-compose.yml'"
    ;;

  start)
    ssh "$HOST" "cd $TARGET_DIR && docker compose up -d"
    ;;

  stop)
    ssh "$HOST" "cd $TARGET_DIR && docker compose stop"
    ;;

  restart)
    ssh "$HOST" "cd $TARGET_DIR && docker compose stop && docker compose up -d"
    ;;

  status)
    ssh "$HOST" "cd $TARGET_DIR && docker compose ps"
    ;;

  console)
    NAME=$(hostname2dockername "$SERVICE")
    ssh -t "$HOST" "cd $TARGET_DIR && docker compose -f $TARGET_DIR/docker-compose.yml exec --user root $NAME bash"
    ;;

  help)
    echo "usage: $0 -s <service> <command>"
    echo ""
    echo "commands:"
    echo "  list         list available templates"
    echo "  build        build docker image for service"
    echo "  push         push docker image to registry"
    echo "  deploy       deploy service to remote host"
    echo "  start        start service remotely"
    echo "  stop         stop service remotely"
    echo "  restart      restart service remotely"
    echo "  status       show remote service status"
    echo "  console      open bash console in service container"
    echo "  help         show this help"
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
