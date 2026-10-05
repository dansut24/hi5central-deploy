#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

DOMAIN=${HI5_ROOT_DOMAIN:-}
ACME_EMAIL_VALUE=${HI5_ACME_EMAIL:-}
EDITION=${HI5_EDITION:-standard}
LICENSE_KEY_VALUE=${HI5_LICENSE_KEY:-}
PRODUCTS=${HI5_PRODUCTS:-itsm,rmm}
SCHEME=${HI5_SCHEME:-}
RELEASE_CHANNEL=${HI5_RELEASE_CHANNEL:-stable}
PLATFORM_TAG=${HI5_PLATFORM_TAG:-}
FORCE=0
CONFIGURE_ONLY=0
SKIP_PULL=${HI5_SKIP_PULL:-0}
ENV_FILE="$ROOT_DIR/.env"

usage() {
  cat <<'EOF'
Usage: ./install.sh [options]

Guided Hi5Central self-host bootstrap.

Options:
  --domain DOMAIN         Base domain, e.g. hi5.example.com
  --email EMAIL           ACME contact email (HTTPS deployments)
  --edition EDITION       standard or msp
  --license-key KEY       MSP licence key (MSP edition only)
  --products LIST         itsm,rmm | itsm | rmm
  --channel CHANNEL       stable or early-access
  --platform-tag TAG      Override the platform image tag
  --http                  Use HTTP instead of automatic HTTPS
  --force                 Replace an existing .env with new configuration
  --configure-only        Generate/validate configuration but do not start
  --skip-pull             Do not pull images before startup
  -h, --help              Show this help

All settings can also be supplied with HI5_* environment variables for
non-interactive/bootstrap automation. Secrets default to secure automatic
generation. Set HI5_SECRET_MODE=manual to supply them yourself.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --domain) DOMAIN=${2:?--domain requires a value}; shift 2 ;;
    --email) ACME_EMAIL_VALUE=${2:?--email requires a value}; shift 2 ;;
    --edition) EDITION=${2:?--edition requires a value}; shift 2 ;;
    --license-key) LICENSE_KEY_VALUE=${2:?--license-key requires a value}; shift 2 ;;
    --products) PRODUCTS=${2:?--products requires a value}; shift 2 ;;
    --channel) RELEASE_CHANNEL=${2:?--channel requires a value}; shift 2 ;;
    --platform-tag) PLATFORM_TAG=${2:?--platform-tag requires a value}; shift 2 ;;
    --http) SCHEME=http; shift ;;
    --force) FORCE=1; shift ;;
    --configure-only) CONFIGURE_ONLY=1; shift ;;
    --skip-pull) SKIP_PULL=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

is_interactive() { [ -t 0 ]; }

random_hex() {
  dd if=/dev/urandom bs="$1" count=1 2>/dev/null | od -An -tx1 | tr -d ' \n'
}

clean_domain() {
  printf '%s' "$1" | sed -e 's#^https\?://##' -e 's#/$##' | tr '[:upper:]' '[:lower:]'
}

yes_no() {
  prompt=$1
  default=${2:-yes}
  if [ "$default" = yes ]; then suffix='[Y/n]'; else suffix='[y/N]'; fi
  while :; do
    printf "%s %s: " "$prompt" "$suffix" >&2
    IFS= read -r answer || answer=
    case "$answer" in
      y|Y|yes|YES|Yes) printf 'yes'; return ;;
      n|N|no|NO|No) printf 'no'; return ;;
      '')
        printf '%s' "$default"
        return
        ;;
      *) echo "Please answer y or n." >&2 ;;
    esac
  done
}

prompt_value() {
  label=$1
  default=${2:-}
  if [ -n "$default" ]; then
    printf "%s [%s]: " "$label" "$default" >&2
  else
    printf "%s: " "$label" >&2
  fi
  IFS= read -r value || value=
  printf '%s' "${value:-$default}"
}

prompt_secret() {
  label=$1
  printf "%s: " "$label" >&2
  if command -v stty >/dev/null 2>&1 && [ -t 0 ]; then stty -echo; fi
  IFS= read -r value || value=
  if command -v stty >/dev/null 2>&1 && [ -t 0 ]; then stty echo; fi
  echo >&2
  printf '%s' "$value"
}

