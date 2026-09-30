#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

ENV_FILE=.env
if [ "${1:-}" = "--env-file" ]; then
  ENV_FILE=${2:?--env-file requires a path}
  shift 2
fi

[ -f "$ENV_FILE" ] || { echo "Missing $ENV_FILE. Run ./install.sh or copy the matching example file." >&2; exit 1; }

if grep -Eq '(^|=)(CHANGE_ME|64_HEX_CHARACTERS)$' "$ENV_FILE"; then
  echo "Placeholder secrets remain in $ENV_FILE." >&2
  exit 1
fi

read_env() {
  awk -F= -v key="$1" '$1==key{print substr($0,index($0,"=")+1)}' "$ENV_FILE" | tail -1
}

MFA=$(read_env MFA_ENCRYPTION_KEY)
RMM=$(read_env RMM_RECOVERY_KEY_ENCRYPTION_KEY)
CONNECT=$(read_env CONNECT_CODE_HMAC_KEY)
TURN=$(read_env TURN_SHARED_SECRET)
PG=$(read_env POSTGRES_PASSWORD)
REDIS=$(read_env REDIS_PASSWORD)
ROOT_DOMAIN=$(read_env ROOT_DOMAIN)
DEPLOYMENT_MODE=$(read_env DEPLOYMENT_MODE)
RELEASE_OPERATOR_TOKEN=$(read_env RELEASE_OPERATOR_TOKEN)

echo "$MFA" | grep -Eq '^[0-9a-fA-F]{64}$' || { echo "MFA_ENCRYPTION_KEY must be 64 hex characters." >&2; exit 1; }
echo "$RMM" | grep -Eq '^[0-9a-fA-F]{64}$' || { echo "RMM_RECOVERY_KEY_ENCRYPTION_KEY must be 64 hex characters." >&2; exit 1; }
echo "$CONNECT" | grep -Eq '^[0-9a-fA-F]{64}$' || { echo "CONNECT_CODE_HMAC_KEY must be 64 hex characters." >&2; exit 1; }
echo "$TURN" | grep -Eq '^[0-9a-fA-F]{64}$' || { echo "TURN_SHARED_SECRET must be 64 hex characters." >&2; exit 1; }
[ "${#PG}" -ge 24 ] || { echo "POSTGRES_PASSWORD must be at least 24 characters." >&2; exit 1; }
[ "${#REDIS}" -ge 24 ] || { echo "REDIS_PASSWORD must be at least 24 characters." >&2; exit 1; }
[ -n "$ROOT_DOMAIN" ] || { echo "ROOT_DOMAIN is required." >&2; exit 1; }
if [ "$DEPLOYMENT_MODE" = "managed" ]; then
  echo "$RELEASE_OPERATOR_TOKEN" | grep -Eq '^[0-9a-fA-F]{64}$' || { echo "Managed RELEASE_OPERATOR_TOKEN must be 64 hex characters." >&2; exit 1; }
fi

docker compose --env-file "$ENV_FILE" config -q
echo "Hi5Central deployment configuration is valid ($ENV_FILE)."
