#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

DOMAIN=${HI5_ROOT_DOMAIN:-}
ACME_EMAIL_VALUE=${HI5_ACME_EMAIL:-}
EDITION=${HI5_EDITION:-standard}
LICENSE_KEY_VALUE=${HI5_LICENSE_KEY:-}
PRODUCTS=${HI5_PRODUCTS:-itsm,rmm}
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
  --edition EDITION       standard or msp (default: standard)
  --license-key KEY        MSP licence key (MSP edition only)
  --products LIST         Comma-separated: itsm,rmm (default: both)
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
    --edition) EDITION=${2:?--edition requires a value}; shift 2 ;;
    --license-key) LICENSE_KEY_VALUE=${2:?--license-key requires a value}; shift 2 ;;
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
      itsm|rmm) ;;
      *) echo "Unsupported product in --products: $product" >&2; exit 1 ;;
    esac
  done
  IFS=$old_ifs
}

validate_edition() {
  case "$1" in
    standard|msp) ;;
    *) echo "Unsupported edition: $1 (expected standard or msp)" >&2; exit 1 ;;
  esac
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

  if [ -t 0 ] && [ -z "${HI5_EDITION:-}" ]; then
    printf "Edition [standard/msp] [$EDITION]: "
    IFS= read -r selected_edition
    EDITION=${selected_edition:-$EDITION}
  fi
  validate_edition "$EDITION"

  if [ "$EDITION" = msp ] && [ "$CONFIGURE_ONLY" -ne 1 ]; then
    if [ -z "$LICENSE_KEY_VALUE" ] && [ -t 0 ]; then
      printf "Hi5Central MSP licence key: "
      if command -v stty >/dev/null 2>&1; then stty -echo; fi
      IFS= read -r LICENSE_KEY_VALUE
      if command -v stty >/dev/null 2>&1; then stty echo; fi
      echo
    fi
    [ -n "$LICENSE_KEY_VALUE" ] || {
      echo "The MSP edition requires a licence key (--license-key or HI5_LICENSE_KEY)." >&2
      exit 1
    }
  fi

  if [ -t 0 ] && [ -z "${HI5_PRODUCTS:-}" ]; then
    printf "Products to install [itsm,rmm]: "
    IFS= read -r selected_products
    PRODUCTS=${selected_products:-itsm,rmm}
  fi
  validate_products "$PRODUCTS"
  COMPOSE_PROFILES_VALUE=$PRODUCTS
  [ "$EDITION" = msp ] && COMPOSE_PROFILES_VALUE="$COMPOSE_PROFILES_VALUE,admin"
  case "$SCHEME" in https|http) ;; *) echo "HI5_SCHEME must be http or https." >&2; exit 1 ;; esac

  PRIMARY_TENANT_SLUG_VALUE=${HI5_PRIMARY_TENANT_SLUG:-local}
  if [ -t 0 ] && [ -z "${HI5_PRIMARY_TENANT_SLUG:-}" ]; then
    printf "Initial organisation slug [$PRIMARY_TENANT_SLUG_VALUE]: "
    IFS= read -r selected_tenant_slug
    PRIMARY_TENANT_SLUG_VALUE=${selected_tenant_slug:-$PRIMARY_TENANT_SLUG_VALUE}
  fi
  PRIMARY_TENANT_SLUG_VALUE=$(printf '%s' "$PRIMARY_TENANT_SLUG_VALUE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]//g')
  printf '%s' "$PRIMARY_TENANT_SLUG_VALUE" | grep -Eq '^[a-z0-9][a-z0-9-]{0,46}[a-z0-9]$|^[a-z0-9]$' || {
    echo "Invalid initial organisation slug: $PRIMARY_TENANT_SLUG_VALUE" >&2; exit 1;
  }

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
  ADMIN_URL_VALUE=
  [ "$EDITION" = msp ] && ADMIN_URL_VALUE="$SCHEME://$ADMIN_HOST"
  API_URL_VALUE="$SCHEME://$API_HOST"
  DOWNLOADS_URL_VALUE="$SCHEME://$DOWNLOADS_HOST"

  if [ "$SCHEME" = http ]; then
    ITSM_ADDRESS_VALUE="http://$ITSM_HOST"
    RMM_ADDRESS_VALUE="http://$RMM_HOST"
    ADMIN_ADDRESS_VALUE=
    [ "$EDITION" = msp ] && ADMIN_ADDRESS_VALUE="http://$ADMIN_HOST"
    API_ADDRESS_VALUE="http://$API_HOST"
    DOWNLOADS_ADDRESS_VALUE="http://$DOWNLOADS_HOST"
  else
    ITSM_ADDRESS_VALUE="$ITSM_HOST"
    RMM_ADDRESS_VALUE="$RMM_HOST"
    ADMIN_ADDRESS_VALUE=
    [ "$EDITION" = msp ] && ADMIN_ADDRESS_VALUE="$ADMIN_HOST"
    API_ADDRESS_VALUE="$API_HOST"
    DOWNLOADS_ADDRESS_VALUE="$DOWNLOADS_HOST"
  fi

  TURN_EXTERNAL_IP_VALUE=${HI5_TURN_EXTERNAL_IP:-}
  if [ -t 0 ] && [ -z "${HI5_TURN_EXTERNAL_IP:-}" ]; then
    case ",$PRODUCTS," in
      *,rmm,*)
        printf "TURN public IP (optional; recommended behind NAT): "
        IFS= read -r TURN_EXTERNAL_IP_VALUE
        ;;
    esac
  fi

  SMTP_HOST_VALUE=${HI5_SMTP_HOST:-}
  SMTP_PORT_VALUE=${HI5_SMTP_PORT:-587}
  SMTP_USER_VALUE=${HI5_SMTP_USER:-}
  SMTP_PASSWORD_VALUE=${HI5_SMTP_PASSWORD:-}
  SMTP_FROM_VALUE=${HI5_SMTP_FROM:-}
  if [ -t 0 ] && [ -z "${HI5_SMTP_HOST:-}" ]; then
    printf "Configure SMTP now for signup/notifications? [Y/n]: "
    IFS= read -r configure_smtp
    case "${configure_smtp:-Y}" in
      n|N|no|NO) ;;
      *)
        printf "SMTP host: "; IFS= read -r SMTP_HOST_VALUE
        if [ -n "$SMTP_HOST_VALUE" ]; then
          printf "SMTP port [$SMTP_PORT_VALUE]: "; IFS= read -r selected_smtp_port
          SMTP_PORT_VALUE=${selected_smtp_port:-$SMTP_PORT_VALUE}
          printf "SMTP username (optional): "; IFS= read -r SMTP_USER_VALUE
          printf "SMTP password (optional): "
          if command -v stty >/dev/null 2>&1; then stty -echo; fi
          IFS= read -r SMTP_PASSWORD_VALUE
          if command -v stty >/dev/null 2>&1; then stty echo; fi
          echo
          printf "SMTP From [Hi5Central <no-reply@$DOMAIN>]: "; IFS= read -r SMTP_FROM_VALUE
          SMTP_FROM_VALUE=${SMTP_FROM_VALUE:-Hi5Central <no-reply@$DOMAIN>}
        fi
        ;;
    esac
  fi

  POSTGRES_PASSWORD_VALUE=$(random_hex 24)
  REDIS_PASSWORD_VALUE=$(random_hex 24)
  MFA_KEY=$(random_hex 32)
  RMM_KEY=$(random_hex 32)
  CONNECT_KEY=$(random_hex 32)
  TURN_SHARED_SECRET_VALUE=$(random_hex 32)

  umask 077
  cat > "$ENV_FILE" <<EOF
