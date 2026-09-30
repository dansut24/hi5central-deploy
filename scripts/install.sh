#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

DOMAIN=${HI5_ROOT_DOMAIN:-}
ACME_EMAIL_VALUE=${HI5_ACME_EMAIL:-}
PRODUCTS=${HI5_PRODUCTS:-itsm,rmm,admin}
SCHEME=${HI5_SCHEME:-https}
FORCE=0
CONFIGURE_ONLY=0
SKIP_PULL=${HI5_SKIP_PULL:-0}
ENV_FILE="$ROOT_DIR/.env"

usage() {
  cat <<'EOF'
Usage: ./install.sh [options]

One-run Hi5Central self-host bootstrap.

Options:
  --domain DOMAIN         Base domain, e.g. example.com
  --email EMAIL           ACME contact email (HTTPS deployments)
  --products LIST         Comma-separated: itsm,rmm,admin (default: all)
  --http                  Use HTTP instead of automatic HTTPS
  --force                 Replace an existing .env with a new configuration
  --configure-only        Generate/validate configuration but do not start
  --skip-pull             Do not pull images before startup
  -h, --help              Show this help

All values can also be supplied with HI5_* environment variables for
non-interactive/bootstrap automation.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --domain) DOMAIN=${2:?--domain requires a value}; shift 2 ;;
    --email) ACME_EMAIL_VALUE=${2:?--email requires a value}; shift 2 ;;
    --products) PRODUCTS=${2:?--products requires a value}; shift 2 ;;
    --http) SCHEME=http; shift ;;
    --force) FORCE=1; shift ;;
    --configure-only) CONFIGURE_ONLY=1; shift ;;
    --skip-pull) SKIP_PULL=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

command -v docker >/dev/null 2>&1 || { echo "Docker is required." >&2; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "Docker Compose v2 is required." >&2; exit 1; }

random_hex() {
  dd if=/dev/urandom bs="$1" count=1 2>/dev/null | od -An -tx1 | tr -d ' \n'
}

clean_domain() {
  printf '%s' "$1" | sed -e 's#^https\?://##' -e 's#/$##' | tr '[:upper:]' '[:lower:]'
}

validate_products() {
  old_ifs=$IFS
  IFS=','
  for product in $1; do
    case "$product" in
      itsm|rmm|admin) ;;
      *) echo "Unsupported product in --products: $product" >&2; exit 1 ;;
    esac
  done
  IFS=$old_ifs
}

if [ -f "$ENV_FILE" ] && [ "$FORCE" -ne 1 ]; then
  echo "Using existing $ENV_FILE (pass --force to regenerate it)."
else
  if [ -z "$DOMAIN" ] && [ -t 0 ]; then
    printf "Base domain (for example, hi5.example.com): "
    IFS= read -r DOMAIN
  fi
  [ -n "$DOMAIN" ] || { echo "A base domain is required (--domain or HI5_ROOT_DOMAIN)." >&2; exit 1; }
  DOMAIN=$(clean_domain "$DOMAIN")
  printf '%s' "$DOMAIN" | grep -Eq '^[a-z0-9][a-z0-9.-]*[a-z0-9]$|^[a-z0-9]$' || {
    echo "Invalid base domain: $DOMAIN" >&2; exit 1;
  }

  validate_products "$PRODUCTS"
  case "$SCHEME" in https|http) ;; *) echo "HI5_SCHEME must be http or https." >&2; exit 1 ;; esac

  if [ "$SCHEME" = https ] && [ -z "$ACME_EMAIL_VALUE" ] && [ -t 0 ]; then
    printf "ACME email [admin@$DOMAIN]: "
    IFS= read -r ACME_EMAIL_VALUE
  fi
  ACME_EMAIL_VALUE=${ACME_EMAIL_VALUE:-admin@$DOMAIN}

  ITSM_HOST=${HI5_ITSM_HOST:-itsm.$DOMAIN}
  RMM_HOST=${HI5_RMM_HOST:-rmm.$DOMAIN}
  ADMIN_HOST=${HI5_ADMIN_HOST:-admin.$DOMAIN}
  API_HOST=${HI5_API_HOST:-api.$DOMAIN}
  DOWNLOADS_HOST=${HI5_DOWNLOADS_HOST:-downloads.$DOMAIN}
  TURN_HOST_VALUE=${HI5_TURN_HOST:-turn.$DOMAIN}

  APP_URL_VALUE="$SCHEME://$ITSM_HOST"
  RMM_URL_VALUE="$SCHEME://$RMM_HOST"
  ADMIN_URL_VALUE="$SCHEME://$ADMIN_HOST"
  API_URL_VALUE="$SCHEME://$API_HOST"
  DOWNLOADS_URL_VALUE="$SCHEME://$DOWNLOADS_HOST"

  if [ "$SCHEME" = http ]; then
    ITSM_ADDRESS_VALUE="http://$ITSM_HOST"
    RMM_ADDRESS_VALUE="http://$RMM_HOST"
    ADMIN_ADDRESS_VALUE="http://$ADMIN_HOST"
    API_ADDRESS_VALUE="http://$API_HOST"
    DOWNLOADS_ADDRESS_VALUE="http://$DOWNLOADS_HOST"
  else
    ITSM_ADDRESS_VALUE="$ITSM_HOST"
    RMM_ADDRESS_VALUE="$RMM_HOST"
    ADMIN_ADDRESS_VALUE="$ADMIN_HOST"
    API_ADDRESS_VALUE="$API_HOST"
    DOWNLOADS_ADDRESS_VALUE="$DOWNLOADS_HOST"
  fi

  POSTGRES_PASSWORD_VALUE=$(random_hex 24)
  REDIS_PASSWORD_VALUE=$(random_hex 24)
  MFA_KEY=$(random_hex 32)
  RMM_KEY=$(random_hex 32)
  CONNECT_KEY=$(random_hex 32)

  umask 077
  cat > "$ENV_FILE" <<EOF
