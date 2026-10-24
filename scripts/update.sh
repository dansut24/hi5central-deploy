#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

compose() {
  if [ -f .env ] && grep -Eq '^RELEASE_EDGE_NETWORK=.+' .env; then
    docker compose -f compose.yml -f compose.release-edge.yml "$@"
  else
    docker compose "$@"
  fi
}

[ -f .env ] || { echo "Missing .env. Run ./install.sh first." >&2; exit 1; }
./scripts/validate.sh

channel=$(awk -F= '$1=="RELEASE_CHANNEL"{print substr($0,index($0,"=")+1)}' .env | tail -1)
channel=${channel:-stable}
echo "Hi5Central update channel: $channel"

if [ "${HI5_SKIP_UPDATE_BACKUP:-0}" != 1 ] && [ -n "$(compose ps -q postgres 2>/dev/null || true)" ]; then
  echo "Creating pre-update backup..."
  ./scripts/backup.sh
fi

echo "Pulling approved $channel images..."
compose pull

echo "Applying database migrations and updating services..."
compose up -d --remove-orphans

active_services="postgres redis control-server"
profiles=$(awk -F= '$1=="COMPOSE_PROFILES"{print substr($0,index($0,"=")+1)}' .env | tail -1)
case ",$profiles," in *,itsm,*) active_services="$active_services itsm-web" ;; esac
case ",$profiles," in *,rmm,*) active_services="$active_services rmm-web" ;; esac
case ",$profiles," in *,admin,*) active_services="$active_services admin-web" ;; esac

echo "Verifying updated services..."
for service in $active_services; do
  container=$(compose ps -q "$service")
  [ -n "$container" ] || { echo "$service did not start." >&2; exit 1; }
  attempts=0
  while :; do
    status=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container" 2>/dev/null || echo missing)
    [ "$status" = healthy ] && break
    case "$status" in
      exited|dead|unhealthy)
        echo "$service failed after update ($status)." >&2
        compose logs --tail=100 "$service" >&2 || true
        exit 1
        ;;
    esac
    attempts=$((attempts + 1))
    [ "$attempts" -lt 60 ] || { echo "Timed out waiting for $service ($status)." >&2; exit 1; }
    sleep 2
  done
  echo "  ✓ $service"
done

docker image prune -f >/dev/null
compose ps

echo
echo "Update complete."
echo "A pre-update backup was created unless HI5_SKIP_UPDATE_BACKUP=1 was supplied."
