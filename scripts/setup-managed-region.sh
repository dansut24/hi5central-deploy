#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

REGION_KEY=${HI5_REGION_KEY:-eu}
ROOT_DOMAIN=${HI5_ROOT_DOMAIN:-$REGION_KEY.hi5central.com}
ACME_EMAIL_VALUE=${HI5_ACME_EMAIL:-admin@hi5central.com}
PLATFORM_TAG_VALUE=${HI5_PLATFORM_TAG:-dev}
TENANT_SLUGS=${HI5_MANAGED_TENANT_SLUGS:-test}
RUNTIME_ENVIRONMENT_VALUE=${HI5_RUNTIME_ENVIRONMENT:-live}
FEATURE_MODE_VALUE=${HI5_FEATURE_MODE:-controlled}
ENV_FILE=${HI5_ENV_FILE:-.env}
FORCE=0

if [ "${1:-}" = "--force" ]; then
  FORCE=1
elif [ -n "${1:-}" ]; then
  echo "Usage: ./scripts/setup-managed-region.sh [--force]" >&2
  exit 2
fi

if [ -s "$ENV_FILE" ] && [ "$FORCE" -ne 1 ]; then
  echo "$ENV_FILE already exists. Use --force only when you intentionally want to replace it." >&2
  exit 1
fi

clean_domain() {
  printf '%s' "$1" | sed -e 's#^https\?://##' -e 's#/$##' | tr '[:upper:]' '[:lower:]'
}

random_hex() {
  dd if=/dev/urandom bs="$1" count=1 2>/dev/null | od -An -tx1 | tr -d ' \n'
}

ROOT_DOMAIN=$(clean_domain "$ROOT_DOMAIN")
[ -n "$ROOT_DOMAIN" ] || { echo "HI5_ROOT_DOMAIN is required." >&2; exit 1; }

case "$RUNTIME_ENVIRONMENT_VALUE" in
  dev|test|uat|live) ;;
  *) echo "HI5_RUNTIME_ENVIRONMENT must be dev, test, uat or live." >&2; exit 1 ;;
esac

case "$FEATURE_MODE_VALUE" in
  all_enabled|controlled) ;;
  *) echo "HI5_FEATURE_MODE must be all_enabled or controlled." >&2; exit 1 ;;
esac

old_ifs=$IFS
IFS=','
for slug in $TENANT_SLUGS; do
  slug=$(printf '%s' "$slug" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
  case "$slug" in
    ''|*[!a-z0-9-]*|-*|*-)
      echo "Invalid managed tenant slug: $slug" >&2
      exit 1
      ;;
  esac
done
IFS=$old_ifs

POSTGRES_PASSWORD_VALUE=$(random_hex 24)
REDIS_PASSWORD_VALUE=$(random_hex 24)
MFA_VALUE=$(random_hex 32)
RMM_RECOVERY_VALUE=$(random_hex 32)
CONNECT_VALUE=$(random_hex 32)
TENANT_INSTALLER_VALUE=$(random_hex 32)
TURN_VALUE=$(random_hex 32)
SETUP_TOKEN_VALUE=$(random_hex 32)
RELEASE_OPERATOR_VALUE=$(random_hex 32)

TURN_HOST_VALUE=${HI5_TURN_HOST:-turn.$ROOT_DOMAIN}

umask 077
cat > "$ENV_FILE" <<EOF
COMPOSE_PROFILES=itsm,rmm,admin
COMPOSE_PROJECT_NAME=hi5central-$REGION_KEY
DEPLOYMENT_MODE=managed
RUNTIME_ENVIRONMENT=$RUNTIME_ENVIRONMENT_VALUE
FEATURE_MODE=$FEATURE_MODE_VALUE
TENANCY_MODE=multi
ROOT_DOMAIN=$ROOT_DOMAIN
PRIMARY_TENANT_SLUG=test
MANAGED_TENANT_SLUGS=$TENANT_SLUGS
BACKGROUND_WORKERS_ENABLED=true

POSTGRES_DB=hi5central
POSTGRES_USER=hi5central
POSTGRES_PASSWORD=$POSTGRES_PASSWORD_VALUE
REDIS_PASSWORD=$REDIS_PASSWORD_VALUE

