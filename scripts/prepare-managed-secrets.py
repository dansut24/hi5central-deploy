#!/usr/bin/env python3
"""Generate fresh Hi5Central-owned credentials for a NEW IONOS VPS.

This is a secrets/configuration phase, NOT a working application installer.
It NEVER uses existing Production credentials and NEVER changes Docker or DB.
It refuses to overwrite an existing configuration. All secrets stay root-only.
"""
import argparse
from datetime import datetime,timezone
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import stat
import subprocess
import sys

LABELS={
 "POSTGRES_PASSWORD":48,
 "REDIS_PASSWORD":48,
 "MFA_ENCRYPTION_KEY":32,
 "RMM_RECOVERY_KEY_ENCRYPTION_KEY":32,
 "CONNECT_CODE_HMAC_KEY":32,
 "TENANT_INSTALLER_HMAC_KEY":32,
 "TURN_SHARED_SECRET":32,
 "INITIAL_SETUP_TOKEN":48,
 "RELEASE_OPERATOR_TOKEN":48,
 "HI5_PGADMIN_EDITOR_PASSWORD":48,
 "HI5_PGADMIN_PASSWORD":48,
 "APP_SESSION_SIGNING_KEY":32,
 "HI5_WEBHOOK_HMAC_KEY":32,
}
FILES=("managed.env","pgadmin-password","pgadmin-editor-password",
       "internal-release-signing.key","internal-release-signing.pub","setup-state.json")
DOMAIN=re.compile(r"^(?=.{4,253}$)[a-z0-9](?:[a-z0-9.-]*[a-z0-9])$")
EMAIL=re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
def fail(msg):
 raise RuntimeError(msg)
def safe_dir(path):
 if not path.is_absolute() or str(path) in ("/","/etc","/root","/opt","/var"):
  fail("Use a dedicated absolute secret directory, e.g. /etc/hi5central/managed")
 # Avoid following symlinked final directories.
 if path.is_symlink():
  fail("Target secret directory cannot be a symlink")
def write_file(p,data):
 with p.open("x",encoding="utf-8") as f:
  os.fchmod(f.fileno(),0o600)
  f.write(data)
def manifest(directory,domain,email):
 return {
  "format":"hi5-managed-secrets-v1",
  "installed_utc":datetime.now(timezone.utc).isoformat(),
  "root_domain":domain,"pgadmin_email":email,
  "phase":"secrets-prepared-only",
  "production_data_imported":False,
  "production_database_changed":False,
  "fresh_tenants_created":0,
  "required_next_steps":[
   "review images by immutable digest and secure container registry",
   "install application compose and distinct non-superuser runtime identities",
   "apply exact approved migrations to a new empty database",
   "verify full-edit private pgAdmin with controlled DB admin login",
   "validate and import preserved global software catalogue seed",
   "install Caddy, marketing/signup, API, ITSM/Portal, RMM/Control, TURN",
   "install audited release workers and fenced host dispatcher",
   "verify all mandatory routes and backup/restore; optional external integrations may be skipped",
  ],
  "optional_integrations":{
   "smtp":"NOT_CONFIGURED","stripe":"NOT_CONFIGURED",
   "qualification_windows_agent":"NOT_CONFIGURED",
   "public_dns_and_tls":"NOT_VERIFIED",
   "external_turn_connectivity":"NOT_VERIFIED",
   "native_agent_code_signing":"NOT_CONFIGURED",
  },
 }
def verify(root):
 safe_dir(root)
 if not root.is_dir(): fail("Configuration directory does not exist")
 if stat.S_IMODE(root.stat().st_mode)!=0o700:
  fail("Secret directory permissions must be 0700")
 for name in FILES:
  path=root/name
  if not path.is_file() or path.is_symlink() or stat.S_IMODE(path.stat().st_mode)!=0o600:
   fail("Missing, unsafe or non-private credential file: "+name)
 content=(root/"managed.env").read_text()
 for key in [*LABELS,"HI5_PGADMIN_EMAIL","HI5_PGADMIN_IMAGE",
             "HI5_PGADMIN_PASSWORD_FILE","HI5_PGADMIN_EDITOR_PASSWORD_FILE"]:
  if not any(line.startswith(key+"=") for line in content.splitlines()):
   fail("Missing configuration key: "+key)
 state=json.loads((root/"setup-state.json").read_text())
 if state.get("phase")!="secrets-prepared-only":
  fail("Unknown setup phase; do not silently regenerate credentials.")
 if "CHANGE_ME" in content or ":latest" in content:
  fail("Placeholder or unpinned images detected.")
 print("PASS: Root-only managed secrets and config are present; no passwords printed.")
 print("STATUS: Secrets prepared. Platform installation NOT completed.")