COMPOSE_PROFILES=$PRODUCTS
COMPOSE_PROJECT_NAME=${HI5_PROJECT_NAME:-hi5central}
DEPLOYMENT_MODE=self_hosted
TENANCY_MODE=single
ROOT_DOMAIN=$DOMAIN
PRIMARY_TENANT_SLUG=${HI5_PRIMARY_TENANT_SLUG:-local}
BACKGROUND_WORKERS_ENABLED=${HI5_BACKGROUND_WORKERS_ENABLED:-true}

POSTGRES_DB=${HI5_POSTGRES_DB:-hi5central}
POSTGRES_USER=${HI5_POSTGRES_USER:-hi5central}
POSTGRES_PASSWORD=$POSTGRES_PASSWORD_VALUE
REDIS_PASSWORD=$REDIS_PASSWORD_VALUE

MFA_ENCRYPTION_KEY=$MFA_KEY
RMM_RECOVERY_KEY_ENCRYPTION_KEY=$RMM_KEY
CONNECT_CODE_HMAC_KEY=$CONNECT_KEY

APP_URL=$APP_URL_VALUE
PORTAL_URL=$APP_URL_VALUE/portal
RMM_URL=$RMM_URL_VALUE
ADMIN_URL=$ADMIN_URL_VALUE
API_URL=$API_URL_VALUE
DOWNLOADS_URL=$DOWNLOADS_URL_VALUE
TURN_URL=turn:$TURN_HOST_VALUE:${HI5_TURN_PUBLIC_PORT:-3478}
TURN_HOST=$TURN_HOST_VALUE
MARKETING_URL=$APP_URL_VALUE
COOKIE_DOMAIN=

ITSM_ADDRESS=$ITSM_ADDRESS_VALUE
RMM_ADDRESS=$RMM_ADDRESS_VALUE
ADMIN_ADDRESS=$ADMIN_ADDRESS_VALUE
API_ADDRESS=$API_ADDRESS_VALUE
DOWNLOADS_ADDRESS=$DOWNLOADS_ADDRESS_VALUE
ACME_EMAIL=$ACME_EMAIL_VALUE

GATEWAY_HTTP_PORT=${HI5_GATEWAY_HTTP_PORT:-80}
GATEWAY_HTTPS_PORT=${HI5_GATEWAY_HTTPS_PORT:-443}
TURN_LISTEN_PORT=${HI5_TURN_LISTEN_PORT:-3478}
TURN_RELAY_MIN_PORT=${HI5_TURN_RELAY_MIN_PORT:-49160}
TURN_RELAY_MAX_PORT=${HI5_TURN_RELAY_MAX_PORT:-49200}

# Optional absolute host bind paths. Defaults keep everything self-contained
# in this deployment directory; these are useful for external config storage
# and remote-admin environments where the Docker daemon sees another path.
CADDYFILE_PATH=${HI5_CADDYFILE_PATH:-./Caddyfile}
TURN_CONFIG_PATH=${HI5_TURN_CONFIG_PATH:-./secrets/turnserver.conf}
TURN_SHARED_SECRET_PATH=${HI5_TURN_SHARED_SECRET_PATH:-./secrets/turn_shared_secret}

CONTROL_SERVER_IMAGE=${HI5_CONTROL_SERVER_IMAGE:-ghcr.io/dansut24/hi5central-control-server:latest}
ITSM_IMAGE=${HI5_ITSM_IMAGE:-ghcr.io/dansut24/hi5central-itsm:latest}
RMM_IMAGE=${HI5_RMM_IMAGE:-ghcr.io/dansut24/hi5central-rmm:latest}
ADMIN_IMAGE=${HI5_ADMIN_IMAGE:-ghcr.io/dansut24/hi5central-admin:latest}

