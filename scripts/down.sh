#!/bin/sh
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"
if [ -f .env ] && grep -Eq '^RELEASE_EDGE_NETWORK=.+' .env; then
  docker compose -f compose.yml -f compose.release-edge.yml down --remove-orphans
else
  docker compose down --remove-orphans
fi