COMPOSE_PROFILES=$COMPOSE_PROFILES_VALUE
COMPOSE_PROJECT_NAME=${HI5_PROJECT_NAME:-hi5central}
DEPLOYMENT_MODE=self_hosted
SELF_HOST_EDITION=$EDITION
TENANCY_MODE=single
ROOT_DOMAIN=$DOMAIN
PRIMARY_TENANT_SLUG=$PRIMARY_TENANT_SLUG_VALUE
BACKGROUND_WORKERS_ENABLED=${HI5_BACKGROUND_WORKERS_ENABLED:-true}

POSTGRES_DB=${HI5_POSTGRES_DB:-hi5central}
POSTGRES_USER=${HI5_POSTGRES_USER:-hi5central}
POSTGRES_PASSWORD=$POSTGRES_PASSWORD_VALUE
REDIS_PASSWORD=$REDIS_PASSWORD_VALUE

MFA_ENCRYPTION_KEY=$MFA_KEY
RMM_RECOVERY_KEY_ENCRYPTION_KEY=$RMM_KEY
CONNECT_CODE_HMAC_KEY=$CONNECT_KEY
TURN_SHARED_SECRET=$TURN_SHARED_SECRET_VALUE
TURN_REALM=${HI5_TURN_REALM:-$DOMAIN}
TURN_EXTERNAL_IP=$TURN_EXTERNAL_IP_VALUE

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

CONTROL_SERVER_IMAGE=${HI5_CONTROL_SERVER_IMAGE:-ghcr.io/dansut24/hi5central-control-server:latest}
ITSM_IMAGE=${HI5_ITSM_IMAGE:-ghcr.io/dansut24/hi5central-itsm:latest}
RMM_IMAGE=${HI5_RMM_IMAGE:-ghcr.io/dansut24/hi5central-rmm:latest}
ADMIN_IMAGE=${HI5_ADMIN_IMAGE:-ghcr.io/dansut24/hi5central-admin:latest}