MFA_ENCRYPTION_KEY=$MFA_VALUE
RMM_RECOVERY_KEY_ENCRYPTION_KEY=$RMM_RECOVERY_VALUE
CONNECT_CODE_HMAC_KEY=$CONNECT_VALUE
TENANT_INSTALLER_HMAC_KEY=$TENANT_INSTALLER_VALUE
TURN_SHARED_SECRET=$TURN_VALUE
INITIAL_SETUP_TOKEN=$SETUP_TOKEN_VALUE
RELEASE_OPERATOR_TOKEN=$RELEASE_OPERATOR_VALUE

APP_URL=https://$ROOT_DOMAIN
PORTAL_URL=https://$ROOT_DOMAIN/portal
RMM_URL=https://rmm.$ROOT_DOMAIN
ADMIN_URL=https://admin.$ROOT_DOMAIN
API_URL=https://api.$ROOT_DOMAIN
DOWNLOADS_URL=https://downloads.$ROOT_DOMAIN
MARKETING_URL=https://$ROOT_DOMAIN
COOKIE_DOMAIN=.$ROOT_DOMAIN

ITSM_ADDRESS=$ROOT_DOMAIN
RMM_ADDRESS=rmm.$ROOT_DOMAIN
ADMIN_ADDRESS=admin.$ROOT_DOMAIN
API_ADDRESS=api.$ROOT_DOMAIN
DOWNLOADS_ADDRESS=downloads.$ROOT_DOMAIN
HELP_ADDRESS=
ACME_EMAIL=$ACME_EMAIL_VALUE

TURN_URL=turn:$TURN_HOST_VALUE:3478
TURN_HOST=$TURN_HOST_VALUE
TURN_REALM=$ROOT_DOMAIN
TURN_EXTERNAL_IP=
TURN_SERVICE_PROFILE=external-turn
TURN_LISTEN_PORT=3478
TURN_RELAY_MIN_PORT=49160
TURN_RELAY_MAX_PORT=49200

GATEWAY_HTTP_PORT=80
GATEWAY_HTTPS_PORT=443

PLATFORM_TAG=$PLATFORM_TAG_VALUE
CONTROL_SERVER_IMAGE=ghcr.io/dansut24/hi5central-platform-api:$PLATFORM_TAG_VALUE
ITSM_IMAGE=ghcr.io/dansut24/hi5central-platform-itsm:$PLATFORM_TAG_VALUE
RMM_IMAGE=ghcr.io/dansut24/hi5central-platform-rmm:$PLATFORM_TAG_VALUE
ADMIN_IMAGE=ghcr.io/dansut24/hi5central-platform-admin:$PLATFORM_TAG_VALUE
AGENT_DEPLOYMENT_ASSETS_IMAGE=ghcr.io/dansut24/hi5central-agent-deployment-assets:$PLATFORM_TAG_VALUE

LICENSING_SERVER_URL=https://licensing.hi5central.com
LICENSING_PUBLIC_KEY_PEM=
LICENSING_PRIVATE_KEY_PEM=
RELEASE_FEED_URL=https://api.hi5central.com/api/releases/v1/feed
RELEASE_SIGNING_PUBLIC_KEY_PEM=
RELEASE_SIGNING_PRIVATE_KEY_PEM=
RELEASE_FEED_SYNC_INTERVAL_MS=21600000
RELEASE_FEED_INITIAL_SYNC_DELAY_MS=45000
LICENSING_REFRESH_INTERVAL_MS=43200000
LICENSING_INITIAL_REFRESH_DELAY_MS=30000

SMTP_HOST=
SMTP_PORT=587
SMTP_USER=
SMTP_PASSWORD=
SMTP_FROM=
MICROSOFT_CLIENT_ID=
MICROSOFT_CLIENT_SECRET=
MICROSOFT_REDIRECT_URI=
EOF

chmod 600 "$ENV_FILE"

./scripts/validate.sh --env-file "$ENV_FILE"

echo
echo "Managed Hi5Central regional configuration created."
echo "  Region key:      $REGION_KEY"
echo "  Root domain:     $ROOT_DOMAIN"
echo "  Runtime:         $RUNTIME_ENVIRONMENT_VALUE"
echo "  Platform tag:    $PLATFORM_TAG_VALUE"
echo "  Tenant routes:   $TENANT_SLUGS"
echo "  External TURN:   $TURN_HOST_VALUE"
echo
echo "Secrets were generated locally in $ENV_FILE and were not printed."
echo "Start with: ./scripts/up.sh"
