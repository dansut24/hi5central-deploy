#!/usr/bin/env python3
"""Dry-run first. Deletes ONLY four explicitly identified isolated PG rehearshal
containers and their exclusive data volumes when --apply AND an exact
operator confirmation are both supplied. Never touches Production or QA pools.
"""
import argparse
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

BACKUP=Path("/var/backups/hi5central/release-activation/pre-generic-final-20261017T110313Z.dump")
EXPECTED_SHA="7a76e3bc176c2b4858bb6f151e7d4bce37246138bb1b45f81a38ed5f3c281a94"
PAIRS=[
 ("hi5central-migration155-e77bb81c27","hi5central-migration155-data-e77bb81c27","2026-10-17T10:21:12."),
 ("hi5central-migration156-6e187ad56404","hi5central-migration156-data-6e187ad56404","2026-10-17T10:26:06."),
 ("hi5central-migration157-c6eadb3b6a42","hi5central-migration157-data-c6eadb3b6a42","2026-10-17T10:29:18."),
 ("hi5central-restore-check-77968d7fa245","hi5central-restore-data-77968d7fa245","2026-10-17T10:12:39."),
]
def docker(*args):
 return subprocess.check_output(["docker",*args],text=True,stderr=subprocess.DEVNULL).strip()
def require(cond,what):
 if not cond: raise RuntimeError("REFUSED: "+what)
def check_one(name,vol,created):
 c=json.loads(docker("inspect",name))[0]
 require(c.get("Name")=="/"+name,"container name changed: "+name)
 require(c.get("Created","").startswith(created),"created date changed: "+name)
 require(c.get("Config",{}).get("Image")=="postgres:17-alpine","image changed: "+name)
 h=c.get("HostConfig") or {}
 require(h.get("Privileged") is False,"privileged: "+name)
 require(h.get("NetworkMode")=="none","joined to network: "+name)
 require((h.get("RestartPolicy") or {}).get("Name") in ("no",""),"restart policy changed: "+name)
 n=c.get("NetworkSettings") or {}
 require(not (n.get("Networks") or {}),"connected network: "+name)
 require(not any(nport for nport in (n.get("Ports") or {}).values()),"published port: "+name)
 require(not (c.get("Config",{}).get("Labels") or {}).get("com.docker.compose.project"),"compose owned: "+name)
 mounts=c.get("Mounts") or []
 require(len(mounts)==1,"unexpected mounts: "+name)
 m=mounts[0]
 require(m.get("Type")=="volume" and m.get("Name")==vol
         and m.get("Destination")=="/var/lib/postgresql/data","unexpected volume mount: "+name)
 used=docker("ps","-a","--filter","volume="+vol,"--format","{{.Names}}").splitlines()
 require(used==[name],"volume reference changed: "+vol)
 v=json.loads(docker("volume","inspect",vol))[0]
 require(v.get("Name")==vol,"volume name mismatch: "+vol)
 print("VERIFIED: "+name+" → "+vol+"; isolated, unshared, no public ports")
def main():
 parser=argparse.ArgumentParser()
 parser.add_argument("--apply",action="store_true",help="Deletion requires exact environment confirmation too")
 args=parser.parse_args()
 print("===== FOUR EXACT ISOLATED POSTGRES REHEARSALS =====",flush=True)
 require(BACKUP.is_file(),"verified Production backup is missing")
 digest=hashlib.file_digest(BACKUP.open("rb"),"sha256").hexdigest()
 require(digest==EXPECTED_SHA,"recovery backup checksum changed")
 docker("inspect","hi5central-postgres")
 for p in PAIRS: check_one(*p)
 print("PASS: all four candidates and verified Production recovery archive match.")
 if not args.apply:
  print("DRY RUN ONLY. No container or volume deleted.")
  print("After approval: H5C_CONFIRM_DISPOSABLE_DB_CLEANUP=DELETE_EXACT_FOUR_REHEARSALS python3 "+sys.argv[0]+" --apply")
  return
 require(os.environ.get("H5C_CONFIRM_DISPOSABLE_DB_CLEANUP")=="DELETE_EXACT_FOUR_REHEARSALS",
         "exact operator confirmation not provided")
 # Recheck full preconditions again immediately before each operation.
 for p in PAIRS:
  name,vol,_=p
  check_one(*p)
  subprocess.check_call(["docker","stop","--time","20",name],stdout=subprocess.DEVNULL)
  subprocess.check_call(["docker","rm",name],stdout=subprocess.DEVNULL)
  subprocess.check_call(["docker","volume","rm",vol],stdout=subprocess.DEVNULL)
  print("REMOVED: "+name+" + "+vol,flush=True)
 docker("inspect","hi5central-postgres")
 print("PASS: primary Production Postgres container remains present. No other resource targeted.")
if __name__=="__main__":
 try:main()
 except (RuntimeError,subprocess.CalledProcessError,PermissionError,OSError) as error:
  print("BLOCKED: "+str(error),file=sys.stderr)
  sys.exit(1)
