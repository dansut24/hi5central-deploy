#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

[ -f .env ] || { echo "Missing .env." >&2; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "Docker is required." >&2; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "Docker Compose v2 is required." >&2; exit 1; }

OUTPUT_DIR=${HI5_BACKUP_DIR:-$ROOT_DIR/backups}
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
PROJECT=$(awk -F= '$1=="COMPOSE_PROJECT_NAME"{print substr($0,index($0,"=")+1)}' .env | tail -1)
PROJECT=${PROJECT:-hi5central}
WORK="$OUTPUT_DIR/.hi5central-backup-$STAMP-$$"
ARCHIVE="$OUTPUT_DIR/hi5central-backup-$STAMP.tar.gz"

umask 077
mkdir -p "$OUTPUT_DIR" "$WORK/volumes"
trap 'rm -rf "$WORK"' EXIT INT TERM

postgres_id=$(docker compose ps -q postgres)
[ -n "$postgres_id" ] || { echo "PostgreSQL container is not running." >&2; exit 1; }
status=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$postgres_id")
[ "$status" = healthy ] || { echo "PostgreSQL is not healthy ($status)." >&2; exit 1; }

echo "Creating PostgreSQL logical backup…"
docker compose exec -T postgres sh -lc 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc' > "$WORK/postgres.dump"

if docker compose ps -q redis >/dev/null 2>&1 && [ -n "$(docker compose ps -q redis)" ]; then
  echo "Persisting Redis before volume archive…"
  docker compose exec -T redis sh -lc 'redis-cli -a "$REDIS_PASSWORD" SAVE >/dev/null' || true
fi

cp .env "$WORK/.env"
chmod 600 "$WORK/.env"

cat > "$WORK/manifest.txt" <<EOF
format=hi5central-backup-v1
created_at=$STAMP
project=$PROJECT
compose_profiles=$(awk -F= '$1=="COMPOSE_PROFILES"{print substr($0,index($0,"=")+1)}' .env | tail -1)
deployment_mode=$(awk -F= '$1=="DEPLOYMENT_MODE"{print substr($0,index($0,"=")+1)}' .env | tail -1)
root_domain=$(awk -F= '$1=="ROOT_DOMAIN"{print substr($0,index($0,"=")+1)}' .env | tail -1)
EOF

volume_name() {
  docker volume ls -q \
    --filter "label=com.docker.compose.project=$PROJECT" \
    --filter "label=com.docker.compose.volume=$1" | head -1
}

archive_volume() {
  logical=$1
  volume=$(volume_name "$logical")
  [ -n "$volume" ] || return 0
  echo "Archiving volume: $logical"
  docker run --rm -v "$volume:/source:ro" alpine:3.22 sh -lc 'tar -C /source -czf - .' > "$WORK/volumes/$logical.tar.gz"
}

for logical in redis_data downloads app_portal_packages caddy_data caddy_config; do
  archive_volume "$logical"
done

(
  cd "$WORK"
  tar -czf "$ARCHIVE.tmp" .
)
mv "$ARCHIVE.tmp" "$ARCHIVE"
chmod 600 "$ARCHIVE"

bytes=$(wc -c < "$ARCHIVE" | tr -d ' ')
echo
echo "Backup complete:"
echo "  $ARCHIVE"
echo "  $bytes bytes"
echo
echo "The archive contains .env and therefore secrets. Store it as sensitive backup material."