LICENSING_SERVER_URL=${HI5_LICENSING_SERVER_URL:-https://licensing.hi5central.com}
LICENSING_PUBLIC_KEY_PEM=${HI5_LICENSING_PUBLIC_KEY_PEM:-}

SMTP_HOST=$SMTP_HOST_VALUE
SMTP_PORT=$SMTP_PORT_VALUE
SMTP_USER=$SMTP_USER_VALUE
SMTP_PASSWORD=$SMTP_PASSWORD_VALUE
SMTP_FROM=$SMTP_FROM_VALUE
MICROSOFT_CLIENT_ID=${HI5_MICROSOFT_CLIENT_ID:-}
MICROSOFT_CLIENT_SECRET=${HI5_MICROSOFT_CLIENT_SECRET:-}
MICROSOFT_REDIRECT_URI=${HI5_MICROSOFT_REDIRECT_URI:-}
EOF
  chmod 600 "$ENV_FILE"
  echo "Generated secure deployment configuration in $ENV_FILE."
fi

./scripts/validate.sh
if [ "${HI5_SKIP_PREFLIGHT:-0}" != 1 ]; then
  ./scripts/preflight.sh
fi

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

installed_edition=$(awk -F= '$1=="SELF_HOST_EDITION"{print substr($0,index($0,"=")+1)}' "$ENV_FILE" | tail -1)
if [ "$installed_edition" = msp ]; then
  if [ -n "$LICENSE_KEY_VALUE" ]; then
    echo "Activating Hi5Central MSP licence…"
    docker compose exec -T -e HI5_ACTIVATION_KEY="$LICENSE_KEY_VALUE" control-server node -e '
      fetch("http://127.0.0.1:3001/api/v1/system/license/activate", {
        method: "POST",
        headers: {"content-type":"application/json"},
        body: JSON.stringify({licenseKey: process.env.HI5_ACTIVATION_KEY})
      }).then(async r => {
        const body = await r.json().catch(() => ({}));
        if (!r.ok || !body.activated) {
          console.error(body.error || ("Licence activation failed with HTTP " + r.status));
          process.exit(1);
        }
        console.log("  ✓ MSP licence active");
      }).catch(error => { console.error(error.message); process.exit(1); });
    '
  else
    docker compose exec -T control-server node -e '
      fetch("http://127.0.0.1:3001/api/v1/system/license").then(async r => {
        const body = await r.json();
        if (!r.ok || !["active","grace"].includes(body.status)) {
          console.error("MSP licence is not active. Re-run install.sh with --license-key or HI5_LICENSE_KEY.");
          process.exit(1);
        }
        console.log("  ✓ Existing MSP licence " + body.status);
      }).catch(error => { console.error(error.message); process.exit(1); });
    '
  fi
fi

smtp_host=$(awk -F= '$1=="SMTP_HOST"{print substr($0,index($0,"=")+1)}' "$ENV_FILE" | tail -1)
if [ -n "$smtp_host" ]; then
  echo "Checking SMTP connectivity…"
  docker compose exec -T control-server node -e "fetch('http://127.0.0.1:3001/api/v1/system/smtp-health').then(async r=>{if(!r.ok){console.error(await r.text());process.exit(1)}}).catch(e=>{console.error(e);process.exit(1)})" || {
    echo "SMTP is configured but the connectivity check failed. Correct SMTP before first signup." >&2
    exit 1
  }
  echo "  ✓ smtp"
else
  echo "WARN SMTP is not configured. Signup verification and email notifications will not work until SMTP is added."
fi

echo
echo "Hi5Central is running."
echo "  Edition:   $(awk -F= '$1=="SELF_HOST_EDITION"{print substr($0,index($0,"=")+1)}' "$ENV_FILE")"
echo "  ITSM:      $(awk -F= '$1=="APP_URL"{print substr($0,index($0,"=")+1)}' "$ENV_FILE")"
echo "  RMM:       $(awk -F= '$1=="RMM_URL"{print substr($0,index($0,"=")+1)}' "$ENV_FILE")"
admin_url=$(awk -F= '$1=="ADMIN_URL"{print substr($0,index($0,"=")+1)}' "$ENV_FILE")
[ -n "$admin_url" ] && echo "  Admin:     $admin_url"
echo "  API:       $(awk -F= '$1=="API_URL"{print substr($0,index($0,"=")+1)}' "$ENV_FILE")"
echo "  Downloads: $(awk -F= '$1=="DOWNLOADS_URL"{print substr($0,index($0,"=")+1)}' "$ENV_FILE")"
echo "  First setup: $(awk -F= '$1=="APP_URL"{print substr($0,index($0,"=")+1)}' "$ENV_FILE")/signup"
echo
echo "Persistent data is stored in Docker volumes. Keep .env and your Docker volumes backed up securely."
echo "Create a backup with ./scripts/backup.sh after completing first-time setup."