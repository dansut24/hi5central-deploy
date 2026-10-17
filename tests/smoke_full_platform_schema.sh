#!/usr/bin/env bash
# Isolated full Platform migration + catalogue + Admin restore test.
# No public PostgreSQL port, real customer data, IONOS action or live workers.
set -Eeuo pipefail
set +x
NAME=hi5central-managed-postgres-1
NET="h5c-fullschema-ci-$$"
API=platform/services/api
test -f "$API/src/migrate.js" && test -f "$API/package-lock.json"
if docker inspect "$NAME" >/dev/null 2>&1;then
 echo "BLOCKED: disposable Postgres name in use" >&2;exit 3
fi
WORK="$(mktemp -d)"
CREATED_NET=no
cleanup(){
 docker rm -f "$NAME" >/dev/null 2>&1 || true
 if [[ "$CREATED_NET" == yes ]];then docker network rm "$NET" >/dev/null 2>&1 || true;fi
 rm -rf -- "$WORK"
}
trap cleanup EXIT
docker network create "$NET" >/dev/null
CREATED_NET=yes
docker run -d --name "$NAME" --network "$NET" \
 --label com.docker.compose.project=hi5central-managed \
 --label com.docker.compose.service=postgres \
 -e POSTGRES_DB=hi5central -e POSTGRES_USER=hi5central \
 -e POSTGRES_PASSWORD=disposable-ci-password postgres:17-alpine >/dev/null
for i in $(seq 1 45);do
 if [[ "$(docker exec "$NAME" psql -X -Atqc 'SELECT 1' -U hi5central -d hi5central 2>/dev/null || true)" == 1 ]];then break;fi
 sleep 1
done
test "$(docker exec "$NAME" psql -X -Atqc 'SELECT 1' -U hi5central -d hi5central)" = 1
echo "Executing exact pinned Platform API migration runner (isolated Docker network)."
if ! docker run --rm --network "$NET" \
 -v "$(realpath "$API"):/workspace" -w /workspace \
 -e "DATABASE_URL=postgresql://hi5central:disposable-ci-password@$NAME:5432/hi5central" \
 node:24-alpine sh -ec 'npm ci --ignore-scripts --no-audit --no-fund >/dev/null && npm run migrate' \
 >"$WORK/migration.log" 2>&1;then
 echo "BLOCKED: real Platform migration set failed:" >&2
 tail -n 85 "$WORK/migration.log" >&2;exit 3
fi
echo "PASS: full Platform migration runner completed."
docker exec -i "$NAME" psql -X -v ON_ERROR_STOP=1 -U hi5central -d hi5central <<'SQL'
BEGIN READ ONLY;
DO $h5$
DECLARE n integer;
BEGIN
 SELECT count(*) INTO n FROM schema_migrations;
 IF n<145 THEN RAISE EXCEPTION 'Incomplete migration ledger: %',n;END IF;
 IF (SELECT count(*) FROM tenants)<>0
 OR (SELECT count(*) FROM users)<>0
 OR (SELECT count(*) FROM rmm_agent_devices)<>0
 OR (SELECT count(*) FROM rmm_software_qualification_queue)<>0
 OR (SELECT count(*) FROM tenant_release_rollout_jobs)<>0
 OR (SELECT paused FROM platform_release_rollout_control WHERE singleton=true) IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'Migrations did not produce zero-tenant paused database';END IF;
END $h5$;
ROLLBACK;
SQL
python3 tests/make_full_schema_seed.py "$WORK/seed.tar.gz"
python3 scripts/verify-global-software-catalogue.py "$WORK/seed.tar.gz"
sudo env GITHUB_ACTIONS=true python3 scripts/import-global-software-catalogue.py --archive "$WORK/seed.tar.gz" --apply
docker exec -i "$NAME" psql -X -v ON_ERROR_STOP=1 -U hi5central -d hi5central <<'SQL'
BEGIN READ ONLY;
DO $h5$
BEGIN
 IF (SELECT count(*) FROM tenants)<>0
 OR (SELECT count(*) FROM users)<>0
 OR (SELECT count(*) FROM rmm_software_catalogue)<>1
 OR (SELECT count(*) FROM rmm_software_vendor_sources)<>1
 OR (SELECT count(*) FROM rmm_software_vendor_bindings)<>1
 OR (SELECT count(*) FROM rmm_software_vendor_releases)<>1
 THEN RAISE EXCEPTION 'Catalogued global-only seed mismatch';END IF;
END $h5$;
ROLLBACK;
SQL
mkdir -m 700 "$WORK/secrets"
printf '%096x\n' 598731 >"$WORK/secrets/pgadmin-editor-password"
printf '%s\n' 'ci-owner-password-unique-strong-with-over-fifty-characters-1234567890' >"$WORK/secrets/platform-owner-password"
printf '%s\n' '{"format":"hi5-managed-secrets-v1","phase":"secrets-prepared-only","fresh_tenants_created":0,"pgadmin_email":"owner@example.invalid"}' >"$WORK/secrets/setup-state.json"
chmod 600 "$WORK/secrets/"*
sudo python3 scripts/configure-managed-db-editor.py --root "$WORK/secrets" --apply
sudo python3 scripts/bootstrap-managed-platform-owner.py --root "$WORK/secrets" --apply
docker exec -i "$NAME" psql -X -v ON_ERROR_STOP=1 -U hi5central -d hi5central <<'SQL'
BEGIN READ ONLY;
DO $h5$
BEGIN
 IF (SELECT count(*) FROM tenants)<>0
 OR (SELECT count(*) FROM users)<>1
 OR (SELECT count(*) FROM platform_admin_members WHERE role='owner' AND status='active')<>1
 OR (SELECT count(*) FROM platform_admin_audit_events WHERE action='platform.bootstrap.owner')<>1
 THEN RAISE EXCEPTION 'Full Platform Owner bootstrap mismatch';END IF;
END $h5$;
ROLLBACK;
SQL
docker exec "$NAME" psql -X -Atqc \
 "SELECT password_hash FROM users WHERE email='owner@example.invalid'" \
 -U hi5central -d hi5central >"$WORK/owner-hash"
python3 tests/test_managed_owner_password.py "$WORK/owner-hash" "$WORK/secrets/platform-owner-password"
EDITOR_PASSWORD="$(cat "$WORK/secrets/pgadmin-editor-password")"
docker exec -i -e "PGPASSWORD=$EDITOR_PASSWORD" "$NAME" \
 psql -h 127.0.0.1 -X -v ON_ERROR_STOP=1 \
 -U hi5_pgadmin_editor -d hi5central <<'SQL'
BEGIN;
CREATE TABLE public.hi5_fresh_install_editor_test (id integer PRIMARY KEY,value text NOT NULL);
INSERT INTO public.hi5_fresh_install_editor_test VALUES(1,'created');
UPDATE public.hi5_fresh_install_editor_test SET value='updated' WHERE id=1;
DO $h5$ BEGIN
 IF (SELECT value FROM public.hi5_fresh_install_editor_test WHERE id=1)<>'updated'
 THEN RAISE EXCEPTION 'Authenticated editor UPDATE failed';END IF;
END $h5$;
DELETE FROM public.hi5_fresh_install_editor_test WHERE id=1;
DROP TABLE public.hi5_fresh_install_editor_test;
COMMIT;
SQL
unset EDITOR_PASSWORD
echo "PASS: full Platform schema, global catalogue, global Owner and authenticated full-DML editor; zero tenants."
echo "CI fixture only; no IONOS VPS touched and no real catalogue archive imported."
