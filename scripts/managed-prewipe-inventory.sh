#!/usr/bin/env bash
# Hi5Central managed clean-install discovery. READ ONLY.
# Inventory must be reviewed before any old VPS removal/volume deletion.
# Does not print secret env vars, mutate PostgreSQL, stop Docker or prune data.
set -Eeuo pipefail
set +x
echo '===== HI5CENTRAL PRE-WIPE SERVICE AND DATA INVENTORY (READ ONLY) ====='
command -v docker >/dev/null || { echo 'BLOCKED: Docker unavailable'; exit 2; }
date -u '+Inventory UTC: %Y-%m-%dT%H:%M:%SZ'
echo
echo '1. Running containers / reviewed image references'
docker ps --format 'name={{.Names}} image={{.Image}} status={{.Status}}'
echo
echo '2. Container groups needed by the future clean install'
# Search names only. Do not dump docker inspect Config.Env or Compose secrets.
names="$(docker ps -a --format '{{.Names}}')"
for row in \
  'api-control:control-server|hi5central-api|platform-api' \
  'itsm-portal:itsm|portal' \
  'rmm-control:rmm|control' \
  'turn:turn|coturn' \
  'software-qualification:qualif|software-worker|software-runner' \
  'releases:release-executor|release-operator|fanout|planner' \
  'database:postgres' \
  'cache:redis' \
  'edge:caddy|gateway|hi5central-web' \
  'admin:admin'
do
  group="${row%%:*}"; pattern="${row#*:}"
  echo "--- $group ---"
  if ! printf '%s\n' "$names" | grep -Ei "$pattern";then
    echo 'NOT IDENTIFIED: needs source/image/volume confirmation before wiping'
  fi
done
echo
echo '3. Persistent volumes (name only; inspect before deleting)'
docker volume ls --format '{{.Name}}'
echo
echo '4. Network names'
docker network ls --format '{{.Name}}'
echo
echo '5. Port bindings'
docker ps --format '{{.Names}} {{.Ports}}'
echo
echo '6. Live PostgreSQL RELEASE/SCHEMA METADATA ONLY'
if docker inspect hi5central-postgres >/dev/null 2>&1;then
 docker exec -i hi5central-postgres sh -c \
   'exec psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -X -v ON_ERROR_STOP=1' <<'SQL'
BEGIN READ ONLY;
SET LOCAL statement_timeout='15s';
SELECT current_database() AS database,pg_size_pretty(pg_database_size(current_database())) AS total_size;
SELECT count(*) AS tenant_count FROM tenants;
SELECT status,count(*) AS release_jobs
 FROM tenant_release_rollout_jobs GROUP BY status ORDER BY status;
SELECT paused,updated_at FROM platform_release_rollout_control WHERE singleton=true;
SELECT count(*) AS migrations_in_ledger FROM schema_migrations;
SELECT schemaname,relname,
 pg_size_pretty(pg_total_relation_size(format('%I.%I',schemaname,relname))) AS size
FROM pg_stat_user_tables
WHERE schemaname='public'
ORDER BY pg_total_relation_size(format('%I.%I',schemaname,relname)) DESC LIMIT 25;
SELECT rolname,rolsuper,rolcanlogin
FROM pg_roles WHERE rolname LIKE 'hi5%' ORDER BY rolname;
ROLLBACK;
SQL
else
 echo 'BLOCKED: hi5central-postgres not found; identify the active DB first.'
fi
echo
echo '===== END OF READ-ONLY PRE-WIPE INVENTORY ====='
echo 'NO CONTAINERS, SCHEMAS, NETWORKS, VOLUMES OR CUSTOMER DATA REMOVED'