def main():
 p=argparse.ArgumentParser()
 p.add_argument("--root",type=Path,default=Path("/etc/hi5central/managed"))
 p.add_argument("--root-domain",default="hi5central.com")
 p.add_argument("--admin-email",default="")
 p.add_argument("--dry-run",action="store_true")
 p.add_argument("--verify",action="store_true")
 args=p.parse_args()
 root=args.root
 safe_dir(root)
 if args.verify:
  verify(root);return
 if not DOMAIN.fullmatch(args.root_domain) or ".." in args.root_domain:
  fail("Invalid root DNS name")
 if not EMAIL.fullmatch(args.admin_email) or "\n" in args.admin_email:
  fail("--admin-email must be the intended administrator's email")
 if root.exists() and (not root.is_dir() or any(root.iterdir())):
  fail("Existing configuration directory is not empty. Never overwrite secrets.")
 if args.dry_run:
  print("DRY RUN: would generate credentials and private Ed25519 release signing key")
  print("Root directory:",root)
  print("No writes, no tenant creation, no VPS wipe, no Docker or database changes.")
  return
 if os.geteuid()!=0:
  fail("Run as root so generated credentials cannot be read by other users.")
 if not shutil.which("openssl"):
  fail("openssl is required for internally generated Ed25519 release signing keys")
 os.umask(0o077)
 root.mkdir(parents=True,exist_ok=True,mode=0o700)
 os.chmod(root,0o700)
 # Save the critical persistent secrets first. No provider-issued API keys
 # or commercial Windows/macOS signing certificates are fabricated.
 values={key:secrets.token_hex(n) for key,n in LABELS.items()}
 signing_key=root/"internal-release-signing.key"
 pub=root/"internal-release-signing.pub"
 try:
  subprocess.run(["openssl","genpkey","-algorithm","Ed25519","-out",str(signing_key)],
                 check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
  os.chmod(signing_key,0o600)
  with pub.open("x") as output:
   os.fchmod(output.fileno(),0o600)
   subprocess.run(["openssl","pkey","-in",str(signing_key),"-pubout"],
                  check=True,stdout=output,stderr=subprocess.DEVNULL)
  write_file(root/"pgadmin-password",values["HI5_PGADMIN_PASSWORD"]+"\n")
  write_file(root/"pgadmin-editor-password",values["HI5_PGADMIN_EDITOR_PASSWORD"]+"\n")
  env={
   "COMPOSE_PROJECT_NAME":"hi5central-managed",
   "COMPOSE_PROFILES":"itsm,rmm,admin,database-browser",
   "DEPLOYMENT_MODE":"managed",
   "TENANCY_MODE":"multi",
   "RUNTIME_ENVIRONMENT":"live",
   "FEATURE_MODE":"controlled",
   "ROOT_DOMAIN":args.root_domain,
   "PRIMARY_TENANT_SLUG":"", # explicit ZERO-tenant new platform
   "MANAGED_TENANT_SLUGS":"",
   "BACKGROUND_WORKERS_ENABLED":"false",
   "POSTGRES_DB":"hi5central",
   "POSTGRES_USER":"hi5central",
   "HI5_PGADMIN_EMAIL":args.admin_email,
   "HI5_PGADMIN_PASSWORD_FILE":str(root/"pgadmin-password"),
   "HI5_PGADMIN_EDITOR_PASSWORD_FILE":str(root/"pgadmin-editor-password"),
   "HI5_PGADMIN_LOCAL_PORT":"5050",
   "HI5_PGADMIN_IMAGE":"", # immutable approved digest supplied by image manifest
   "HI5_INTERNAL_RELEASE_SIGNING_PRIVATE_KEY_FILE":str(signing_key),
   "HI5_INTERNAL_RELEASE_SIGNING_PUBLIC_KEY_FILE":str(pub),
   "RELEASE_ROLLOUT_PAUSED":"true",
   "APP_URL":"https://"+args.root_domain,
   "MARKETING_URL":"https://"+args.root_domain,
   "PORTAL_URL":"https://"+args.root_domain+"/portal",
   "API_URL":"https://api."+args.root_domain,
   "ADMIN_URL":"https://admin."+args.root_domain,
   "RMM_URL":"https://rmm."+args.root_domain,
   "DOWNLOADS_URL":"https://downloads."+args.root_domain,
   "COOKIE_DOMAIN":"."+args.root_domain,
   "ITSM_ADDRESS":args.root_domain,
   "RMM_ADDRESS":"rmm."+args.root_domain,
   "ADMIN_ADDRESS":"admin."+args.root_domain,
   "API_ADDRESS":"api."+args.root_domain,
   "DOWNLOADS_ADDRESS":"downloads."+args.root_domain,
   "ACME_EMAIL":args.admin_email,
   "TURN_HOST":"turn."+args.root_domain,
   "TURN_URL":"turn:turn."+args.root_domain+":3478",
   "TURN_REALM":args.root_domain,
   "TURN_EXTERNAL_IP":"",
   "SMTP_HOST":"",
   "SMTP_PORT":"587",
   "SMTP_USER":"",
   "SMTP_PASSWORD":"",
   "SMTP_FROM":"",
   "STRIPE_SECRET_KEY":"",
   "STRIPE_WEBHOOK_SECRET":"",
   "MICROSOFT_CLIENT_ID":"",
   "MICROSOFT_CLIENT_SECRET":"",
   "MICROSOFT_REDIRECT_URI":"",
  }
  env.update(values)
  lines=["# Generated; contains secrets. Do not commit. chmod 600.",
         "# This is secrets PREPARATION, not evidence services have started."]
  for k,v in env.items():
   # Each generated field is a single line and must never include shell syntax.
   if any(ch in str(v) for ch in "\r\n"): fail("Unsafe multiline env content")
   lines.append(k+"="+str(v))
  write_file(root/"managed.env","\n".join(lines)+"\n")
  write_file(root/"setup-state.json",json.dumps(manifest(root,args.root_domain,args.admin_email),
                                                 indent=2)+"\n")
  verify(root)
 except Exception:
  # Do not leave partial credentials around and accidentally treat them as ready;
  # require explicit human cleanup if preparation ever fails.
  print("BLOCKED: preparation incomplete. Do not use partial credentials in "+str(root),
        file=sys.stderr)
  raise
 print("Created new, independent Hi5Central credentials in "+str(root))
 print("IMPORTANT: copy securely to offline encrypted recovery storage.")
 print("SMTP/Stripe/code-signing are NOT CONFIGURED. Do not use this alone as an installer.")
if __name__=="__main__":
 try:main()
 except (RuntimeError,OSError,subprocess.CalledProcessError,ValueError) as exc:
  print("BLOCKED: "+str(exc),file=sys.stderr)
  sys.exit(1)
