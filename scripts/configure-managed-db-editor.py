#!/usr/bin/env python3
"""Provision private, full-table DML pgAdmin account in a NEW managed DB.

Not the PostgreSQL cluster superuser, not the API login. Works only with
hi5central-managed Compose PostgreSQL, new empty tenants and paused rollout.
Keep password in root-only credential file; it is not printed or placed in argv.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

NAME="hi5_pgadmin_editor"
CONTAINER="hi5central-managed-postgres-1"
def fail(s):raise RuntimeError(s)

def main():
 parser=argparse.ArgumentParser()
 parser.add_argument("--root",type=Path,default=Path("/etc/hi5central/managed"))
 parser.add_argument("--dry-run",action="store_true")
 parser.add_argument("--apply",action="store_true")
 args=parser.parse_args()
 if args.dry_run==args.apply:fail("Choose exactly one of --dry-run or --apply.")
 secret=args.root/"pgadmin-editor-password"
 if not secret.is_file() or secret.is_symlink() or secret.stat().st_mode & 0o077:
  fail("Dedicated private database editor password is not available.")
 password=secret.read_text(encoding="ascii").strip()
 if len(password)<50 or not all(ch in "0123456789abcdef" for ch in password):
  fail("Invalid generated password shape.")
 if args.dry_run:
  print("DRY RUN: would create or update non-superuser database editor role.")
  print("Would grant CRUD across existing/future public tables and sequences.")
  print("Would grant CREATE in public schema; PostgreSQL object ownership still applies to DDL.")
  print("No database access or credentials displayed.")
  return
 if os.geteuid()!=0:fail("Run as root on the fresh installed VPS.")
 c=json.loads(subprocess.check_output(["docker","inspect",CONTAINER],text=True))[0]
 labels=c.get("Config",{}).get("Labels") or {}
 if labels.get("com.docker.compose.project")!="hi5central-managed" or labels.get("com.docker.compose.service")!="postgres":
  fail("Database is not the new verified managed Compose project.")
 if any(v for v in (c.get("NetworkSettings",{}).get("Ports") or {}).values()):
  fail("PostgreSQL unexpectedly published to the host.")
 # Hexadecimal password cannot interpolate SQL characters.
 sql=r"""
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL statement_timeout='30s';
DO $h5$
BEGIN
 IF (SELECT count(*) FROM public.tenants)>0
 OR (SELECT paused FROM public.platform_release_rollout_control WHERE singleton=true) IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'Not a paused zero-tenant installation'; END IF;
END $h5$;
DO $h5$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='hi5_pgadmin_editor') THEN
  CREATE ROLE hi5_pgadmin_editor LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
     NOINHERIT NOREPLICATION NOBYPASSRLS;
 END IF;
END $h5$;
ALTER ROLE hi5_pgadmin_editor WITH LOGIN NOSUPERUSER NOCREATEDB
 NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS PASSWORD '"""+password+r"""';
GRANT CONNECT,TEMPORARY ON DATABASE hi5central TO hi5_pgadmin_editor;
GRANT USAGE,CREATE ON SCHEMA public TO hi5_pgadmin_editor;
GRANT SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER
 ON ALL TABLES IN SCHEMA public TO hi5_pgadmin_editor;
GRANT USAGE,SELECT,UPDATE ON ALL SEQUENCES IN SCHEMA public TO hi5_pgadmin_editor;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
 GRANT SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER
 ON TABLES TO hi5_pgadmin_editor;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
 GRANT USAGE,SELECT,UPDATE ON SEQUENCES TO hi5_pgadmin_editor;
DO $h5$
BEGIN
 IF (SELECT rolsuper OR rolbypassrls OR rolcreaterole OR rolcreatedb
     FROM pg_roles WHERE rolname='hi5_pgadmin_editor') IS DISTINCT FROM false
 THEN RAISE EXCEPTION 'Database editor role has prohibited superuser powers'; END IF;
END $h5$;
COMMIT;
"""
 res=subprocess.run(
  ["docker","exec","-i",CONTAINER,"sh","-c",
   'exec psql -X -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"'],
  input=sql,text=True,capture_output=True)
 if res.returncode!=0:
  fail("Dedicated editor role transaction rejected; zero changes committed.")
 print("PASS: private PostgreSQL editor login is provisioned in the new managed database.")
 print("Privileges include app-table insert/update/delete and new-schema-object CREATE.")
 print("Protected RLS policies and unrelated DB object ownership remain enforced.")
 print("Use this role in loopback-only pgAdmin; never use it for unattended app workers.")
if __name__=="__main__":
 try:main()
 except (RuntimeError,OSError,subprocess.CalledProcessError) as e:
  print("BLOCKED: "+str(e),file=sys.stderr);sys.exit(1)