validate_products() {
  old_ifs=$IFS
  IFS=','
  found=0
  for product in $1; do
    case "$product" in
      itsm|rmm) found=1 ;;
      *) echo "Unsupported product: $product" >&2; exit 1 ;;
    esac
  done
  IFS=$old_ifs
  [ "$found" -eq 1 ] || { echo "At least one product is required." >&2; exit 1; }
}

validate_edition() {
  case "$1" in
    standard|msp) ;;
    *) echo "Unsupported edition: $1 (expected standard or msp)" >&2; exit 1 ;;
  esac
}

validate_channel() {
  case "$1" in
    stable|early-access) ;;
    *) echo "Unsupported release channel: $1 (expected stable or early-access)" >&2; exit 1 ;;
  esac
}

validate_port() {
  value=$1
  name=$2
  case "$value" in
    ''|*[!0-9]*) echo "$name must be a numeric TCP/UDP port." >&2; exit 1 ;;
  esac
  [ "$value" -ge 1 ] && [ "$value" -le 65535 ] || {
    echo "$name must be between 1 and 65535." >&2
    exit 1
  }
}

echo
echo "Hi5Central Self-Hosted Setup"
echo "============================"
echo

command -v docker >/dev/null 2>&1 || {
  echo "Docker is required. Install Docker Engine/Desktop first." >&2
  exit 1
}
docker compose version >/dev/null 2>&1 || {
  echo "Docker Compose v2 is required." >&2
  exit 1
}
docker info >/dev/null 2>&1 || {
  echo "Docker is installed but the daemon is not reachable by this user." >&2
  exit 1
}

printf 'Docker ............... OK\n'
printf 'Docker Compose ....... OK\n'
mem_kb=$(awk '/MemTotal:/{print $2}' /proc/meminfo 2>/dev/null || echo 0)
disk_kb=$(df -Pk . 2>/dev/null | awk 'NR==2{print $4}')
[ "$mem_kb" -gt 0 ] && printf 'Memory ............... %s GiB\n' "$(awk -v kb="$mem_kb" 'BEGIN{printf "%.1f",kb/1024/1024}')"
[ -n "$disk_kb" ] && printf 'Disk free ............ %s GiB\n' "$(awk -v kb="$disk_kb" 'BEGIN{printf "%.1f",kb/1024/1024}')"
echo

if [ -f "$ENV_FILE" ] && [ "$FORCE" -ne 1 ]; then
  echo "Existing configuration found at $ENV_FILE."
  echo "Using it unchanged. Pass --force only when you intentionally want to regenerate configuration."
