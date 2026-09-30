#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

PROJECT=${HI5_SMOKE_PROJECT:-hi5central-selfhost-smoke}
EDITION=${HI5_SMOKE_EDITION:-standard}
CONTROL_IMAGE=${HI5_SMOKE_CONTROL_IMAGE:-ghcr.io/dansut24/hi5central-control-server:dev}
ITSM_IMAGE=${HI5_SMOKE_ITSM_IMAGE:-ghcr.io/dansut24/hi5central-itsm:dev}
RMM_IMAGE=${HI5_SMOKE_RMM_IMAGE:-ghcr.io/dansut24/hi5central-rmm:dev}
ADMIN_IMAGE=${HI5_SMOKE_ADMIN_IMAGE:-ghcr.io/dansut24/hi5central-admin:dev}
LICENSE_KEY=${HI5_SMOKE_LICENSE_KEY:-}
LICENSE_SERVER=${HI5_SMOKE_LICENSE_SERVER:-https://dev-api.hi5central.com}
LICENSE_PUBLIC_KEY=${HI5_SMOKE_LICENSE_PUBLIC_KEY:-}

case "$EDITION" in
  standard|msp) ;;
  *) echo "HI5_SMOKE_EDITION must be standard or msp." >&2; exit 2 ;;
esac
if [ "$EDITION" = msp ] && [ -z "$LICENSE_KEY" ]; then
  echo "MSP smoke requires HI5_SMOKE_LICENSE_KEY." >&2
  exit 2
fi

ENV_FILE=$(mktemp)
random_hex() { dd if=/dev/urandom bs="$1" count=1 2>/dev/null | od -An -tx1 | tr -d ' \n'; }
PG_PASSWORD=$(random_hex 18)
REDIS_PASSWORD=$(random_hex 18)
MFA_KEY=$(random_hex 32)
RMM_KEY=$(random_hex 32)
CONNECT_KEY=$(random_hex 32)
TURN_KEY=$(random_hex 32)
PROFILES=itsm,rmm
ADMIN_URL=
ADMIN_ADDRESS=
[ "$EDITION" = msp ] && PROFILES="$PROFILES,admin"
[ "$EDITION" = msp ] && ADMIN_URL=http://admin.split.localhost
[ "$EDITION" = msp ] && ADMIN_ADDRESS=http://admin.split.localhost

compose() {
  docker compose -p "$PROJECT" --env-file "$ENV_FILE" "$@"
}
cleanup() {
  compose down -v --remove-orphans >/dev/null 2>&1 || true
  rm -f "$ENV_FILE"
}
trap cleanup EXIT INT TERM

cat >"$ENV_FILE" <<EOF
COMPOSE_PROFILES=$PROFILES
COMPOSE_PROJECT_NAME=$PROJECT
DEPLOYMENT_MODE=self_hosted
SELF_HOST_EDITION=$EDITION
RUNTIME_ENVIRONMENT=live
FEATURE_MODE=controlled
TENANCY_MODE=single
ROOT_DOMAIN=split.localhost
PRIMARY_TENANT_SLUG=local
BACKGROUND_WORKERS_ENABLED=false

POSTGRES_DB=hi5central
POSTGRES_USER=hi5central
POSTGRES_PASSWORD=$PG_PASSWORD
REDIS_PASSWORD=$REDIS_PASSWORD

MFA_ENCRYPTION_KEY=$MFA_KEY
RMM_RECOVERY_KEY_ENCRYPTION_KEY=$RMM_KEY
CONNECT_CODE_HMAC_KEY=$CONNECT_KEY
TURN_SHARED_SECRET=$TURN_KEY
TURN_REALM=split.localhost
TURN_EXTERNAL_IP=

APP_URL=http://itsm.split.localhost
PORTAL_URL=http://itsm.split.localhost/portal
RMM_URL=http://rmm.split.localhost
ADMIN_URL=$ADMIN_URL
API_URL=http://api.split.localhost
DOWNLOADS_URL=http://downloads.split.localhost
TURN_URL=turn:turn.split.localhost:3489
TURN_HOST=turn.split.localhost
MARKETING_URL=http://itsm.split.localhost
COOKIE_DOMAIN=

ITSM_ADDRESS=http://itsm.split.localhost
RMM_ADDRESS=http://rmm.split.localhost
ADMIN_ADDRESS=$ADMIN_ADDRESS
API_ADDRESS=http://api.split.localhost
DOWNLOADS_ADDRESS=http://downloads.split.localhost
ACME_EMAIL=

GATEWAY_HTTP_PORT=127.0.0.1:18180
GATEWAY_HTTPS_PORT=127.0.0.1:18480
TURN_LISTEN_PORT=3489
TURN_RELAY_MIN_PORT=49860
TURN_RELAY_MAX_PORT=49900

