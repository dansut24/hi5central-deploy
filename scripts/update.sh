#!/bin/sh
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"
./scripts/validate.sh
docker compose pull
docker compose up -d --remove-orphans
docker image prune -f
docker compose ps