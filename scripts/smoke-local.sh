#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

PROJECT=${HI5_SMOKE_PROJECT:-hi5central-split-smoke}
CONTROL_IMAGE=${HI5_SMOKE_CONTROL_IMAGE:-hi5central-control-server:extract-test}
ITSM_IMAGE=${HI5_SMOKE_ITSM_IMAGE:-hi5central-itsm:extract-test}
RMM_IMAGE=${HI5_SMOKE_RMM_IMAGE:-hi5central-rmm:extract-test}
ADMIN_IMAGE=${HI5_SMOKE_ADMIN_IMAGE:-hi5central-admin:extract-test}
ENV_FILE=$(mktemp)
random_hex() { dd if=/dev/urandom bs="$1" count=1 2>/dev/null | od -An -tx1 | tr -d ' \n'; }
PG_PASSWORD=$(random_hex 18)
REDIS_PASSWORD=$(random_hex 18)
MFA_KEY=$(random_hex 32)
RMM_KEY=$(random_hex 32)
CONNECT_KEY=$(random_hex 32)
trap 'docker compose -p "$PROJECT" --env-file "$ENV_FILE" down -v --remove-orphans >/dev/null 2>&1 || true; rm -f "$ENV_FILE"' EXIT INT TERM

cat >"$ENV_FILE" <<EOF
COMPOSE_PROFILES=itsm,rmm,admin
DEPLOYMENT_MODE=self_hosted
TENANCY_MODE=single
ROOT_DOMAIN=split.localhost
PRIMARY_TENANT_SLUG=local

POSTGRES_DB=hi5central
POSTGRES_USER=hi5central
POSTGRES_PASSWORD=$PG_PASSWORD
REDIS_PASSWORD=$REDIS_PASSWORD

MFA_ENCRYPTION_KEY=$MFA_KEY
RMM_RECOVERY_KEY_ENCRYPTION_KEY=$RMM_KEY
CONNECT_CODE_HMAC_KEY=$CONNECT_KEY

APP_URL=http://itsm.split.localhost
PORTAL_URL=http://itsm.split.localhost/portal
RMM_URL=http://rmm.split.localhost
API_URL=http://api.split.localhost
DOWNLOADS_URL=http://downloads.split.localhost
TURN_URL=
TURN_HOST=turn
MARKETING_URL=http://itsm.split.localhost
COOKIE_DOMAIN=

ITSM_ADDRESS=itsm.split.localhost
RMM_ADDRESS=rmm.split.localhost
ADMIN_ADDRESS=admin.split.localhost
API_ADDRESS=api.split.localhost
DOWNLOADS_ADDRESS=downloads.split.localhost

CONTROL_SERVER_IMAGE=$CONTROL_IMAGE
ITSM_IMAGE=$ITSM_IMAGE
RMM_IMAGE=$RMM_IMAGE
ADMIN_IMAGE=$ADMIN_IMAGE

SELF_HOST_EVALUATION_PRODUCTS=itsm,rmm
SELF_HOST_EVALUATION_USER_LIMIT=10
SELF_HOST_EVALUATION_DEVICE_LIMIT=25
EOF

docker compose -p "$PROJECT" --env-file "$ENV_FILE" up -d postgres redis migrate control-server itsm-web rmm-web admin-web

for _ in $(seq 1 40); do
  control=$(docker inspect -f '{{.State.Health.Status}}' "$PROJECT-control-server-1" 2>/dev/null || echo missing)
  itsm=$(docker inspect -f '{{.State.Health.Status}}' "$PROJECT-itsm-web-1" 2>/dev/null || echo missing)
  rmm=$(docker inspect -f '{{.State.Health.Status}}' "$PROJECT-rmm-web-1" 2>/dev/null || echo missing)
  admin=$(docker inspect -f '{{.State.Health.Status}}' "$PROJECT-admin-web-1" 2>/dev/null || echo missing)
  if [ "$control" = healthy ] && [ "$itsm" = healthy ] && [ "$rmm" = healthy ] && [ "$admin" = healthy ]; then break; fi
  sleep 3
done

[ "$(docker inspect -f '{{.State.Health.Status}}' "$PROJECT-control-server-1")" = healthy ]
[ "$(docker inspect -f '{{.State.Health.Status}}' "$PROJECT-itsm-web-1")" = healthy ]
[ "$(docker inspect -f '{{.State.Health.Status}}' "$PROJECT-rmm-web-1")" = healthy ]
[ "$(docker inspect -f '{{.State.Health.Status}}' "$PROJECT-admin-web-1")" = healthy ]

docker exec "$PROJECT-control-server-1" node -e "Promise.all([fetch('http://127.0.0.1:3001/live'),fetch('http://127.0.0.1:3001/health')]).then(async ([a,b])=>{if(!a.ok||!b.ok)process.exit(1);console.log(await a.text());console.log(await b.text())}).catch(()=>process.exit(1))"

for item in \
  "$PROJECT-itsm-web-1:Hi5Central ITSM" \
  "$PROJECT-rmm-web-1:Hi5Central RMM" \
  "$PROJECT-admin-web-1:Hi5Central Admin"; do
  container=${item%%:*}
  expected=${item#*:}
  docker exec "$container" wget -qO- http://127.0.0.1/ | grep -Fq "<title>$expected"
done

tables=$(docker exec "$PROJECT-postgres-1" sh -lc "psql -U hi5central -d hi5central -Atc \"select count(*) from information_schema.tables where table_schema='public';\"")
[ "$tables" -ge 100 ]

echo "Hi5Central split-stack smoke test passed ($tables public tables)."
