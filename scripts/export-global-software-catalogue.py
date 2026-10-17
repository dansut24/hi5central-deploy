#!/usr/bin/env python3
"""Read-only consistent PostgreSQL export of GLOBAL software catalogue and
vendor source definitions. Produces root-only data files and manifest.
No DDL/DML, no tenant-scoped source rows, no agents, no ITSM/RMM records.
Full Production recovery backup must be kept separately.

Example:
  sudo python3 scripts/export-global-software-catalogue.py
"""
import csv
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
from datetime import datetime, timezone

BASE=Path("/var/backups/hi5central/catalogue-seed")
TABLES={
  "catalogue": "rmm_software_catalogue",
  "vendor_sources": "rmm_software_vendor_sources",
  "vendor_bindings": "rmm_software_vendor_bindings",
  "vendor_releases": "rmm_software_vendor_releases",
}
# This copy runs as one read-only PostgreSQL statement: a consistent snapshot.
# Tenant-scoped software items are EXCLUDED. User FK columns are removed from
# catalogue rows so they can be imported into a blank users table.
QUERY=r"""
COPY (
 SELECT 'catalogue' AS kind,
   (to_jsonb(c) - 'created_by_user_id' - 'updated_by_user_id'
                - 'qualified_by_user_id')::text AS document
 FROM public.rmm_software_catalogue AS c
 WHERE c.tenant_id IS NULL
 UNION ALL
 SELECT 'vendor_sources', to_jsonb(s)::text
 FROM public.rmm_software_vendor_sources AS s
 UNION ALL
 SELECT 'vendor_bindings', to_jsonb(b)::text
 FROM public.rmm_software_vendor_bindings AS b
 UNION ALL
 SELECT 'vendor_releases', to_jsonb(r)::text
 FROM public.rmm_software_vendor_releases AS r
) TO STDOUT WITH (FORMAT csv);
"""

def sha(path):
 h=hashlib.sha256()
 with path.open("rb") as f:
  for part in iter(lambda:f.read(1024*1024),b""):
   h.update(part)
 return h.hexdigest()

def main():
 os.umask(0o077)
 if os.geteuid()!=0:
  raise RuntimeError("Run as root; catalogue source metadata must remain private.")
 if not BASE.is_dir():
  BASE.mkdir(mode=0o700,parents=True)
 os.chmod(BASE,0o700)
 stamp=datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
 final=BASE/("global-software-seed-"+stamp+".tar.gz")
 if final.exists():
  raise RuntimeError("Refusing to overwrite an existing seed bundle.")
 backup=Path("/var/backups/hi5central/release-activation/pre-generic-final-20261017T110313Z.dump")
 if not backup.is_file() or backup.stat().st_size<1000000:
  raise RuntimeError("Verified original Production recovery dump missing.")
 with tempfile.TemporaryDirectory(prefix=".global-catalogue-",dir=BASE) as td:
  tmp=Path(td)
  files={k:(tmp/(k+".jsonl")).open("w",encoding="utf-8",newline="\n") for k in TABLES}
  counts={k:0 for k in TABLES}
  # --no-psqlrc via -X and no network/credentials exposed in output.
  # The transaction is a single server-side COPY query, hence consistent.
  proc=subprocess.Popen([
    "docker","exec","-i","hi5central-postgres","sh","-c",
    'exec psql -X -q -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" '
    '-d "$POSTGRES_DB" -c "$1"',"sh",QUERY
  ],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,encoding="utf-8")
  try:
   reader=csv.reader(proc.stdout,strict=True)
   for row in reader:
    if len(row)!=2:
     raise RuntimeError("Unexpected export row shape.")
    kind,document=row
    if kind not in files:
     raise RuntimeError("Unexpected source kind.")
    data=json.loads(document)
    if not isinstance(data,dict):
     raise RuntimeError("Unexpected document value.")
    if kind=="catalogue":
     if data.get("tenant_id") is not None:
      raise RuntimeError("Tenant-scoped catalogue row found in global seed.")
     if any(field in data for field in
       ("created_by_user_id","updated_by_user_id","qualified_by_user_id")):
      raise RuntimeError("Catalogue export contains an original user reference.")
    files[kind].write(json.dumps(data,sort_keys=True,separators=(",",":"))+"\n")
    counts[kind]+=1
  except BaseException:
   proc.kill()
   proc.wait()
   raise
  finally:
   for f in files.values():
    f.close()
  err=proc.stderr.read(limit:=20000)
  rc=proc.wait()
  if rc!=0:
   raise RuntimeError("Read-only PostgreSQL catalogue export failed (psql exit "+str(rc)+").")
  if counts["vendor_sources"]==0 or counts["catalogue"]==0:
   raise RuntimeError("No global software catalogue/source rows. Refusing an empty export.")
  manifest={
   "format":"hi5central-global-software-seed-v1",
   "created_utc":datetime.now(timezone.utc).isoformat(),
   "source_database":"hi5central",
   "snapshot":"single-statement-repeatable-query",
   "contains_customer_tickets_devices_or_agent_secrets":False,
   "source_metadata_may_contain_credentials":True,
   "requires_independent_import_validation":True,
   "tenant_scoped_catalogue_exported":False,
   "tables":[{"alias":k,"table":v,"rows":counts[k],
              "file":k+".jsonl","sha256":sha(tmp/(k+".jsonl"))}
             for k,v in TABLES.items()],
  }
  manpath=tmp/"manifest.json"
  manpath.write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8")
  with tarfile.open(final,"w:gz") as arc:
   for path in [manpath,*[tmp/(k+".jsonl") for k in TABLES]]:
    arc.add(path,arcname=path.name,recursive=False)
 os.chmod(final,0o600)
 print("PASS: Global software catalogue seed safely exported.")
 print("Bundle: "+str(final))
 print("SHA256: "+sha(final))
 print("Global row counts (no data displayed): "+json.dumps(counts,sort_keys=True))
 print("IMPORTANT: This file can include source URLs and metadata; keep it private.")
 print("Do NOT wipe the VPS until the bundle is copied off-host AND")
 print("verified against a fresh PostgreSQL import on an isolated install.")
if __name__=="__main__":
 try:main()
 except Exception as e:
  print("BLOCKED: "+str(e),file=sys.stderr)
  sys.exit(1)
