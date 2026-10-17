#!/usr/bin/env python3
"""Stage an APPROVED complete set of Windows/Linux/macOS agents and viewers,
mobile viewer and Avalonia self-service downloads on a FRESH managed host.

The source is a private offline directory of independently built packages.
No binary is downloaded or built by this script. Every file must match the
approved immutable SHA256, byte size, safe basename and source commit.
An entire validated release is atomically published, never partially.
No customer tenant, database, Docker, Caddy or service is modified.

Input layout: SOURCE_DIR/<artifact key>/<approved filename>
Output: DEST/releases/<manifest_sha256>/<artifact key>/<approved filename>
        DEST/latest.json  (atomic snapshot pointer for managed download service)
Default DEST is /var/lib/hi5central/native-downloads; bind read-only to Caddy.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import sys
import tempfile
from importlib.machinery import SourceFileLoader
from importlib.util import spec_from_loader,module_from_spec

SRC=Path(__file__).with_name("validate-managed-image-manifest.py")
loader=SourceFileLoader("hi5_native_manifest",str(SRC))
spec=spec_from_loader(loader.name,loader)
validator=module_from_spec(spec)
loader.exec_module(validator)
DEST=Path("/var/lib/hi5central/native-downloads")

def require(ok,msg):
 if not ok:raise RuntimeError(msg)
def hashfile(p):
 h=hashlib.sha256()
 with p.open("rb") as f:
  for chunk in iter(lambda:f.read(1024*1024),b""):
   h.update(chunk)
 return h.hexdigest()
def files(manifest,source):
 seen=set()
 rows=[]
 require(source.is_dir() and not source.is_symlink(),"Native source directory missing or symbolic link.")
 for key in validator.NATIVE_NAMES:
  data=manifest["native_artifacts"][key]
  target=source/key
  p=target/data["filename"]
  require(target.is_dir() and not target.is_symlink(),"Native asset group missing/unsafe: "+key)
  require(p.is_file() and not p.is_symlink(),"Expected native package missing: "+key)
  require(p.stat().st_size==data["size_bytes"],"Native package byte length differs: "+key)
  require(hashfile(p)==data["sha256"],"Native package SHA256 differs: "+key)
  require((key,data["filename"]) not in seen,"Duplicate native output")
  seen.add((key,data["filename"]))
  rows.append((key,p,data))
 return rows
def release_metadata(manifest,sha):
 return {
  "schema":"hi5central-native-downloads-v1",
  "platform_git_sha":manifest["platform_git_sha"],
  "release_manifest_sha256":sha,
  "agent_viewer_versions_are_managed_centrally":True,
  "artifacts":{
   key:{
    "path":"releases/"+sha+"/"+key+"/"+data["filename"],
    "sha256":data["sha256"],
    "size_bytes":data["size_bytes"],
    "source_git_sha":data["source_git_sha"]
   } for key,data in ((k,d) for k,d in manifest["native_artifacts"].items())
  }
 }
def stage(manifest_bytes,manifest,source,dest,dry_run):
 validator.validate(manifest)
 rows=files(manifest,source)
 sha=hashlib.sha256(manifest_bytes).hexdigest()
 output=release_metadata(manifest,sha)
 require(dest.is_absolute(),"Download root must be absolute.")
 require(not dest.is_symlink(),"Downloads root may not be a symlink.")
 if dest.exists():
  require(dest.is_dir(),"Downloads destination must be a directory.")
  existing=dest/"latest.json"
  if existing.exists():
   require(existing.is_file() and not existing.is_symlink(),
           "Existing native release marker unsafe.")
   require(existing.read_bytes()==(json.dumps(output,sort_keys=True,indent=2)+"\n").encode(),
           "Different native release already active. Use a separately audited later-release publisher.")
   for key,p,data in rows:
    delivered=dest/output["artifacts"][key]["path"]
    require(delivered.is_file() and not delivered.is_symlink() and
            hashfile(delivered)==data["sha256"],
            "Previously staged binary is missing or modified: "+key)
   print("PASS: existing approved native release matches all files; no changes.")
   return output
 if dry_run:
  print("PASS: 8 approved native assets verified (name, size, SHA256 and source SHA).")
  print("DRY-RUN: no files written or services changed.")
  return output
 require(os.geteuid()==0,"Native staging requires root.")
 os.umask(0o022)
 dest.mkdir(parents=True,exist_ok=True,mode=0o755)
 releases=dest/"releases"
 require(not releases.is_symlink(),"Releases path cannot be a symlink.")
 releases.mkdir(exist_ok=True,mode=0o755)
 final=releases/sha
 require(not final.exists(),"Unexpected incomplete native release with same digest; manual review required.")
 # Temporary content is private until ALL copies are verified.
 temp=Path(tempfile.mkdtemp(prefix=".pending-native-",dir=releases))
 try:
  for key,p,data in rows:
   sub=temp/key
   sub.mkdir(mode=0o755)
   target=sub/data["filename"]
   with p.open("rb") as inp, target.open("xb") as out:
    shutil.copyfileobj(inp,out,1024*1024)
   require(target.stat().st_size==data["size_bytes"] and
           hashfile(target)==data["sha256"],"Native asset changed during copy: "+key)
   target.chmod(0o644)
  temp.chmod(0o755)
  os.replace(temp,final)
 except Exception:
  shutil.rmtree(temp,ignore_errors=True)
  raise
 data=(json.dumps(output,sort_keys=True,indent=2)+"\n").encode()
 with tempfile.NamedTemporaryFile(mode="wb",dir=dest,prefix=".pending-latest-",
                                  delete=False) as file:
  os.fchmod(file.fileno(),0o644)
  file.write(data)
  file.flush()
  os.fsync(file.fileno())
  marker=Path(file.name)
 try:
  require(not (dest/"latest.json").exists(),"Latest pointer appeared during publish; refuse race.")
  os.link(marker,dest/"latest.json")
 finally:
  marker.unlink(missing_ok=True)
 print("PASS: all 8 native assets atomically published for private managed Caddy bind.")
 print("Release digest:",sha)
 print("No tenant, Docker image or database objects changed.")
 return output

def main():
 p=argparse.ArgumentParser()
 p.add_argument("--manifest",type=Path,required=True)
 p.add_argument("--source-dir",type=Path,required=True)
 p.add_argument("--destination",type=Path,default=DEST)
 p.add_argument("--dry-run",action="store_true")
 p.add_argument("--apply",action="store_true")
 args=p.parse_args()
 require(args.dry_run!=args.apply,"Choose exactly --dry-run or --apply.")
 require(args.manifest.is_file() and not args.manifest.is_symlink(),
         "Reviewed restore manifest missing/unsafe.")
 raw=args.manifest.read_bytes()
 require(len(raw)<=128*1024,"Manifest too large.")
 manifest=json.loads(raw)
 stage(raw,manifest,args.source_dir,args.destination,args.dry_run)
if __name__=="__main__":
 try:main()
 except (RuntimeError,ValueError,OSError,KeyError,json.JSONDecodeError) as err:
  print("BLOCKED: "+str(err),file=sys.stderr)
  sys.exit(3)