else
  if is_interactive && [ -z "${HI5_EDITION:-}" ]; then
    echo "Installation type:"
    echo "  1) Standard - Free"
    echo "  2) MSP - Licensed"
    while :; do
      selected=$(prompt_value "Select" "1")
      case "$selected" in
        1) EDITION=standard; break ;;
        2) EDITION=msp; break ;;
        *) echo "Choose 1 or 2." >&2 ;;
      esac
    done
    echo
  fi
  validate_edition "$EDITION"

  if is_interactive && [ -z "${HI5_PRODUCTS:-}" ]; then
    echo "Install:"
    echo "  1) ITSM + RMM"
    echo "  2) ITSM only"
    echo "  3) RMM only"
    while :; do
      selected=$(prompt_value "Select" "1")
      case "$selected" in
        1) PRODUCTS=itsm,rmm; break ;;
        2) PRODUCTS=itsm; break ;;
        3) PRODUCTS=rmm; break ;;
        *) echo "Choose 1, 2 or 3." >&2 ;;
      esac
    done
    echo
  fi
  validate_products "$PRODUCTS"

  if [ -z "$DOMAIN" ] && is_interactive; then
    DOMAIN=$(prompt_value "Primary domain (for example hi5.example.com)" "")
  fi
  [ -n "$DOMAIN" ] || {
    echo "A primary domain is required (--domain or HI5_ROOT_DOMAIN)." >&2
    exit 1
  }
  DOMAIN=$(clean_domain "$DOMAIN")
  printf '%s' "$DOMAIN" | grep -Eq '^[a-z0-9][a-z0-9.-]*[a-z0-9]$|^[a-z0-9]$' || {
    echo "Invalid domain: $DOMAIN" >&2
    exit 1
  }

  if [ -z "$SCHEME" ]; then
    if is_interactive; then
      use_https=$(yes_no "Use automatic HTTPS with Let's Encrypt?" yes)
      [ "$use_https" = yes ] && SCHEME=https || SCHEME=http
    else
      SCHEME=https
    fi
  fi
  case "$SCHEME" in https|http) ;; *) echo "HI5_SCHEME must be http or https." >&2; exit 1 ;; esac

  if is_interactive && [ -z "${HI5_RELEASE_CHANNEL:-}" ]; then
    echo
    echo "Update channel:"
    echo "  1) Stable (recommended)"
    echo "  2) Early Access"
    while :; do
      selected=$(prompt_value "Select" "1")
      case "$selected" in
        1) RELEASE_CHANNEL=stable; break ;;
        2) RELEASE_CHANNEL=early-access; break ;;
        *) echo "Choose 1 or 2." >&2 ;;
      esac
    done
  fi
  validate_channel "$RELEASE_CHANNEL"
  PLATFORM_TAG=${PLATFORM_TAG:-$RELEASE_CHANNEL}

  GATEWAY_HTTP_PORT_VALUE=${HI5_GATEWAY_HTTP_PORT:-80}
  GATEWAY_HTTPS_PORT_VALUE=${HI5_GATEWAY_HTTPS_PORT:-443}
  TURN_LISTEN_PORT_VALUE=${HI5_TURN_LISTEN_PORT:-3478}
  TURN_RELAY_MIN_PORT_VALUE=${HI5_TURN_RELAY_MIN_PORT:-49160}
  TURN_RELAY_MAX_PORT_VALUE=${HI5_TURN_RELAY_MAX_PORT:-49200}

  if is_interactive; then
    [ -n "${HI5_GATEWAY_HTTP_PORT:-}" ] || GATEWAY_HTTP_PORT_VALUE=$(prompt_value "HTTP port" "$GATEWAY_HTTP_PORT_VALUE")
    [ -n "${HI5_GATEWAY_HTTPS_PORT:-}" ] || GATEWAY_HTTPS_PORT_VALUE=$(prompt_value "HTTPS port" "$GATEWAY_HTTPS_PORT_VALUE")
    case ",$PRODUCTS," in
      *,rmm,*)
        [ -n "${HI5_TURN_LISTEN_PORT:-}" ] || TURN_LISTEN_PORT_VALUE=$(prompt_value "TURN port" "$TURN_LISTEN_PORT_VALUE")
        if [ -z "${HI5_TURN_RELAY_MIN_PORT:-}" ] && [ -z "${HI5_TURN_RELAY_MAX_PORT:-}" ]; then
          keep_turn_range=$(yes_no "Use default TURN relay range $TURN_RELAY_MIN_PORT_VALUE-$TURN_RELAY_MAX_PORT_VALUE?" yes)
          if [ "$keep_turn_range" = no ]; then
            TURN_RELAY_MIN_PORT_VALUE=$(prompt_value "TURN relay start port" "$TURN_RELAY_MIN_PORT_VALUE")
            TURN_RELAY_MAX_PORT_VALUE=$(prompt_value "TURN relay end port" "$TURN_RELAY_MAX_PORT_VALUE")
          fi
        fi
        ;;
    esac
  fi

  validate_port "$GATEWAY_HTTP_PORT_VALUE" "HTTP port"
  validate_port "$GATEWAY_HTTPS_PORT_VALUE" "HTTPS port"
  validate_port "$TURN_LISTEN_PORT_VALUE" "TURN port"
  validate_port "$TURN_RELAY_MIN_PORT_VALUE" "TURN relay start port"
  validate_port "$TURN_RELAY_MAX_PORT_VALUE" "TURN relay end port"
  [ "$TURN_RELAY_MIN_PORT_VALUE" -le "$TURN_RELAY_MAX_PORT_VALUE" ] || {
    echo "TURN relay start port must not be greater than the end port." >&2
    exit 1
  }

  ITSM_HOST=${HI5_ITSM_HOST:-itsm.$DOMAIN}
  RMM_HOST=${HI5_RMM_HOST:-rmm.$DOMAIN}
  ADMIN_HOST=${HI5_ADMIN_HOST:-admin.$DOMAIN}
  API_HOST=${HI5_API_HOST:-api.$DOMAIN}
  DOWNLOADS_HOST=${HI5_DOWNLOADS_HOST:-downloads.$DOMAIN}
  TURN_HOST_VALUE=${HI5_TURN_HOST:-turn.$DOMAIN}

  if is_interactive && [ -z "${HI5_ADVANCED_DOMAINS:-}" ]; then
    advanced_domains=$(yes_no "Use advanced/custom hostnames?" no)
    if [ "$advanced_domains" = yes ]; then
      ITSM_HOST=$(prompt_value "ITSM hostname" "$ITSM_HOST")
      RMM_HOST=$(prompt_value "RMM hostname" "$RMM_HOST")
      API_HOST=$(prompt_value "API hostname" "$API_HOST")
      DOWNLOADS_HOST=$(prompt_value "Downloads hostname" "$DOWNLOADS_HOST")
      TURN_HOST_VALUE=$(prompt_value "TURN hostname" "$TURN_HOST_VALUE")
      [ "$EDITION" = msp ] && ADMIN_HOST=$(prompt_value "Admin hostname" "$ADMIN_HOST")
    fi
  fi

  if [ "$SCHEME" = https ] && [ -z "$ACME_EMAIL_VALUE" ] && is_interactive; then
    ACME_EMAIL_VALUE=$(prompt_value "Let's Encrypt email" "admin@$DOMAIN")
  fi
  ACME_EMAIL_VALUE=${ACME_EMAIL_VALUE:-admin@$DOMAIN}

  COMPOSE_PROFILES_VALUE=$PRODUCTS
  TENANCY_MODE_VALUE=single
  if [ "$EDITION" = msp ]; then
    COMPOSE_PROFILES_VALUE="$COMPOSE_PROFILES_VALUE,admin"
    TENANCY_MODE_VALUE=multi
  fi

  PRIMARY_TENANT_SLUG_VALUE=${HI5_PRIMARY_TENANT_SLUG:-local}
  PRIMARY_TENANT_SLUG_VALUE=$(printf '%s' "$PRIMARY_TENANT_SLUG_VALUE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]//g')
  printf '%s' "$PRIMARY_TENANT_SLUG_VALUE" | grep -Eq '^[a-z0-9][a-z0-9-]{0,46}[a-z0-9]$|^[a-z0-9]$' || {
    echo "Invalid initial organisation slug: $PRIMARY_TENANT_SLUG_VALUE" >&2
    exit 1
  }

  if [ "$EDITION" = msp ] && [ "$CONFIGURE_ONLY" -ne 1 ]; then
    if [ -z "$LICENSE_KEY_VALUE" ] && is_interactive; then
      LICENSE_KEY_VALUE=$(prompt_secret "Hi5Central MSP licence key")
    fi
    [ -n "$LICENSE_KEY_VALUE" ] || {
      echo "The MSP edition requires a licence key (--license-key or HI5_LICENSE_KEY)." >&2
      exit 1
    }
  fi

  TURN_EXTERNAL_IP_VALUE=${HI5_TURN_EXTERNAL_IP:-}
  if is_interactive && [ -z "${HI5_TURN_EXTERNAL_IP:-}" ]; then
    case ",$PRODUCTS," in
      *,rmm,*)
        TURN_EXTERNAL_IP_VALUE=$(prompt_value "TURN public IP (optional; useful behind NAT)" "")
        ;;
    esac
  fi

  SMTP_HOST_VALUE=${HI5_SMTP_HOST:-}
  SMTP_PORT_VALUE=${HI5_SMTP_PORT:-587}
  SMTP_USER_VALUE=${HI5_SMTP_USER:-}
  SMTP_PASSWORD_VALUE=${HI5_SMTP_PASSWORD:-}
  SMTP_FROM_VALUE=${HI5_SMTP_FROM:-}
  if is_interactive && [ -z "${HI5_SMTP_HOST:-}" ]; then
    configure_smtp=$(yes_no "Configure SMTP now?" no)
    if [ "$configure_smtp" = yes ]; then
      SMTP_HOST_VALUE=$(prompt_value "SMTP host" "")
      if [ -n "$SMTP_HOST_VALUE" ]; then
        SMTP_PORT_VALUE=$(prompt_value "SMTP port" "$SMTP_PORT_VALUE")
        SMTP_USER_VALUE=$(prompt_value "SMTP username (optional)" "")
        SMTP_PASSWORD_VALUE=$(prompt_secret "SMTP password (optional)")
        SMTP_FROM_VALUE=$(prompt_value "SMTP From" "Hi5Central <no-reply@$DOMAIN>")
      fi
    fi
  fi

  SECRET_MODE=${HI5_SECRET_MODE:-}
  if [ -z "$SECRET_MODE" ]; then
    if is_interactive; then
      auto_secrets=$(yes_no "Generate secure installation secrets automatically?" yes)
      [ "$auto_secrets" = yes ] && SECRET_MODE=auto || SECRET_MODE=manual
    else
      SECRET_MODE=auto
    fi
  fi
  case "$SECRET_MODE" in auto|manual) ;; *) echo "HI5_SECRET_MODE must be auto or manual." >&2; exit 1 ;; esac

  POSTGRES_PASSWORD_VALUE=${HI5_POSTGRES_PASSWORD:-}
  REDIS_PASSWORD_VALUE=${HI5_REDIS_PASSWORD:-}
  MFA_KEY=${HI5_MFA_ENCRYPTION_KEY:-}
  RMM_KEY=${HI5_RMM_RECOVERY_KEY_ENCRYPTION_KEY:-}
  CONNECT_KEY=${HI5_CONNECT_CODE_HMAC_KEY:-}
  TENANT_INSTALLER_KEY=${HI5_TENANT_INSTALLER_HMAC_KEY:-}
  TURN_SHARED_SECRET_VALUE=${HI5_TURN_SHARED_SECRET:-}
  RELEASE_OPERATOR_TOKEN_VALUE=${HI5_RELEASE_OPERATOR_TOKEN:-}
  INITIAL_SETUP_TOKEN_VALUE=${HI5_INITIAL_SETUP_TOKEN:-}

  if [ "$SECRET_MODE" = auto ]; then
    POSTGRES_PASSWORD_VALUE=${POSTGRES_PASSWORD_VALUE:-$(random_hex 24)}
    REDIS_PASSWORD_VALUE=${REDIS_PASSWORD_VALUE:-$(random_hex 24)}
    MFA_KEY=${MFA_KEY:-$(random_hex 32)}
    RMM_KEY=${RMM_KEY:-$(random_hex 32)}
    CONNECT_KEY=${CONNECT_KEY:-$(random_hex 32)}
    TENANT_INSTALLER_KEY=${TENANT_INSTALLER_KEY:-$(random_hex 32)}
    TURN_SHARED_SECRET_VALUE=${TURN_SHARED_SECRET_VALUE:-$(random_hex 32)}
    RELEASE_OPERATOR_TOKEN_VALUE=${RELEASE_OPERATOR_TOKEN_VALUE:-$(random_hex 32)}
    INITIAL_SETUP_TOKEN_VALUE=${INITIAL_SETUP_TOKEN_VALUE:-$(random_hex 32)}
  else
    if ! is_interactive; then
      [ -n "$POSTGRES_PASSWORD_VALUE" ] &&
      [ -n "$REDIS_PASSWORD_VALUE" ] &&
      [ -n "$MFA_KEY" ] &&
      [ -n "$RMM_KEY" ] &&
      [ -n "$CONNECT_KEY" ] &&
      [ -n "$TENANT_INSTALLER_KEY" ] &&
      [ -n "$TURN_SHARED_SECRET_VALUE" ] || {
        echo "Manual secret mode is non-interactive; provide all HI5_* secret variables." >&2
        exit 1
      }
    else
      [ -n "$POSTGRES_PASSWORD_VALUE" ] || POSTGRES_PASSWORD_VALUE=$(prompt_secret "PostgreSQL password (24+ characters)")
      [ -n "$REDIS_PASSWORD_VALUE" ] || REDIS_PASSWORD_VALUE=$(prompt_secret "Redis password (24+ characters)")
      [ -n "$MFA_KEY" ] || MFA_KEY=$(prompt_secret "MFA encryption key (64 hex characters)")
      [ -n "$RMM_KEY" ] || RMM_KEY=$(prompt_secret "RMM recovery encryption key (64 hex characters)")
      [ -n "$CONNECT_KEY" ] || CONNECT_KEY=$(prompt_secret "Connect HMAC key (64 hex characters)")
      [ -n "$TENANT_INSTALLER_KEY" ] || TENANT_INSTALLER_KEY=$(prompt_secret "Tenant installer HMAC key (64 hex characters)")
      [ -n "$TURN_SHARED_SECRET_VALUE" ] || TURN_SHARED_SECRET_VALUE=$(prompt_secret "TURN shared secret (64 hex characters)")
      RELEASE_OPERATOR_TOKEN_VALUE=${RELEASE_OPERATOR_TOKEN_VALUE:-$(random_hex 32)}
    fi
    INITIAL_SETUP_TOKEN_VALUE=${INITIAL_SETUP_TOKEN_VALUE:-$(random_hex 32)}
  fi

  URL_PORT=
  if [ "$SCHEME" = https ] && [ "$GATEWAY_HTTPS_PORT_VALUE" -ne 443 ]; then
    URL_PORT=":$GATEWAY_HTTPS_PORT_VALUE"
  elif [ "$SCHEME" = http ] && [ "$GATEWAY_HTTP_PORT_VALUE" -ne 80 ]; then
    URL_PORT=":$GATEWAY_HTTP_PORT_VALUE"
  fi

  APP_URL_VALUE="$SCHEME://$ITSM_HOST$URL_PORT"
  RMM_URL_VALUE="$SCHEME://$RMM_HOST$URL_PORT"
  ADMIN_URL_VALUE=
  [ "$EDITION" = msp ] && ADMIN_URL_VALUE="$SCHEME://$ADMIN_HOST$URL_PORT"
  API_URL_VALUE="$SCHEME://$API_HOST$URL_PORT"
  DOWNLOADS_URL_VALUE="$SCHEME://$DOWNLOADS_HOST$URL_PORT"

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

  echo
  echo "Ready to configure"
  echo "------------------"
  echo "Edition:          $EDITION"
  echo "Products:         $PRODUCTS"
  echo "Domain:           $DOMAIN"
  echo "Release channel:  $RELEASE_CHANNEL"
  echo "Platform tag:     $PLATFORM_TAG"
  echo "HTTPS:            $([ "$SCHEME" = https ] && echo enabled || echo disabled)"
  echo "HTTP port:        $GATEWAY_HTTP_PORT_VALUE"
  echo "HTTPS port:       $GATEWAY_HTTPS_PORT_VALUE"
  case ",$PRODUCTS," in *,rmm,*) echo "TURN port:        $TURN_LISTEN_PORT_VALUE" ;; esac
  echo "Secrets:          $SECRET_MODE"
  echo

  if is_interactive; then
    if [ "$CONFIGURE_ONLY" -eq 1 ]; then
      proceed=$(yes_no "Write this configuration?" yes)
    else
      proceed=$(yes_no "Start installation?" yes)
    fi
    [ "$proceed" = yes ] || { echo "Installation cancelled."; exit 0; }
  fi

  umask 077
  cat > "$ENV_FILE" <<EOF
