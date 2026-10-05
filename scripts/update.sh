#!/bin/sh
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"
compose() {
  if [ -f .env ] && grep -Eq '^RELEASE_EDGE_NETWORK=.+' .env; then
    docker compose -f compose.yml -f compose.release-edge.yml "$@"
  else
    docker compose "$@"
  fi
}
./scripts/validate.sh
compose pull
compose up -d --remove-orphans
docker image prune -f
compose ps
