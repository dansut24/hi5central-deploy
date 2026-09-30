#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

ENVIRONMENT=${1:-}
ACTION=${2:-}
case "$ENVIRONMENT" in
  dev|test|uat|prod) ;;
  *) echo "Usage: ./scripts/environment.sh <dev|test|uat|prod> <config|up|update|down|ps>" >&2; exit 2 ;;
esac

case "$ACTION" in
  config|up|update|down|ps) ;;
  *) echo "Usage: ./scripts/environment.sh <dev|test|uat|prod> <config|up|update|down|ps>" >&2; exit 2 ;;
esac

ENV_FILE="environments/$ENVIRONMENT.env"
[ -f "$ENV_FILE" ] || {
  echo "Missing $ENV_FILE. Copy environments/$ENVIRONMENT.env.example and fill in secrets first." >&2
  exit 1
}

compose() {
  docker compose -f compose.yml -f compose.managed-edge.yml --env-file "$ENV_FILE" "$@"
}
case "$ACTION" in
  config)
    ./scripts/validate.sh --env-file "$ENV_FILE"
    compose config
    ;;
  up)
    ./scripts/validate.sh --env-file "$ENV_FILE"
    compose pull
    compose up -d --remove-orphans
    compose ps
    ;;
  update)
    ./scripts/validate.sh --env-file "$ENV_FILE"
    compose pull
    compose up -d --remove-orphans
    docker image prune -f
    compose ps
    ;;
  down)
    compose down
    ;;
  ps)
    compose ps
    ;;
esac