CONTROL_SERVER_IMAGE=$CONTROL_IMAGE
ITSM_IMAGE=$ITSM_IMAGE
RMM_IMAGE=$RMM_IMAGE
ADMIN_IMAGE=$ADMIN_IMAGE

LICENSING_SERVER_URL=$LICENSE_SERVER
LICENSING_PUBLIC_KEY_PEM=$LICENSE_PUBLIC_KEY
LICENSING_REFRESH_INTERVAL_MS=43200000
LICENSING_INITIAL_REFRESH_DELAY_MS=30000
EOF

./scripts/validate.sh --env-file "$ENV_FILE"
services=$(compose config --services)
printf '%s\n' "$services" | grep -qx control-server
printf '%s\n' "$services" | grep -qx itsm-web
printf '%s\n' "$services" | grep -qx rmm-web
if [ "$EDITION" = standard ]; then
  ! printf '%s\n' "$services" | grep -qx admin-web
else
  printf '%s\n' "$services" | grep -qx admin-web
fi

if [ "${HI5_SMOKE_SKIP_PULL:-0}" != "1" ]; then
  compose pull
fi
compose up -d --remove-orphans

wait_healthy() {
  service=$1
  container=$(compose ps -q "$service")
  [ -n "$container" ] || { echo "$service did not start." >&2; exit 1; }
  attempts=0
  while :; do
    status=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container" 2>/dev/null || echo missing)
    [ "$status" = healthy ] && return 0
    case "$status" in exited|dead|unhealthy) echo "$service failed ($status)." >&2; exit 1 ;; esac
    attempts=$((attempts+1))
    [ "$attempts" -lt 60 ] || { echo "Timed out waiting for $service ($status)." >&2; exit 1; }
    sleep 2
  done
}

for service in postgres redis control-server itsm-web rmm-web; do wait_healthy "$service"; done
[ "$EDITION" = msp ] && wait_healthy admin-web

control=$(compose ps -q control-server)
docker exec "$control" test ! -d /app/src
docker exec "$control" node -e "Promise.all([fetch('http://127.0.0.1:3001/live'),fetch('http://127.0.0.1:3001/health')]).then(([a,b])=>{if(!a.ok||!b.ok)process.exit(1)}).catch(()=>process.exit(1))"

if [ "$EDITION" = msp ]; then
  docker exec -e HI5_ACTIVATION_KEY="$LICENSE_KEY" "$control" node -e "fetch('http://127.0.0.1:3001/api/v1/system/license/activate',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({licenseKey:process.env.HI5_ACTIVATION_KEY})}).then(async r=>{const b=await r.json().catch(()=>({}));if(!r.ok||!b.activated){console.error(b);process.exit(1)}}).catch(e=>{console.error(e);process.exit(1)})"
fi

docker exec "$control" node -e "fetch('http://127.0.0.1:3001/api/v1/system/edition').then(async r=>{const b=await r.json();if(b.edition!=='$EDITION') {console.error(b);process.exit(1)};console.log(JSON.stringify(b))}).catch(()=>process.exit(1))"
if [ "$EDITION" = standard ]; then
  docker exec "$control" node -e "fetch('http://127.0.0.1:3001/api/platform/v1/overview').then(r=>{if(r.status!==404)process.exit(1)}).catch(()=>process.exit(1))"
else
  docker exec "$control" node -e "fetch('http://127.0.0.1:3001/api/v1/system/license').then(async r=>{const b=await r.json();if(!r.ok||!['active','grace'].includes(b.status)){console.error(b);process.exit(1)}}).catch(()=>process.exit(1))"
fi

for pair in "itsm-web:Hi5Central ITSM" "rmm-web:Hi5Central RMM"; do
  service=${pair%%:*}; expected=${pair#*:}; container=$(compose ps -q "$service")
  docker exec "$container" wget -qO- http://127.0.0.1/ | grep -Fq "<title>$expected"
done
if [ "$EDITION" = msp ]; then
  container=$(compose ps -q admin-web)
  docker exec "$container" wget -qO- http://127.0.0.1/ | grep -Fq "<title>Hi5Central Admin"
fi

gateway=$(compose ps -q gateway)
docker exec "$gateway" wget --header='Host: itsm.split.localhost' -qO- http://127.0.0.1/ | grep -Fq 'Hi5Central'
docker exec "$gateway" wget --header='Host: api.split.localhost' -qO- http://127.0.0.1/live >/dev/null

tables=$(compose exec -T postgres psql -U hi5central -d hi5central -Atc "select count(*) from information_schema.tables where table_schema=current_schema();")
[ "$tables" -ge 120 ]

echo "Hi5Central $EDITION self-host smoke test passed ($tables public tables)."