COMPOSE_PROFILES=$COMPOSE_PROFILES_VALUE
COMPOSE_PROJECT_NAME=${HI5_PROJECT_NAME:-hi5central}
DEPLOYMENT_MODE=self_hosted
SELF_HOST_EDITION=$EDITION
RUNTIME_ENVIRONMENT=production
FEATURE_MODE=controlled
TENANCY_MODE=$TENANCY_MODE_VALUE
ROOT_DOMAIN=$DOMAIN
PRIMARY_TENANT_SLUG=$PRIMARY_TENANT_SLUG_VALUE
BACKGROUND_WORKERS_ENABLED=${HI5_BACKGROUND_WORKERS_ENABLED:-true}
RELEASE_CHANNEL=$RELEASE_CHANNEL
PLATFORM_TAG=$PLATFORM_TAG

POSTGRES_DB=${HI5_POSTGRES_DB:-hi5central}
POSTGRES_USER=${HI5_POSTGRES_USER:-hi5central}
POSTGRES_PASSWORD=$POSTGRES_PASSWORD_VALUE
REDIS_PASSWORD=$REDIS_PASSWORD_VALUE

MFA_ENCRYPTION_KEY=$MFA_KEY
RMM_RECOVERY_KEY_ENCRYPTION_KEY=$RMM_KEY
CONNECT_CODE_HMAC_KEY=$CONNECT_KEY
TENANT_INSTALLER_HMAC_KEY=$TENANT_INSTALLER_KEY
TURN_SHARED_SECRET=$TURN_SHARED_SECRET_VALUE
INITIAL_SETUP_TOKEN=$INITIAL_SETUP_TOKEN_VALUE
TURN_REALM=${HI5_TURN_REALM:-$DOMAIN}
TURN_EXTERNAL_IP=$TURN_EXTERNAL_IP_VALUE

