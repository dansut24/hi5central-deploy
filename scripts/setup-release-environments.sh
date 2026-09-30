#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

LIVE_ENV=.env
[ -s "$LIVE_ENV" ] || { echo "Missing .env. Install Hi5Central first." >&2; exit 1; }

read_env() {
  file=$1
  key=$2
  awk -F= -v key="$key" '$1==key{print substr($0,index($0,"=")+1)}' "$file" | tail -1
}

set_env() {
  file=$1
  key=$2
  value=$3
  tmp=$(mktemp)
  awk -F= -v key="$key" '$1!=key{print}' "$file" > "$tmp"
  printf '%s=%s\n' "$key" "$value" >> "$tmp"
  cat "$tmp" > "$file"
  rm -f "$tmp"
}

random_hex() {
  dd if=/dev/urandom bs="$1" count=1 2>/dev/null | od -An -tx1 | tr -d ' \n'
}

mode=$(read_env "$LIVE_ENV" DEPLOYMENT_MODE)
[ "$mode" = self_hosted ] || { echo "This command is for self-hosted Hi5Central installations." >&2; exit 1; }

edition=$(read_env "$LIVE_ENV" SELF_HOST_EDITION)
case "$edition" in standard|msp) ;; *) echo "Unsupported self-host edition: $edition" >&2; exit 1 ;; esac
root_domain=$(read_env "$LIVE_ENV" ROOT_DOMAIN)
profiles=$(read_env "$LIVE_ENV" COMPOSE_PROFILES)
tenancy=$(read_env "$LIVE_ENV" TENANCY_MODE)
project=$(read_env "$LIVE_ENV" COMPOSE_PROJECT_NAME)
project=\${project:-hi5central}
app_url=$(read_env "$LIVE_ENV" APP_URL)
scheme=$(printf '%s' "$app_url" | sed -n 's#^\(https\?\)://.*#\1#p')
scheme=\${scheme:-https}
turn_external=$(read_env "$LIVE_ENV" TURN_EXTERNAL_IP)
licensing_url=$(read_env "$LIVE_ENV" LICENSING_SERVER_URL)
licensing_public=$(read_env "$LIVE_ENV" LICENSING_PUBLIC_KEY_PEM)
release_feed_url=$(read_env "$LIVE_ENV" RELEASE_FEED_URL)
release_feed_url=${release_feed_url:-https://api.hi5central.com/api/releases/v1/feed}
release_signing_public=$(read_env "$LIVE_ENV" RELEASE_SIGNING_PUBLIC_KEY_PEM)
release_signing_public=${release_signing_public:-$licensing_public}
operator_token=$(read_env "$LIVE_ENV" RELEASE_OPERATOR_TOKEN)
if ! printf '%s' "$operator_token" | grep -Eq '^[0-9a-fA-F]{64}$'; then
  operator_token=$(random_hex 32)
  set_env "$LIVE_ENV" RELEASE_OPERATOR_TOKEN "$operator_token"
fi

edge_network="\${project}-release-edge"
live_gateway="\${project}-live-gateway"
test_gateway="\${project}-test-gateway"
uat_gateway="\${project}-uat-gateway"

docker network inspect "$edge_network" >/dev/null 2>&1 || docker network create "$edge_network" >/dev/null

set_env "$LIVE_ENV" RUNTIME_ENVIRONMENT live
set_env "$LIVE_ENV" FEATURE_MODE controlled
set_env "$LIVE_ENV" RELEASE_GATEWAY_CONTAINER_NAME "$live_gateway"
set_env "$LIVE_ENV" RELEASE_EDGE_NETWORK "$edge_network"

test_itsm="test.$root_domain"
test_rmm="test-rmm.$root_domain"
test_admin="test-admin.$root_domain"
test_api="test-api.$root_domain"
test_downloads="test-downloads.$root_domain"
test_turn="test-turn.$root_domain"
uat_itsm="uat.$root_domain"
uat_rmm="uat-rmm.$root_domain"
uat_admin="uat-admin.$root_domain"
uat_api="uat-api.$root_domain"
uat_downloads="uat-downloads.$root_domain"
uat_turn="uat-turn.$root_domain"

caddy_address() {
  host=$1
  if [ "$scheme" = http ]; then printf 'http://%s' "$host"; else printf '%s' "$host"; fi
}

test_addresses="$(caddy_address "$test_itsm"),$(caddy_address "$test_rmm"),$(caddy_address "$test_api"),$(caddy_address "$test_downloads")"
uat_addresses="$(caddy_address "$uat_itsm"),$(caddy_address "$uat_rmm"),$(caddy_address "$uat_api"),$(caddy_address "$uat_downloads")"
case ",$profiles," in
  *,admin,*)
    test_addresses="$test_addresses,$(caddy_address "$test_admin")"
    uat_addresses="$uat_addresses,$(caddy_address "$uat_admin")"
    ;;
