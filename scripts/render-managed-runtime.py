#!/usr/bin/env python3
"""Produce an immutable private Compose env from generated NEW secrets and a
validated pinned-image manifest. No Docker, network or SQL side effects.
"""
import argparse
import json
import os
from pathlib import Path
import stat
import sys
import tempfile
from importlib.machinery import SourceFileLoader
from importlib.util import spec_from_loader,module_from_spec

SOURCE=Path(__file__).with_name("validate-managed-image-manifest.py")
loader=SourceFileLoader("managed_manifest_validator",str(SOURCE))
spec=spec_from_loader(loader.name,loader)
validator=module_from_spec(spec)
loader.exec_module(validator)

def reject(msg):raise ValueError(msg)
def parse_env(path):
 if not path.is_file() or path.is_symlink() or stat.S_IMODE(path.stat().st_mode)!=0o600:
  reject("Generated managed.env must be a regular private 0600 file.")
 env={}
 for line in path.read_text(encoding="utf-8").splitlines():
  if not line or line.lstrip().startswith("#"):continue
  if "=" not in line:reject("Invalid generated environment entry.")
  key,value=line.split("=",1)
  if not key.isidentifier() or key in env:reject("Unsafe or duplicate env key.")
  if any(x in value for x in "\x00\r\n$"):reject("Unsafe env expansion or multiline value.")
  env[key]=value
 return env

def render(env,manifest):
 validator.validate(manifest)
 if env.get("COMPOSE_PROJECT_NAME")!="hi5central-managed":
  reject("Expected dedicated managed Compose project.")
 if env.get("DEPLOYMENT_MODE")!="managed" or env.get("TENANCY_MODE")!="multi":
  reject("Managed multitenant configuration required.")
 if env.get("PRIMARY_TENANT_SLUG") or env.get("MANAGED_TENANT_SLUGS"):
  reject("A clean restore cannot preseed tenants.")
 if env.get("RELEASE_ROLLOUT_PAUSED")!="true":
  reject("Generic rollout must be paused.")
 domain=env.get("ROOT_DOMAIN","")
 if domain.count(".")<1 or not env.get("POSTGRES_PASSWORD") or not env.get("TURN_SHARED_SECRET"):
  reject("Domain or generated secrets absent.")
 out=dict(env)
 for key,image in manifest["images"].items():
  out["HI5_IMAGE_"+key.upper()]=image
 out["HI5_PGADMIN_IMAGE"]=manifest["images"]["pgadmin"]
 out["MARKETING_ADDRESS"]=domain
 out["HI5_NATIVE_DOWNLOAD_ROOT"]="/var/lib/hi5central/native-downloads"
 out["COMPOSE_PROFILES"]="itsm,rmm,admin,database-browser"
 out["TURN_SERVICE_PROFILE"]="rmm"
 out["HI5_PLATFORM_GIT_SHA"]=manifest["platform_git_sha"]
 out["BACKGROUND_WORKERS_ENABLED"]="false"
 out["RELEASE_ROLLOUT_PAUSED"]="true"
 out["PRIMARY_TENANT_SLUG"]=""
 out["MANAGED_TENANT_SLUGS"]=""
 for key,value in out.items():
  if not key.isidentifier() or any(c in value for c in "\x00\r\n$"):
   reject("Invalid rendered environment property "+key)
 return out

def serialize(env):
 return "".join(key+"="+value+"\n" for key,value in sorted(env.items()))

def main():
 parser=argparse.ArgumentParser()
 parser.add_argument("--root",type=Path,default=Path("/etc/hi5central/managed"))
 parser.add_argument("--manifest",type=Path,required=True)
 parser.add_argument("--dry-run",action="store_true")
 parser.add_argument("--apply",action="store_true")
 a=parser.parse_args()
 if a.dry_run==a.apply:reject("Choose exactly --dry-run or --apply.")
 root=a.root
 if not root.is_dir() or root.is_symlink() or stat.S_IMODE(root.stat().st_mode)!=0o700:
  reject("Private 0700 generated secret directory unavailable.")
 if not a.manifest.is_file() or a.manifest.is_symlink():
  reject("Approved image manifest must be an ordinary file.")
 manifest=json.loads(a.manifest.read_text(encoding="utf-8"))
 source=parse_env(root/"managed.env")
 output=serialize(render(source,manifest))
 dest=root/"managed-runtime.env"
 if dest.is_symlink():reject("Runtime env cannot be a symlink.")
 if dest.exists():
  if dest.read_text(encoding="utf-8")!=output or stat.S_IMODE(dest.stat().st_mode)!=0o600:
   reject("Existing runtime env differs or has unsafe permissions. Refusing overwrite.")
  print("PASS: existing private runtime matches approved image manifest.")
  return
 if a.dry_run:
  print("PASS: would generate pinned 15-image runtime env; no changes or credentials printed.")
  return
 if os.geteuid()!=0:reject("Root required to write private runtime configuration.")
 os.umask(0o077)
 with tempfile.NamedTemporaryFile(mode="w",encoding="utf-8",dir=root,
                                  prefix=".managed-runtime-",delete=False) as tmp:
  os.fchmod(tmp.fileno(),0o600)
  tmp.write(output)
  tmp.flush()
  os.fsync(tmp.fileno())
  pending=Path(tmp.name)
 try:
  if dest.exists():reject("Runtime config already exists.")
  os.link(pending,dest)
 finally:
  pending.unlink(missing_ok=True)
 print("PASS: private pinned Compose configuration prepared at "+str(dest))
 print("No tenant, Docker service, database migration or release worker started.")
if __name__=="__main__":
 try:main()
 except (ValueError,OSError,KeyError,json.JSONDecodeError) as e:
  print("BLOCKED: "+str(e),file=sys.stderr)
  sys.exit(3)