APP_URL=$APP_URL_VALUE
PORTAL_URL=$APP_URL_VALUE/portal
RMM_URL=$RMM_URL_VALUE
ADMIN_URL=$ADMIN_URL_VALUE
API_URL=$API_URL_VALUE
DOWNLOADS_URL=$DOWNLOADS_URL_VALUE
TURN_URL=turn:$TURN_HOST_VALUE:$TURN_LISTEN_PORT_VALUE
TURN_HOST=$TURN_HOST_VALUE
MARKETING_URL=$APP_URL_VALUE
COOKIE_DOMAIN=

ITSM_ADDRESS=$ITSM_ADDRESS_VALUE
RMM_ADDRESS=$RMM_ADDRESS_VALUE
ADMIN_ADDRESS=$ADMIN_ADDRESS_VALUE
API_ADDRESS=$API_ADDRESS_VALUE
DOWNLOADS_ADDRESS=$DOWNLOADS_ADDRESS_VALUE
ACME_EMAIL=$ACME_EMAIL_VALUE

GATEWAY_HTTP_PORT=$GATEWAY_HTTP_PORT_VALUE
GATEWAY_HTTPS_PORT=$GATEWAY_HTTPS_PORT_VALUE
TURN_LISTEN_PORT=$TURN_LISTEN_PORT_VALUE
TURN_RELAY_MIN_PORT=$TURN_RELAY_MIN_PORT_VALUE
TURN_RELAY_MAX_PORT=$TURN_RELAY_MAX_PORT_VALUE