esac

set_env "$LIVE_ENV" RELEASE_TEST_ADDRESSES "$test_addresses"
set_env "$LIVE_ENV" RELEASE_TEST_GATEWAY_UPSTREAM "$test_gateway:80"
set_env "$LIVE_ENV" RELEASE_UAT_ADDRESSES "$uat_addresses"
set_env "$LIVE_ENV" RELEASE_UAT_GATEWAY_UPSTREAM "$uat_gateway:80"

control_image=$(read_env "$LIVE_ENV" CONTROL_SERVER_IMAGE)
itsm_image=$(read_env "$LIVE_ENV" ITSM_IMAGE)
rmm_image=$(read_env "$LIVE_ENV" RMM_IMAGE)
admin_image=$(read_env "$LIVE_ENV" ADMIN_IMAGE)

TEST_HTTP_PORT=${HI5_RELEASE_TEST_HTTP_PORT:-28080}
TEST_HTTPS_PORT=${HI5_RELEASE_TEST_HTTPS_PORT:-28443}
TEST_TURN_PORT=${HI5_RELEASE_TEST_TURN_PORT:-3480}
TEST_RELAY_MIN=${HI5_RELEASE_TEST_RELAY_MIN:-49360}
TEST_RELAY_MAX=${HI5_RELEASE_TEST_RELAY_MAX:-49400}
UAT_HTTP_PORT=${HI5_RELEASE_UAT_HTTP_PORT:-38080}
UAT_HTTPS_PORT=${HI5_RELEASE_UAT_HTTPS_PORT:-38443}
UAT_TURN_PORT=${HI5_RELEASE_UAT_TURN_PORT:-3481}
UAT_RELAY_MIN=${HI5_RELEASE_UAT_RELAY_MIN:-49460}
UAT_RELAY_MAX=${HI5_RELEASE_UAT_RELAY_MAX:-49500}

mkdir -p environments
umask 077

write_environment() {
  name=$1
  runtime=$2
  feature_mode=$3
  gateway_name=$4
  http_port=$5
  https_port=$6
  turn_port=$7
  relay_min=$8
  relay_max=$9
  itsm_host=\${10}
  rmm_host=\${11}
  admin_host=\${12}
  api_host=\${13}
  downloads_host=\${14}
  turn_host=\${15}
  file="environments/$name.env"

  pg=$(random_hex 24)
  redis=$(random_hex 24)
  mfa=$(random_hex 32)
  rmmkey=$(random_hex 32)
  connect=$(random_hex 32)
  turnsecret=$(random_hex 32)

  admin_url=
  admin_address=
  case ",$profiles," in
    *,admin,*)
      admin_url="$scheme://$admin_host"
      admin_address="http://$admin_host"
      ;;
  esac

  cat > "$file" <<EOF
COMPOSE_PROFILES=$profiles
COMPOSE_PROJECT_NAME=$project-$name
RELEASE_GATEWAY_CONTAINER_NAME=$gateway_name
RELEASE_EDGE_NETWORK=$edge_network
DEPLOYMENT_MODE=self_hosted
SELF_HOST_EDITION=$edition
RUNTIME_ENVIRONMENT=$runtime
FEATURE_MODE=$feature_mode
TENANCY_MODE=$tenancy
ROOT_DOMAIN=$root_domain
PRIMARY_TENANT_SLUG=$name
BACKGROUND_WORKERS_ENABLED=false

