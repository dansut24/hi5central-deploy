#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

ARCHIVE=
YES=0

usage() {
  cat <<'EOF'
Usage: ./scripts/restore.sh BACKUP.tar.gz [--yes]

Restores a Hi5Central backup created by scripts/backup.sh.
This replaces the current database and backed-up Docker volume contents.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --yes) YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -* ) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    * )
      [ -z "$ARCHIVE" ] || { echo "Only one backup archive may be supplied." >&2; exit 2; }
      ARCHIVE=$1
      shift
      ;;
  esac
done

[ -n "$ARCHIVE" ] || { usage >&2; exit 2; }
[ -f "$ARCHIVE" ] || { echo "Backup archive not found: $ARCHIVE" >&2; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "Docker is required." >&2; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "Docker Compose v2 is required." >&2; exit 1; }

if [ "$YES" -ne 1 ]; then
  [ -t 0 ] || { echo "Restore requires --yes when stdin is not interactive." >&2; exit 1; }
  echo "WARNING: this will replace the current Hi5Central database and backed-up volume contents."
  printf "Type RESTORE to continue: "
  IFS= read -r answer
  [ "$answer" = RESTORE ] || { echo "Restore cancelled."; exit 1; }
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/hi5central-restore.XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM
tar -xzf "$ARCHIVE" -C "$WORK"

grep -qx 'format=hi5central-backup-v1' "$WORK/manifest.txt" 2>/dev/null || {
  echo "Unsupported or invalid Hi5Central backup archive." >&2
  exit 1
}
[ -s "$WORK/postgres.dump" ] || { echo "Backup is missing postgres.dump." >&2; exit 1; }
[ -s "$WORK/.env" ] || { echo "Backup is missing .env." >&2; exit 1; }

if [ -f .env ]; then
  cp .env ".env.before-restore-$(date -u +%Y%m%dT%H%M%SZ)"
fi
cp "$WORK/.env" .env
chmod 600 .env

./scripts/validate.sh
PROJECT=$(awk -F= '$1=="COMPOSE_PROJECT_NAME"{print substr($0,index($0,"=")+1)}' .env | tail -1)
PROJECT=${PROJECT:-hi5central}

echo "Stopping application services…"
docker compose down --remove-orphans

# Create all configured named volumes/containers without starting the application.
docker compose create >/dev/null

volume_name() {
  docker volume ls -q \
    --filter "label=com.docker.compose.project=$PROJECT" \
    --filter "label=com.docker.compose.volume=$1" | head -1
}

restore_volume() {
  logical=$1
  source="$WORK/volumes/$logical.tar.gz"
  [ -s "$source" ] || return 0
  volume=$(volume_name "$logical")
  [ -n "$volume" ] || { echo "Could not resolve Docker volume for $logical." >&2; exit 1; }
  echo "Restoring volume: $logical"
  docker run --rm -i -v "$volume:/target" alpine:3.22 sh -lc \
    'find /target -mindepth 1 -maxdepth 1 -exec rm -rf {} +; tar -C /target -xzf -' < "$source"
}

for logical in redis_data downloads app_portal_packages caddy_data caddy_config; do
  restore_volume "$logical"
done

echo "Starting PostgreSQL for database restore…"
docker compose up -d postgres
postgres_id=$(docker compose ps -q postgres)
attempts=0
while :; do
  status=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$postgres_id" 2>/dev/null || echo missing)
  [ "$status" = healthy ] && break
  attempts=$((attempts + 1))
  [ "$attempts" -lt 60 ] || { echo "Timed out waiting for PostgreSQL ($status)." >&2; exit 1; }
  sleep 2
done

echo "Restoring PostgreSQL database…"
docker compose exec -T postgres sh -lc 'dropdb --if-exists --force -U "$POSTGRES_USER" "$POSTGRES_DB"'
docker compose exec -T postgres sh -lc 'createdb -U "$POSTGRES_USER" "$POSTGRES_DB"'
cat "$WORK/postgres.dump" | docker compose exec -T postgres sh -lc 'pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --no-privileges'

echo "Starting restored Hi5Central stack and applying any newer migrations…"
docker compose up -d --remove-orphans

active_services="postgres redis control-server"
profiles=$(awk -F= '$1=="COMPOSE_PROFILES"{print substr($0,index($0,"=")+1)}' .env | tail -1)
case ",$profiles," in *,itsm,*) active_services="$active_services itsm-web" ;; esac
case ",$profiles," in *,rmm,*) active_services="$active_services rmm-web" ;; esac
case ",$profiles," in *,admin,*) active_services="$active_services admin-web" ;; esac

for service in $active_services; do
  container=$(docker compose ps -q "$service")
  attempts=0
  while :; do
    status=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container" 2>/dev/null || echo missing)
    [ "$status" = healthy ] && break
    case "$status" in exited|dead|unhealthy) echo "$service failed after restore ($status)." >&2; exit 1 ;; esac
    attempts=$((attempts + 1))
    [ "$attempts" -lt 60 ] || { echo "Timed out waiting for $service ($status)." >&2; exit 1; }
    sleep 2
  done
  echo "  ✓ $service"
done

echo
echo "Restore complete."
echo "Run ./scripts/preflight.sh and verify the web interfaces before reopening external access."
