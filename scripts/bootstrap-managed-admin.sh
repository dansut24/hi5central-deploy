#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

EMAIL=${1:-}
TENANT_SLUG=${2:-test}
ENV_FILE=${HI5_ENV_FILE:-.env}

[ -n "$EMAIL" ] || {
  echo "Usage: ./scripts/bootstrap-managed-admin.sh <email> [tenant-slug]" >&2
  exit 2
}
[ -f "$ENV_FILE" ] || { echo "Missing $ENV_FILE." >&2; exit 1; }

case "$TENANT_SLUG" in
  ''|*[!a-z0-9-]*|-*|*-) echo "Invalid tenant slug: $TENANT_SLUG" >&2; exit 1 ;;
esac

read_env() {
  awk -F= -v key="$1" '$1==key{print substr($0,index($0,"=")+1)}' "$ENV_FILE" | tail -1
}

[ "$(read_env DEPLOYMENT_MODE)" = managed ] || {
  echo "This bootstrap is only available for DEPLOYMENT_MODE=managed." >&2
  exit 1
}

POSTGRES_USER_VALUE=$(read_env POSTGRES_USER)
POSTGRES_DB_VALUE=$(read_env POSTGRES_DB)
POSTGRES_USER_VALUE=${POSTGRES_USER_VALUE:-hi5central}
POSTGRES_DB_VALUE=${POSTGRES_DB_VALUE:-hi5central}

docker compose --env-file "$ENV_FILE" exec -T postgres   psql -X -v ON_ERROR_STOP=1   -U "$POSTGRES_USER_VALUE"   -d "$POSTGRES_DB_VALUE"   -v bootstrap_email="$EMAIL"   -v bootstrap_slug="$TENANT_SLUG" <<'SQL'
SELECT u.id::text AS bootstrap_user_id, t.id::text AS bootstrap_tenant_id
  FROM users u
  JOIN tenant_memberships m ON m.user_id=u.id
  JOIN tenants t ON t.id=m.tenant_id
 WHERE lower(u.email)=lower(:'bootstrap_email')
   AND t.slug=:'bootstrap_slug'
 ORDER BY m.created_at
 LIMIT 1
\gset

\if :{?bootstrap_user_id}
UPDATE users
   SET email_verified_at=COALESCE(email_verified_at,now()),
       updated_at=now()
 WHERE id=:'bootstrap_user_id'::uuid;

UPDATE tenants
   SET status='active',
       updated_at=now()
 WHERE id=:'bootstrap_tenant_id'::uuid;

UPDATE tenant_memberships
   SET status='active'
 WHERE tenant_id=:'bootstrap_tenant_id'::uuid
   AND user_id=:'bootstrap_user_id'::uuid;

UPDATE tenant_settings
   SET onboarding_step=CASE
         WHEN onboarding_completed_at IS NULL AND onboarding_step='verify_email' THEN 'company'
         ELSE onboarding_step
       END,
       updated_at=now()
 WHERE tenant_id=:'bootstrap_tenant_id'::uuid;

UPDATE user_email_verifications
   SET used_at=COALESCE(used_at,now())
 WHERE tenant_id=:'bootstrap_tenant_id'::uuid
   AND user_id=:'bootstrap_user_id'::uuid
   AND used_at IS NULL;

INSERT INTO platform_admin_members (user_id,role,status)
VALUES (:'bootstrap_user_id'::uuid,'owner','active')
ON CONFLICT (user_id) DO UPDATE
   SET role='owner',
       status='active',
       updated_at=now();

INSERT INTO platform_admin_audit_events
  (actor_user_id,action,target_type,target_id,metadata)
VALUES
  (:'bootstrap_user_id'::uuid,'platform.bootstrap.owner','tenant',:'bootstrap_tenant_id',
   jsonb_build_object('tenantSlug',:'bootstrap_slug','bootstrap','regional-managed'));

SELECT t.slug,u.email,p.role,p.status
  FROM tenants t
  JOIN tenant_memberships m ON m.tenant_id=t.id
  JOIN users u ON u.id=m.user_id
  JOIN platform_admin_members p ON p.user_id=u.id
 WHERE t.id=:'bootstrap_tenant_id'::uuid
   AND u.id=:'bootstrap_user_id'::uuid;
\else
\echo 'No matching managed tenant/user exists. Complete signup first, then rerun this command.'
\quit 3
\endif
SQL

echo
echo "Managed Platform Admin bootstrap complete for $EMAIL on tenant $TENANT_SLUG."
