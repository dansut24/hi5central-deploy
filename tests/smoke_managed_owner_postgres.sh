#!/usr/bin/env bash
# Disposable integration test for zero-tenant global Platform Owner bootstrap.
# Runs AFTER catalogue smoke and only on GitHub's disposable Docker engine.
set -Eeuo pipefail
NAME="hi5central-managed-postgres-1"
if docker inspect "$NAME" >/dev/null 2>&1;then
 echo 'BLOCKED: test DB container name already exists.' >&2
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
 -e POSTGRES_PASSWORD=ci-only-disposable \
 postgres:17-alpine >/dev/null
for i in $(seq 1 40);do
 if [[ "$(docker exec "$NAME" psql -X -Atqc 'SELECT 1' -U hi5central -d hi5central 2>/dev/null || true)" == 1 ]];then break;fi
 sleep 1
done
docker exec -i "$NAME" psql -X -v ON_ERROR_STOP=1 -U hi5central -d hi5central <<'SQL'
CREATE TABLE tenants (id uuid PRIMARY KEY DEFAULT gen_random_uuid());
CREATE TABLE users (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 email text NOT NULL UNIQUE,
 name text NOT NULL,
 password_hash text NOT NULL,
 email_verified_at timestamptz
);
CREATE TABLE schema_migrations(version text PRIMARY KEY);
INSERT INTO schema_migrations(version) VALUES ('082_platform_admin_control_plane.sql');
CREATE TABLE platform_admin_members(
 user_id uuid PRIMARY KEY REFERENCES users(id),
 role text NOT NULL,
 status text NOT NULL
);
CREATE TABLE platform_admin_audit_events(
 actor_user_id uuid REFERENCES users(id),
 action text NOT NULL,
 target_type text NOT NULL,
 metadata jsonb NOT NULL
);
CREATE TABLE tenant_release_rollout_jobs(id uuid PRIMARY KEY DEFAULT gen_random_uuid());
CREATE TABLE platform_release_rollout_control(
 singleton boolean PRIMARY KEY, paused boolean NOT NULL
);
INSERT INTO platform_release_rollout_control VALUES(true,true);
SQL
mkdir -m 700 "$WORK/secrets"
printf '%s\n' 'ci-platform-owner-secret-with-sufficient-entropy-abcdef-12345678' > "$WORK/secrets/platform-owner-password"
printf '%s\n' '{"format":"hi5-managed-secrets-v1","phase":"secrets-prepared-only","fresh_tenants_created":0,"pgadmin_email":"owner@example.invalid"}' > "$WORK/secrets/setup-state.json"
chmod 600 "$WORK/secrets/"*
sudo python3 scripts/bootstrap-managed-platform-owner.py --root "$WORK/secrets" --dry-run
sudo python3 scripts/bootstrap-managed-platform-owner.py --root "$WORK/secrets" --apply
docker exec -i "$NAME" psql -X -v ON_ERROR_STOP=1 -U hi5central -d hi5central <<'SQL'
DO $h5$
BEGIN
 IF (SELECT count(*) FROM users)<>1
 OR (SELECT count(*) FROM tenants)<>0
 OR (SELECT count(*) FROM platform_admin_members WHERE role='owner' AND status='active')<>1
 OR (SELECT count(*) FROM platform_admin_audit_events WHERE action='platform.bootstrap.owner')<>1
 THEN RAISE EXCEPTION 'Owner bootstrap created unexpected state';END IF;
END $h5$;
SQL
docker exec "$NAME" psql -X -Atqc \
 "SELECT password_hash FROM users WHERE email='owner@example.invalid'" \
 -U hi5central -d hi5central >"$WORK/hash"
python3 tests/test_managed_owner_password.py "$WORK/hash" "$WORK/secrets/platform-owner-password"
set +e
sudo python3 scripts/bootstrap-managed-platform-owner.py --root "$WORK/secrets" --apply >"$WORK/repeat-rejected" 2>&1
rc=$?
set -e
if [[ "$rc" -eq 0 ]];then echo 'FAILED: permitted a second owner bootstrap' >&2;exit 2;fi
docker exec -i "$NAME" psql -X -v ON_ERROR_STOP=1 -U hi5central -d hi5central <<'SQL'
DO $h5$
BEGIN
 IF (SELECT count(*) FROM users)<>1
 OR (SELECT count(*) FROM platform_admin_audit_events WHERE action='platform.bootstrap.owner')<>1
 THEN RAISE EXCEPTION 'Rejected owner bootstrap modified database';END IF;
END $h5$;
SQL
echo 'PASS: global Owner created with zero tenants; audit/hash valid; duplicate bootstrap rejected.'
