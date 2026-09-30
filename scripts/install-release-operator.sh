#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

CONTROL_ENV=${1:-prod}
case "$CONTROL_ENV" in
  dev|prod) CONTROL_FILE="environments/$CONTROL_ENV.env" ;;
  selfhost) CONTROL_FILE=".env" ;;
  *) echo "Usage: $0 <dev|prod|selfhost>" >&2; exit 2 ;;
esac

[ -s "$CONTROL_FILE" ] || { echo "Missing $CONTROL_FILE." >&2; exit 1; }
[ -s environments/test.env ] || { echo "Missing environments/test.env." >&2; exit 1; }
[ -s environments/uat.env ] || { echo "Missing environments/uat.env." >&2; exit 1; }

read_env() {
  file=$1
  key=$2
  awk -F= -v key="$key" '$1==key{print substr($0,index($0,"=")+1);exit}' "$file"
}

API_URL=$(read_env "$CONTROL_FILE" API_URL)
TOKEN=$(read_env "$CONTROL_FILE" RELEASE_OPERATOR_TOKEN)
[ -n "$API_URL" ] || { echo "API_URL is missing from $CONTROL_FILE." >&2; exit 1; }
echo "$TOKEN" | grep -Eq '^[0-9a-fA-F]{64}$' || { echo "RELEASE_OPERATOR_TOKEN is invalid in $CONTROL_FILE." >&2; exit 1; }

if [ "$CONTROL_ENV" = dev ]; then
  DEFAULT_IMAGE=ghcr.io/dansut24/hi5central-release-operator:dev
else
  DEFAULT_IMAGE=ghcr.io/dansut24/hi5central-release-operator:prod
fi
IMAGE=${RELEASE_OPERATOR_IMAGE:-$DEFAULT_IMAGE}
CONFIG_VOLUME=${RELEASE_OPERATOR_CONFIG_VOLUME:-hi5central-release-operator-config}
CONTAINER=${RELEASE_OPERATOR_CONTAINER:-hi5central-release-operator}
LIVE_ENABLED=${HI5_ENABLE_LIVE_PROMOTION:-0}

docker volume create "$CONFIG_VOLUME" >/dev/null

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM
umask 077
cp environments/test.env "$WORK/test.env"
cp environments/uat.env "$WORK/uat.env"
if [ "$CONTROL_ENV" = selfhost ]; then
  cp .env "$WORK/live.env"
elif [ -s environments/prod.env ]; then
  cp environments/prod.env "$WORK/live.env"
fi
[ -s "$WORK/live.env" ] || { echo "A Live environment file is required by the release operator." >&2; exit 1; }
printf '%s' "$TOKEN" > "$WORK/operator.token"
chmod 600 "$WORK"/*

tar -C "$WORK" -cf - . | docker run --rm -i -v "$CONFIG_VOLUME:/config" alpine:3.22 sh -lc '
  find /config -mindepth 1 -maxdepth 1 -type f -delete
  tar -C /config -xf -
  chmod 600 /config/*
'

docker pull "$IMAGE"
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
docker run -d   --name "$CONTAINER"   --restart unless-stopped   -e "RELEASE_CONTROL_API_URL=$API_URL"   -e "RELEASE_OPERATOR_TOKEN_FILE=/config/operator.token"   -e "LIVE_PROMOTION_ENABLED=$LIVE_ENABLED"   -v /var/run/docker.sock:/var/run/docker.sock   -v "$CONFIG_VOLUME:/config"   "$IMAGE" >/dev/null

echo "Hi5Central Release Operator is running."
echo "  control: $CONTROL_ENV"
echo "  live promotion: $LIVE_ENABLED"
echo "  container: $CONTAINER"