SELF_HOST_EVALUATION_PRODUCTS=${HI5_EVALUATION_PRODUCTS:-itsm,rmm}
SELF_HOST_EVALUATION_USER_LIMIT=${HI5_EVALUATION_USER_LIMIT:-10}
SELF_HOST_EVALUATION_DEVICE_LIMIT=${HI5_EVALUATION_DEVICE_LIMIT:-25}

SMTP_HOST=${HI5_SMTP_HOST:-}
SMTP_PORT=${HI5_SMTP_PORT:-587}
SMTP_USER=${HI5_SMTP_USER:-}
SMTP_PASSWORD=${HI5_SMTP_PASSWORD:-}
SMTP_FROM=${HI5_SMTP_FROM:-}
MICROSOFT_CLIENT_ID=${HI5_MICROSOFT_CLIENT_ID:-}
MICROSOFT_CLIENT_SECRET=${HI5_MICROSOFT_CLIENT_SECRET:-}
MICROSOFT_REDIRECT_URI=${HI5_MICROSOFT_REDIRECT_URI:-}
EOF
  chmod 600 "$ENV_FILE"

  TURN_EXTERNAL_IP=${HI5_TURN_EXTERNAL_IP:-} ./scripts/generate-turn-config.sh >/dev/null
  echo "Generated secure deployment configuration in $ENV_FILE."
fi

./scripts/validate.sh

if [ "$CONFIGURE_ONLY" -eq 1 ]; then
  echo "Configuration complete. Run ./scripts/up.sh when ready."
  exit 0
fi

if [ "$SKIP_PULL" != 1 ]; then
  echo "Pulling Hi5Central container images…"
  docker compose pull
fi

echo "Starting PostgreSQL, Redis, migrations and Hi5Central services…"
docker compose up -d --remove-orphans

active_services="postgres redis control-server"
profiles=$(awk -F= '$1=="COMPOSE_PROFILES"{print substr($0,index($0,"=")+1)}' "$ENV_FILE" | tail -1)
case ",$profiles," in *,itsm,*) active_services="$active_services itsm-web" ;; esac
case ",$profiles," in *,rmm,*) active_services="$active_services rmm-web" ;; esac
case ",$profiles," in *,admin,*) active_services="$active_services admin-web" ;; esac

echo "Waiting for services to become healthy…"
for service in $active_services; do
  container=$(docker compose ps -q "$service")
  [ -n "$container" ] || { echo "$service did not start." >&2; docker compose ps; exit 1; }
  attempts=0
  while :; do
    status=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container" 2>/dev/null || echo missing)
    [ "$status" = healthy ] && break
    case "$status" in
      exited|dead|unhealthy)
        echo "$service failed with status $status." >&2
        docker compose logs --tail=100 "$service" >&2 || true
        exit 1
        ;;
    esac
    attempts=$((attempts + 1))
    [ "$attempts" -lt 60 ] || { echo "Timed out waiting for $service (last status: $status)." >&2; exit 1; }
    sleep 2
  done
  echo "  ✓ $service"
done

gateway_container=$(docker compose ps -q gateway)
[ -n "$gateway_container" ] && [ "$(docker inspect -f '{{.State.Status}}' "$gateway_container")" = running ] || {
  echo "Gateway did not start." >&2; docker compose logs --tail=100 gateway >&2 || true; exit 1;
}
docker compose exec -T gateway caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1 || {
  echo "Gateway configuration validation failed." >&2; docker compose logs --tail=100 gateway >&2 || true; exit 1;
}
echo "  ✓ gateway"

case ",$profiles," in
  *,rmm,*)
    turn_container=$(docker compose ps -q turn)
    [ -n "$turn_container" ] && [ "$(docker inspect -f '{{.State.Status}}' "$turn_container")" = running ] || {
      echo "TURN service did not start." >&2; docker compose logs --tail=100 turn >&2 || true; exit 1;
    }
    echo "  ✓ turn"
    ;;
esac

tables=$(docker compose exec -T postgres sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "select count(*) from information_schema.tables where table_schema='\''public'\'';"')
echo "Database migrations complete ($tables public tables)."

echo
echo "Hi5Central is running."
echo "  ITSM:      $(awk -F= '$1=="APP_URL"{print substr($0,index($0,"=")+1)}' "$ENV_FILE")"
echo "  RMM:       $(awk -F= '$1=="RMM_URL"{print substr($0,index($0,"=")+1)}' "$ENV_FILE")"
echo "  Admin:     $(awk -F= '$1=="ADMIN_URL"{print substr($0,index($0,"=")+1)}' "$ENV_FILE")"
echo "  API:       $(awk -F= '$1=="API_URL"{print substr($0,index($0,"=")+1)}' "$ENV_FILE")"
echo "  Downloads: $(awk -F= '$1=="DOWNLOADS_URL"{print substr($0,index($0,"=")+1)}' "$ENV_FILE")"
echo
echo "Persistent data is stored in Docker volumes. Keep .env and secrets/ backed up securely."