POSTGRES_DB=hi5central
POSTGRES_USER=hi5central
POSTGRES_PASSWORD=$pg
REDIS_PASSWORD=$redis

MFA_ENCRYPTION_KEY=$mfa
RMM_RECOVERY_KEY_ENCRYPTION_KEY=$rmmkey
CONNECT_CODE_HMAC_KEY=$connect
TURN_SHARED_SECRET=$turnsecret
TURN_REALM=$turn_host
TURN_EXTERNAL_IP=$turn_external

APP_URL=$scheme://$itsm_host
PORTAL_URL=$scheme://$itsm_host/portal
RMM_URL=$scheme://$rmm_host
ADMIN_URL=$admin_url
API_URL=$scheme://$api_host
DOWNLOADS_URL=$scheme://$downloads_host
TURN_URL=turn:$turn_host:$turn_port
TURN_HOST=$turn_host
MARKETING_URL=$scheme://$itsm_host
COOKIE_DOMAIN=

ITSM_ADDRESS=http://$itsm_host
RMM_ADDRESS=http://$rmm_host
ADMIN_ADDRESS=$admin_address
API_ADDRESS=http://$api_host
DOWNLOADS_ADDRESS=http://$downloads_host
HELP_ADDRESS=
ACME_EMAIL=

GATEWAY_HTTP_PORT=127.0.0.1:$http_port
GATEWAY_HTTPS_PORT=127.0.0.1:$https_port
TURN_LISTEN_PORT=$turn_port
TURN_RELAY_MIN_PORT=$relay_min
TURN_RELAY_MAX_PORT=$relay_max

CONTROL_SERVER_IMAGE=$control_image
ITSM_IMAGE=$itsm_image
RMM_IMAGE=$rmm_image
ADMIN_IMAGE=$admin_image

LICENSING_SERVER_URL=$licensing_url
LICENSING_PUBLIC_KEY_PEM=$licensing_public
RELEASE_OPERATOR_TOKEN=$operator_token
RELEASE_FEED_URL=$release_feed_url
RELEASE_SIGNING_PUBLIC_KEY_PEM=$release_signing_public
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
  chmod 600 "$file"
}

write_environment test test all_enabled "$test_gateway" 28080 28443 3480 49360 49400 "$test_itsm" "$test_rmm" "$test_admin" "$test_api" "$test_downloads" "$test_turn"
write_environment uat uat controlled "$uat_gateway" 38080 38443 3481 49460 49500 "$uat_itsm" "$uat_rmm" "$uat_admin" "$uat_api" "$uat_downloads" "$uat_turn"

./scripts/validate.sh --env-file environments/test.env
./scripts/validate.sh --env-file environments/uat.env
docker compose -f compose.yml -f compose.release-edge.yml --env-file "$LIVE_ENV" config -q

echo "Recreating the Live gateway with isolated Test/UAT routing..."
docker compose -f compose.yml -f compose.release-edge.yml --env-file "$LIVE_ENV" up -d --force-recreate config-init gateway

echo "Starting disposable Test with the currently installed release..."
docker compose -f compose.yml -f compose.release-edge.yml --env-file environments/test.env pull
docker compose -f compose.yml -f compose.release-edge.yml --env-file environments/test.env up -d --remove-orphans

HI5_ENABLE_LIVE_PROMOTION=1 sh scripts/install-release-operator.sh selfhost

echo
echo "Hi5Central release environments are enabled."
echo "  Test: $scheme://$test_itsm"
echo "  UAT:  $scheme://$uat_itsm (created on first approved promotion)"
echo "  Test data is disposable and external SMTP/Microsoft credentials are disabled by default."
echo
echo "DNS must resolve the test-* and uat-* hostnames (and test-turn/uat-turn for RMM) to this server."
