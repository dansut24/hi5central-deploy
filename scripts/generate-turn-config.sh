#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ENV_FILE="$ROOT_DIR/.env"
SECRETS_DIR="$ROOT_DIR/secrets"

mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing .env. Copy .env.example to .env first." >&2
  exit 1
fi

ROOT_DOMAIN=$(awk -F= '$1=="ROOT_DOMAIN"{print substr($0,index($0,"=")+1)}' "$ENV_FILE" | tail -1)
TURN_REALM=${TURN_REALM:-$ROOT_DOMAIN}
[ -n "$TURN_REALM" ] || { echo "ROOT_DOMAIN/TURN_REALM is required." >&2; exit 1; }

SECRET_FILE="$SECRETS_DIR/turn_shared_secret"
if [ ! -s "$SECRET_FILE" ]; then
  umask 077
  dd if=/dev/urandom bs=32 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n' > "$SECRET_FILE"
fi
SECRET=$(cat "$SECRET_FILE")

{
  echo "listening-port=3478"
  echo "fingerprint"
  echo "use-auth-secret"
  echo "static-auth-secret=$SECRET"
  echo "realm=$TURN_REALM"
  echo "min-port=49160"
  echo "max-port=49200"
  echo "stale-nonce=600"
  echo "no-loopback-peers"
  echo "no-multicast-peers"
  if [ -n "${TURN_EXTERNAL_IP:-}" ]; then
    echo "external-ip=$TURN_EXTERNAL_IP"
  fi
} > "$SECRETS_DIR/turnserver.conf"
chmod 600 "$SECRET_FILE" "$SECRETS_DIR/turnserver.conf"

echo "TURN secret and configuration are ready in $SECRETS_DIR."