CONTROL_SERVER_IMAGE=${HI5_CONTROL_SERVER_IMAGE:-ghcr.io/dansut24/hi5central-platform-api:$PLATFORM_TAG}
ITSM_IMAGE=${HI5_ITSM_IMAGE:-ghcr.io/dansut24/hi5central-platform-itsm:$PLATFORM_TAG}
RMM_IMAGE=${HI5_RMM_IMAGE:-ghcr.io/dansut24/hi5central-platform-rmm:$PLATFORM_TAG}
ADMIN_IMAGE=${HI5_ADMIN_IMAGE:-ghcr.io/dansut24/hi5central-platform-admin:$PLATFORM_TAG}
AGENT_DEPLOYMENT_ASSETS_IMAGE=${HI5_AGENT_DEPLOYMENT_ASSETS_IMAGE:-ghcr.io/dansut24/hi5central-agent-deployment-assets:$PLATFORM_TAG}
TENANT_INSTALLER_API_BASE=$API_URL_VALUE

LICENSING_SERVER_URL=${HI5_LICENSING_SERVER_URL:-https://licensing.hi5central.com}
LICENSING_PUBLIC_KEY_PEM=${HI5_LICENSING_PUBLIC_KEY_PEM:-}
RELEASE_OPERATOR_TOKEN=$RELEASE_OPERATOR_TOKEN_VALUE
RELEASE_FEED_URL=${HI5_RELEASE_FEED_URL:-https://api.hi5central.com/api/releases/v1/feed}
RELEASE_SIGNING_PUBLIC_KEY_PEM=${HI5_RELEASE_SIGNING_PUBLIC_KEY_PEM:-${HI5_LICENSING_PUBLIC_KEY_PEM:-}}
RELEASE_SIGNING_PRIVATE_KEY_PEM=
RELEASE_FEED_SYNC_INTERVAL_MS=${HI5_RELEASE_FEED_SYNC_INTERVAL_MS:-21600000}
RELEASE_FEED_INITIAL_SYNC_DELAY_MS=${HI5_RELEASE_FEED_INITIAL_SYNC_DELAY_MS:-45000}

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
  echo "Secure deployment configuration written to $ENV_FILE."
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
  echo "Pulling Hi5Central container images..."
  docker compose pull
fi

echo "Starting PostgreSQL, Redis, migrations and Hi5Central services..."
docker compose up -d --remove-orphans

active_services="postgres redis control-server"
profiles=$(awk -F= '$1=="COMPOSE_PROFILES"{print substr($0,index($0,"=")+1)}' "$ENV_FILE" | tail -1)
case ",$profiles," in *,itsm,*) active_services="$active_services itsm-web" ;; esac
case ",$profiles," in *,rmm,*) active_services="$active_services rmm-web" ;; esac
case ",$profiles," in *,admin,*) active_services="$active_services admin-web" ;; esac

