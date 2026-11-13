#!/usr/bin/env bash
# Managed single-VPS baseline backup: PostgreSQL databases and cluster roles only.
# Requires root, local Docker daemon, flock, and the hi5central-db-1 container.
set -Eeuo pipefail
umask 077
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

root=/opt/hi5central/recovery/scheduled-postgres
container=hi5central-db-1
retention_days=14
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
install -d -m 0700 "$root"
exec 9>"$root/.backup.lock"
if ! flock -n 9; then
  echo "BACKUP_SKIPPED another backup is running"
  exit 0
fi
if [[ "$(id -u)" -ne 0 ]]; then
  echo "BACKUP_FAILED run this task as root" >&2
  exit 1
fi
status="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container")"
if [[ "$status" != "healthy" ]]; then
  echo "BACKUP_FAILED postgres container is not healthy: $status" >&2
  exit 1
fi
work="$(mktemp -d "$root/.pending-XXXXXXXX")"
cleanup() { if [[ -n "$work" && -d "$work" ]]; then rm -rf -- "$work"; fi; }
trap cleanup EXIT

for db in hi5central hi5central_dev hi5central_test hi5central_uat; do
  file="$work/$db.pgcustom"
  docker exec "$container" sh -c 'exec pg_dump -U "$POSTGRES_USER" -d "$1" -Fc --no-owner --no-privileges' _ "$db" > "$file"
  [[ -s "$file" ]] || { echo "BACKUP_FAILED $db empty archive" >&2; exit 1; }
  docker exec -i "$container" pg_restore --list < "$file" >/dev/null
  chmod 0600 "$file"
  echo "BACKUP_ARCHIVE_VALID $db bytes=$(stat -c%s "$file")"
done

docker exec "$container" sh -c 'exec pg_dumpall -U "$POSTGRES_USER" --globals-only' > "$work/globals.sql"
[[ -s "$work/globals.sql" ]] || { echo "BACKUP_FAILED globals empty" >&2; exit 1; }
chmod 0600 "$work/globals.sql"
(
  cd "$work"
  sha256sum ./*.pgcustom ./globals.sql > manifest.sha256
  sha256sum -c manifest.sha256 >/dev/null
)
final="$root/$stamp"
[[ ! -e "$final" ]] || { echo "BACKUP_FAILED timestamp collision" >&2; exit 1; }
mv -- "$work" "$final"
work=""
echo "BACKUP_COMPLETE $stamp files=5"

# Only delete directories from this script's dedicated backup root with a valid manifest.
while IFS= read -r -d '' old; do
  if [[ -f "$old/manifest.sha256" ]]; then
    rm -rf -- "$old"
    echo "BACKUP_PRUNED $(basename "$old")"
  fi
done < <(find "$root" -mindepth 1 -maxdepth 1 -type d -name '20*Z' -mtime +"$((retention_days - 1))" -print0)
