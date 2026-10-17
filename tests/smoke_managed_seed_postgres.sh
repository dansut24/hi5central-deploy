#!/usr/bin/env bash
# Disposable CI-only PostgreSQL integration: catalogue restore + read/write DBA.
# Never accepts a pre-existing container with this name; always cleans itself.
set -Eeuo pipefail
export LC_ALL=C
NAME="hi5central-managed-postgres-1"
if docker inspect "$NAME" >/dev/null 2>&1;then
 echo 'BLOCKED: disposable CI container name already in use.' >&2
 exit 2
fi
WORK="$(mktemp -d)"
cleanup(){
 docker rm -f "$NAME" >/dev/null 2>&1 || true
 rm -rf -- "$WORK"
}
trap cleanup EXIT
docker run -d --name "$NAME" \
 --label com.docker.compose.project=hi5central-managed \
 --label com.docker.compose.service=postgres \
 -e POSTGRES_DB=hi5central -e POSTGRES_USER=hi5central \
 -e POSTGRES_PASSWORD=ci-only-not-for-production \
 postgres:17-alpine >/dev/null
for i in $(seq 1 40);do
 if docker exec "$NAME" pg_isready -U hi5central -d hi5central >/dev/null 2>&1;then break;fi
 sleep 1
done
docker exec -i "$NAME" psql -X -v ON_ERROR_STOP=1 -U hi5central -d hi5central <<'SQL'
CREATE TABLE tenants(id text PRIMARY KEY);
CREATE TABLE users(id text PRIMARY KEY);
CREATE TABLE rmm_agent_devices(id text PRIMARY KEY);
CREATE TABLE itsm_records(id text PRIMARY KEY);
CREATE TABLE rmm_software_qualification_queue(id text PRIMARY KEY);
CREATE TABLE tenant_release_rollout_jobs(id text PRIMARY KEY);
CREATE TABLE platform_release_rollout_control(
  singleton boolean PRIMARY KEY,paused boolean NOT NULL
);
INSERT INTO platform_release_rollout_control VALUES(true,true);
CREATE TABLE rmm_software_vendor_sources (
 source_key text PRIMARY KEY,source_type text,source_url text
);
CREATE TABLE rmm_software_vendor_bindings (
 id text PRIMARY KEY,source_key text NOT NULL REFERENCES rmm_software_vendor_sources(source_key),
 provider_package_id text,channel text,platform text,architecture text
);
CREATE TABLE rmm_software_vendor_releases (
 id text PRIMARY KEY,source_key text NOT NULL REFERENCES rmm_software_vendor_sources(source_key),
 provider_package_id text,channel text,platform text,architecture text,version text
);
CREATE TABLE rmm_software_catalogue (
 id text PRIMARY KEY,tenant_id text REFERENCES tenants(id),
 catalogue_source text,external_key text,status text
);
-- Simulate migration-seeded vendor defaults that MUST be replaced in the
-- fresh database within the guarded transaction (not on Production).
INSERT INTO rmm_software_vendor_sources VALUES('migration-seed','vendor_api','https://seed.invalid');
SQL
python3 - "$WORK/catalogue.tar.gz" <<'PY'
import sys
from pathlib import Path
sys.path.insert(0,str(Path('tests').resolve()))
from test_global_software_seed import SeedTest
SeedTest().pack(Path(sys.argv[1]))
PY
python3 scripts/verify-global-software-catalogue.py "$WORK/catalogue.tar.gz"
sudo python3 scripts/import-global-software-catalogue.py \
 --archive "$WORK/catalogue.tar.gz" --apply
docker exec -i "$NAME" psql -X -v ON_ERROR_STOP=1 -U hi5central -d hi5central <<'SQL'
DO $h5$
BEGIN
 IF (SELECT count(*) FROM rmm_software_catalogue)<>1 OR
    (SELECT count(*) FROM rmm_software_vendor_sources)<>1 OR
    (SELECT count(*) FROM rmm_software_vendor_releases)<>1 OR
    (SELECT count(*) FROM rmm_software_vendor_bindings)<>1 OR
    (SELECT count(*) FROM rmm_software_vendor_sources WHERE source_key='migration-seed')<>0
 THEN RAISE EXCEPTION 'CI catalogue import row mismatch'; END IF;
END $h5$;
SQL
mkdir -p "$WORK/secrets"
chmod 700 "$WORK/secrets"
printf '%096x\n' 123456789 > "$WORK/secrets/pgadmin-editor-password"
chmod 600 "$WORK/secrets/pgadmin-editor-password"
sudo python3 scripts/configure-managed-db-editor.py \
 --root "$WORK/secrets" --apply
docker exec -i "$NAME" psql -X -v ON_ERROR_STOP=1 -U hi5central -d hi5central <<'SQL'
BEGIN;
SET ROLE hi5_pgadmin_editor;
INSERT INTO rmm_software_catalogue(id,tenant_id,status)
 VALUES('dbeditor-ci',NULL,'active');
UPDATE rmm_software_catalogue SET status='disabled' WHERE id='dbeditor-ci';
DO $h5$
BEGIN
 IF (SELECT status FROM rmm_software_catalogue WHERE id='dbeditor-ci')<>'disabled'
 THEN RAISE EXCEPTION 'Editor UPDATE failed'; END IF;
END $h5$;
DELETE FROM rmm_software_catalogue WHERE id='dbeditor-ci';
ROLLBACK;
SELECT rolname,rolsuper,rolbypassrls
FROM pg_roles WHERE rolname='hi5_pgadmin_editor';
INSERT INTO tenants VALUES('ci-tenant');
SQL
# The second import must refuse the no-longer-empty database without changing
# even migration-seeded global software data.
set +e
sudo python3 scripts/import-global-software-catalogue.py \
 --archive "$WORK/catalogue.tar.gz" --apply >"$WORK/reject.log" 2>&1
rc=$?
set -e
[[ "$rc" -ne 0 ]] || { echo 'FAIL: importer accepted existing tenants' >&2; exit 2;}
grep -Fq "transaction was rolled back" "$WORK/reject.log"
docker exec -i "$NAME" psql -X -v ON_ERROR_STOP=1 -U hi5central -d hi5central <<'SQL'
DO $h5$
BEGIN
 IF (SELECT count(*) FROM rmm_software_vendor_sources)<>1
 OR (SELECT count(*) FROM rmm_software_catalogue)<>1
 THEN RAISE EXCEPTION 'Rejected import modified catalogue'; END IF;
END $h5$;
SQL
echo 'PASS: disposable PostgreSQL seed restore, full DML editor and nonempty-database denial.'