echo "Waiting for services to become healthy..."
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
    echo "Activating Hi5Central MSP licence..."
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
  fi
fi

smtp_host=$(awk -F= '$1=="SMTP_HOST"{print substr($0,index($0,"=")+1)}' "$ENV_FILE" | tail -1)
if [ -n "$smtp_host" ]; then
  echo "Checking SMTP connectivity..."
  docker compose exec -T control-server node -e "fetch('http://127.0.0.1:3001/api/v1/system/smtp-health').then(async r=>{if(!r.ok){console.error(await r.text());process.exit(1)}}).catch(e=>{console.error(e);process.exit(1)})" || {
    echo "SMTP is configured but the connectivity check failed. Correct SMTP before relying on email." >&2
    exit 1
  }
  echo "  ✓ smtp"
else
  echo "INFO SMTP is not configured. You can add it later from deployment configuration."
fi

echo
echo "Hi5Central is ready."
echo "  Edition:   $installed_edition"
echo "  Channel:   $(awk -F= '$1=="RELEASE_CHANNEL"{print substr($0,index($0,"=")+1)}' "$ENV_FILE" | tail -1)"
case ",$profiles," in *,itsm,*) echo "  ITSM:      $(awk -F= '$1=="APP_URL"{print substr($0,index($0,"=")+1)}' "$ENV_FILE")" ;; esac
case ",$profiles," in *,rmm,*) echo "  RMM:       $(awk -F= '$1=="RMM_URL"{print substr($0,index($0,"=")+1)}' "$ENV_FILE")" ;; esac
admin_url=$(awk -F= '$1=="ADMIN_URL"{print substr($0,index($0,"=")+1)}' "$ENV_FILE")
[ -n "$admin_url" ] && echo "  Admin:     $admin_url"
echo "  API:       $(awk -F= '$1=="API_URL"{print substr($0,index($0,"=")+1)}' "$ENV_FILE")"
echo "  Downloads: $(awk -F= '$1=="DOWNLOADS_URL"{print substr($0,index($0,"=")+1)}' "$ENV_FILE")"
setup_token=$(awk -F= '$1=="INITIAL_SETUP_TOKEN"{print substr($0,index($0,"=")+1)}' "$ENV_FILE")
app_url=$(awk -F= '$1=="APP_URL"{print substr($0,index($0,"=")+1)}' "$ENV_FILE")
if [ -n "$setup_token" ]; then
  echo
  echo "First-time setup:"
  echo "  $app_url/signup#setup=$setup_token"
  echo
  echo "Keep this setup URL private. It is accepted only while the installation has no tenant."
fi
echo
echo "Persistent data is stored in Docker volumes."
echo "Keep .env and backups secure. Create a backup after first-time application setup."
