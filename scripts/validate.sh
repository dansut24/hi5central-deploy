#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

ENV_FILE=.env
if [ "${1:-}" = "--env-file" ]; then
  ENV_FILE=${2:?--env-file requires a path}
  shift 2
fi

[ -f "$ENV_FILE" ] || {
  echo "Missing $ENV_FILE. Run ./install.sh or copy the matching example file." >&2
  exit 1
}

if grep -Eq '(^|=)(CHANGE_ME|64_HEX_CHARACTERS)$' "$ENV_FILE"; then
  echo "Placeholder secrets remain in $ENV_FILE." >&2
  exit 1
fi

read_env() {
  awk -F= -v key="$1" '$1==key{print substr($0,index($0,"=")+1)}' "$ENV_FILE" | tail -1
}

require_hex64() {
  value=$1
  name=$2
  printf '%s' "$value" | grep -Eq '^[0-9a-fA-F]{64}$' || {
    echo "$name must be 64 hex characters." >&2
    exit 1
  }
}

MFA=$(read_env MFA_ENCRYPTION_KEY)
RMM=$(read_env RMM_RECOVERY_KEY_ENCRYPTION_KEY)
CONNECT=$(read_env CONNECT_CODE_HMAC_KEY)
TENANT_INSTALLER=$(read_env TENANT_INSTALLER_HMAC_KEY)
TURN=$(read_env TURN_SHARED_SECRET)
SETUP_TOKEN=$(read_env INITIAL_SETUP_TOKEN)
PG=$(read_env POSTGRES_PASSWORD)
REDIS=$(read_env REDIS_PASSWORD)
ROOT_DOMAIN=$(read_env ROOT_DOMAIN)
DEPLOYMENT_MODE=$(read_env DEPLOYMENT_MODE)
TENANCY_MODE=$(read_env TENANCY_MODE)
RELEASE_CHANNEL=$(read_env RELEASE_CHANNEL)
RELEASE_OPERATOR_TOKEN=$(read_env RELEASE_OPERATOR_TOKEN)
MANAGED_TENANT_SLUGS=$(read_env MANAGED_TENANT_SLUGS)

require_hex64 "$MFA" MFA_ENCRYPTION_KEY
require_hex64 "$RMM" RMM_RECOVERY_KEY_ENCRYPTION_KEY
require_hex64 "$CONNECT" CONNECT_CODE_HMAC_KEY
[ -z "$TENANT_INSTALLER" ] || require_hex64 "$TENANT_INSTALLER" TENANT_INSTALLER_HMAC_KEY
require_hex64 "$TURN" TURN_SHARED_SECRET
require_hex64 "$SETUP_TOKEN" INITIAL_SETUP_TOKEN

[ "${#PG}" -ge 24 ] || { echo "POSTGRES_PASSWORD must be at least 24 characters." >&2; exit 1; }
[ "${#REDIS}" -ge 24 ] || { echo "REDIS_PASSWORD must be at least 24 characters." >&2; exit 1; }
[ -n "$ROOT_DOMAIN" ] || { echo "ROOT_DOMAIN is required." >&2; exit 1; }

case "$DEPLOYMENT_MODE" in
  self_hosted|managed) ;;
  *) echo "DEPLOYMENT_MODE must be self_hosted or managed." >&2; exit 1 ;;
esac

case "$TENANCY_MODE" in
  single|multi) ;;
  *) echo "TENANCY_MODE must be single or multi." >&2; exit 1 ;;
esac

case "$RELEASE_CHANNEL" in
  stable|early-access|"") ;;
  *) echo "RELEASE_CHANNEL must be stable or early-access." >&2; exit 1 ;;
esac

if [ "$DEPLOYMENT_MODE" = self_hosted ]; then
  for image_key in CONTROL_SERVER_IMAGE ITSM_IMAGE RMM_IMAGE ADMIN_IMAGE AGENT_DEPLOYMENT_ASSETS_IMAGE; do
    image=$(read_env "$image_key")
    case "$image" in
      *:latest)
        echo "$image_key must not use the mutable :latest tag for self-hosted releases." >&2
        exit 1
        ;;
    esac
  done
fi

if [ "$DEPLOYMENT_MODE" = managed ]; then
  require_hex64 "$RELEASE_OPERATOR_TOKEN" RELEASE_OPERATOR_TOKEN

  if [ "$TENANCY_MODE" = multi ] && [ -n "$MANAGED_TENANT_SLUGS" ]; then
    old_ifs=$IFS
    IFS=','
    for slug in $MANAGED_TENANT_SLUGS; do
      slug=$(printf '%s' "$slug" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
      case "$slug" in
        ''|*[!a-z0-9-]*|-*|*-)
          echo "Invalid managed tenant slug: $slug" >&2
          exit 1
          ;;
      esac
    done
    IFS=$old_ifs
  fi
fi

docker compose --env-file "$ENV_FILE" config -q
echo "Hi5Central deployment configuration is valid ($ENV_FILE)."
