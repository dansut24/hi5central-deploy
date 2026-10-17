#!/usr/bin/env python3
"""One-time tenant-independent global owner bootstrap in NEW managed Postgres.

Reads generated private owner password from a mode-600 file, derives the same
scrypt encoding as Platform services/api/src/password.js, and installs an owner
in users + platform_admin_members. This never creates tenants or memberships.
This bootstrap is for initial setup ONLY, not account recovery/role promotion.
"""
import argparse
import base64
import hashlib
import hmac
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys

CONTAINER="hi5central-managed-postgres-1"
EMAIL=re.compile(r"^[A-Za-z0-9._+%-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,63}$")

def require(ok,message):
 if not ok: raise RuntimeError(message)
def q(value):
 require("'" not in value and "\\" not in value and "\n" not in value,"Unsafe SQL parameter.")
 return "'"+value+"'"
def b64url(blob):
 return base64.urlsafe_b64encode(blob).decode("ascii").rstrip("=")
def encoded_password(password):
 require(len(password)>=32,"Owner credential must be strong.")
 salt=os.urandom(16)
 raw=hashlib.scrypt(password.encode("utf-8"),salt=salt,
                    n=16384,r=8,p=1,dklen=64,maxmem=64*1024*1024)
 return "scrypt$16384$8$1$"+b64url(salt)+"$"+b64url(raw)
def main():
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument("--root",type=Path,default=Path("/etc/hi5central/managed"))
 parser.add_argument("--dry-run",action="store_true")
 parser.add_argument("--apply",action="store_true")
 args=parser.parse_args()
 require(args.dry_run != args.apply,"Choose exactly --dry-run or --apply.")
 root=args.root
 require(root.is_dir() and not root.is_symlink() and stat.S_IMODE(root.stat().st_mode)==0o700,
         "Managed private secret directory is missing or unsafe.")
 state=root/"setup-state.json"
 password_path=root/"platform-owner-password"
 for path in (state,password_path):
  require(path.is_file() and not path.is_symlink()
          and stat.S_IMODE(path.stat().st_mode)==0o600,"Required private owner setup file unavailable.")
 details=json.loads(state.read_text(encoding="utf-8"))
 require(details.get("format")=="hi5-managed-secrets-v1","Invalid managed setup state.")
 require(details.get("phase")=="secrets-prepared-only","Owner bootstrap only available in fresh setup phase.")
 require(details.get("fresh_tenants_created")==0,"Unexpected tenant state.")
 email=str(details.get("pgadmin_email","")).lower().strip()
 require(bool(EMAIL.fullmatch(email)),"Validated global admin email required.")
 password=password_path.read_text(encoding="ascii").strip()
 require(len(password)>=50,"Generated owner password is too short.")
 if args.dry_run:
  print("PASS: private global owner credentials and fresh setup state verified.")
  print("Would create a global admin user with owner role; ZERO tenants created.")
  print("No Docker/database changes or password disclosure.")
  return
 require(os.geteuid()==0,"Root required to initialise database owner.")
 container=json.loads(subprocess.check_output(["docker","inspect",CONTAINER],text=True))[0]
 labels=container.get("Config",{}).get("Labels") or {}
 require(labels.get("com.docker.compose.project")=="hi5central-managed" and
         labels.get("com.docker.compose.service")=="postgres",
         "Refused: PostgreSQL does not belong to fresh managed Compose project.")
 require(not any(x for x in (container.get("NetworkSettings",{}).get("Ports") or {}).values()),
         "Refused: PostgreSQL has published host ports.")
 # The plaintext owner password is NEVER passed in environment, argv or SQL.
 phash=encoded_password(password)
 sql="""
\\set ON_ERROR_STOP on
BEGIN;
SET LOCAL lock_timeout='15s';
SET LOCAL statement_timeout='45s';
DO $h5bootstrap$
BEGIN
 IF to_regclass('public.schema_migrations') IS NULL
    OR to_regclass('public.platform_admin_members') IS NULL
    OR to_regclass('public.platform_admin_audit_events') IS NULL
    OR to_regclass('public.users') IS NULL
    OR to_regclass('public.tenants') IS NULL
    OR to_regclass('public.platform_release_rollout_control') IS NULL
 THEN RAISE EXCEPTION 'Reviewed full Platform schema not installed'; END IF;
 IF NOT EXISTS (
   SELECT 1 FROM public.schema_migrations
   WHERE version='082_platform_admin_control_plane.sql'
 ) THEN RAISE EXCEPTION 'Platform Admin migration not applied'; END IF;
 IF EXISTS(SELECT 1 FROM public.tenants)
    OR EXISTS(SELECT 1 FROM public.users)
    OR EXISTS(SELECT 1 FROM public.platform_admin_members)
    OR EXISTS(SELECT 1 FROM public.tenant_release_rollout_jobs)
    OR (SELECT paused FROM public.platform_release_rollout_control WHERE singleton=true)
       IS DISTINCT FROM TRUE
 THEN RAISE EXCEPTION 'Owner bootstrap only permitted in empty, globally paused platform'; END IF;
END $h5bootstrap$;
WITH created AS (
 INSERT INTO public.users(email,name,password_hash,email_verified_at)
 VALUES ("""+q(email)+", 'Hi5Central Owner', "+q(phash)+""", now())
 RETURNING id
), member AS (
 INSERT INTO public.platform_admin_members(user_id,role,status)
 SELECT id,'owner','active' FROM created RETURNING user_id
)
INSERT INTO public.platform_admin_audit_events
 (actor_user_id,action,target_type,metadata)
SELECT user_id,'platform.bootstrap.owner','global_admin',
 '{"source":"ionos_clean_managed_bootstrap","tenant_count":0,"manual_root_setup":true}'::jsonb
FROM member;
COMMIT;
"""
 process=subprocess.run(
  ["docker","exec","-i",CONTAINER,"sh","-c",
   'exec psql -X -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"'],
  input=sql,text=True,capture_output=True,timeout=65,
 )
 require(process.returncode==0,
         "Global Admin bootstrap refused or failed transaction; inspect reviewed schema/empty-DB guards.")
 print("PASS: one independent global Platform Owner created; ZERO customer tenants.")
 print("Owner email:",email)
 print("Credential remains private in "+str(password_path)+" (not displayed).")
 print("MFA enrollment and verified Admin login remain separate acceptance checks.")
if __name__=="__main__":
 try:main()
 except (RuntimeError,OSError,ValueError,json.JSONDecodeError,
         subprocess.TimeoutExpired,subprocess.CalledProcessError) as e:
  print("BLOCKED: "+str(e),file=sys.stderr)
  sys.exit(3)
