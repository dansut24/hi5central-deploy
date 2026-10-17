#!/usr/bin/env python3
"""Single read-only preflight for Hi5Central clean IONOS restore inputs.

Checks exact pinned runtime declaration, all verified local native packages,
global-only catalogue SQL import compatibility and protected recovery archive.
NEVER contacts Docker, AWS, DNS or the VPS; never creates users/tenants.
It cannot independently verify offsite storage or actual container startup.
"""
import argparse
import hashlib
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec,spec_from_loader
import json
from pathlib import Path
import re
import sys
import tarfile
import tempfile

HERE=Path(__file__).resolve().parent
def load(name,path):
 loader=SourceFileLoader(name,str(HERE/path))
 spec=spec_from_loader(name,loader)
 module=module_from_spec(spec)
 loader.exec_module(module)
 return module
manifest_mod=load("restore_manifest","validate-managed-image-manifest.py")
catalogue_mod=load("restore_catalogue","import-global-software-catalogue.py")
native_mod=load("restore_native","stage-managed-native-artifacts.py")

def require(test,message):
 if not test:raise ValueError(message)
def sha256(data):
 return hashlib.sha256(data).hexdigest()
def validate_bundle(bundle,seed):
 require(bundle.is_file() and not bundle.is_symlink(),
         "Protected recovery bundle missing or unsafe.")
 require(bundle.stat().st_size <= 1024*1024*1024,
         "Recovery bundle exceeds 1 GiB review limit.")
 expected={
   "hi5central-global-software-20261017.pgdump",
   "global-software-seed-20261017T145713Z.tar.gz",
   "production-schema-20261017.pgdump",
   "SHA256SUMS.txt"
 }
 with tarfile.open(bundle,"r:gz") as tar:
  members={v.name:v for v in tar.getmembers()}
  require(set(members)==expected,"Recovery bundle must contain exact approved component list.")
  require(all(v.isfile() and 0 < v.size <= 1024*1024*1024
              for v in members.values()),"Unsafe recovery bundle member.")
  raw=tar.extractfile("SHA256SUMS.txt").read()
  require(len(raw)<2000,"Checksum manifest too large.")
  checks={}
  for line in raw.decode("ascii").splitlines():
   m=re.fullmatch(r"([0-9a-f]{64})  ([A-Za-z0-9._-]+)",line)
   require(m is not None,"Malformed SHA256SUMS entry.")
   require(m.group(2) not in checks,"Duplicate checksum entry.")
   checks[m.group(2)]=m.group(1)
  require(set(checks)==expected-{"SHA256SUMS.txt"},
          "Recovery checksum manifest incomplete/incorrect.")
  for name in checks:
   h=hashlib.sha256()
   with tar.extractfile(name) as source:
    for chunk in iter(lambda:source.read(1024*1024),b""):
     h.update(chunk)
   require(h.hexdigest()==checks[name],"Recovery SHA256 mismatch: "+name)
  seed_sha=sha256(seed.read_bytes())
  require(seed_sha==checks["global-software-seed-20261017T145713Z.tar.gz"],
          "Provided catalogue archive not identical to protected recovery bundle.")
 return checks

def run(args):
 for item in (args.manifest,args.catalogue):
  require(item.is_file() and not item.is_symlink(),
          "Required ordinary restore input unavailable.")
 require(args.manifest.stat().st_size <= 128*1024,
         "Image manifest exceeds 128 KiB.")
 manifest=json.loads(args.manifest.read_text(encoding="utf-8"))
 reviewed=manifest_mod.validate(manifest)
 counts,_=catalogue_mod.payload(args.catalogue)
 native_mod.files(manifest,args.native_source_dir)
 checks=validate_bundle(args.recovery_bundle,args.catalogue)
 print("PASS: reviewed pinned manifest: "+str(reviewed["images"])+
       " images; "+str(reviewed["native_artifacts"])+" native assets verified.")
 print("PASS: verified global-only catalogue: "+json.dumps(counts,sort_keys=True))
 print("PASS: all protected recovery bundle files match SHA256SUMS.")
 print("PASS: recovery catalogue matches the exact requested import archive.")
 print("STATUS: local restore inputs validated; NO Docker, DB or network writes.")
 print("RESET NOT READY: still requires proven offsite private-key recovery,")
 print("complete approved worker/Hi5Dev/marketing images and clean-host runtime startup.")
def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument("--manifest",required=True,type=Path)
 p.add_argument("--catalogue",required=True,type=Path)
 p.add_argument("--native-source-dir",required=True,type=Path)
 p.add_argument("--recovery-bundle",required=True,type=Path)
 args=p.parse_args()
 run(args)
if __name__=="__main__":
 try:main()
 except (OSError,ValueError,KeyError,RuntimeError,tarfile.TarError,
         UnicodeError,json.JSONDecodeError) as e:
  print("BLOCKED: "+str(e),file=sys.stderr)
  sys.exit(3)
