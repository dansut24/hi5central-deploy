#!/usr/bin/env python3
"""Make a synthetic global software seed using the ACTUAL migrated schema.

Inside a single READ/WRITE PostgreSQL TRANSACTION: insert four fake software
objects, export their full JSON records with the same to_jsonb() method as
the real exporter, ROLLBACK. This retains defaults from every real migration,
while leaving NO CI catalogue rows prior to the importer.
No production data, no external URLs beyond example.invalid.
"""
from datetime import datetime,timezone
from pathlib import Path
import csv
import hashlib
import io
import json
import os
import subprocess
import sys
import tarfile
import tempfile

TABLES={
 "catalogue":"rmm_software_catalogue",
 "vendor_sources":"rmm_software_vendor_sources",
 "vendor_bindings":"rmm_software_vendor_bindings",
 "vendor_releases":"rmm_software_vendor_releases",
}
SQL=r"""
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL statement_timeout='25s';
INSERT INTO public.rmm_software_vendor_sources
 (source_key,display_name,source_type,source_url,enabled,priority,poll_minutes,metadata)
VALUES ('synthetic_release_ci','Synthetic CI Vendor','vendor_api',
 'https://example.invalid/ci-fake-vendor-api',false,10,1440,'{"ci_fixture":true}'::jsonb);
INSERT INTO public.rmm_software_vendor_bindings
 (source_key,provider_package_id,canonical_name,publisher,channel,platform,architecture,enabled,metadata)
VALUES ('synthetic_release_ci','Synthetic.Example','Synthetic CI Package',
 'HI5 CI fixture only','stable','windows','x64',false,'{"ci_fixture":true}'::jsonb);
INSERT INTO public.rmm_software_vendor_releases
 (source_key,provider_package_id,canonical_name,publisher,channel,platform,architecture,version,
  installer_url,installer_sha256,installer_type,source_priority,source_payload)
VALUES ('synthetic_release_ci','Synthetic.Example','Synthetic CI Package',
 'HI5 CI fixture only','stable','windows','x64','1.2.3','','','',10,
 '{"ci_fixture":true}'::jsonb);
INSERT INTO public.rmm_software_catalogue
 (tenant_id,canonical_name,publisher,name_pattern,publisher_pattern,platform,provider,
  provider_package_id,target_version,release_channel,installer_type,status)
VALUES (NULL,'Synthetic CI Package','HI5 CI fixture only',
 'Synthetic CI Package','HI5 CI fixture only','windows','winget',
 'Synthetic.Example','1.2.3','stable','exe','active');
COPY (
 SELECT 'catalogue' AS kind,
  (to_jsonb(c)-'created_by_user_id'-'updated_by_user_id'-'qualified_by_user_id')::text
 FROM public.rmm_software_catalogue c
 WHERE c.canonical_name='Synthetic CI Package' AND c.tenant_id IS NULL
 UNION ALL
 SELECT 'vendor_sources',to_jsonb(s)::text FROM public.rmm_software_vendor_sources s
 WHERE s.source_key='synthetic_release_ci'
 UNION ALL
 SELECT 'vendor_bindings',to_jsonb(b)::text FROM public.rmm_software_vendor_bindings b
 WHERE b.source_key='synthetic_release_ci'
 UNION ALL
 SELECT 'vendor_releases',to_jsonb(r)::text FROM public.rmm_software_vendor_releases r
 WHERE r.source_key='synthetic_release_ci'
) TO STDOUT WITH (FORMAT csv);
ROLLBACK;
"""
def make(path):
 name="hi5central-managed-postgres-1"
 # CI postgres is disposable and has no published ports; never use host's
 # existing Production container. No data survives the SQL ROLLBACK.
 c=json.loads(subprocess.check_output(["docker","inspect",name],text=True))[0]
 labels=c.get("Config",{}).get("Labels") or {}
 if labels.get("com.docker.compose.project")!="hi5central-managed" or \
    labels.get("com.docker.compose.service")!="postgres" or \
    any(v for v in (c.get("NetworkSettings",{}).get("Ports") or {}).values()):
  raise RuntimeError("Synthetic fixture must target isolated managed CI postgres without public ports.")
 cmd=["docker","exec","-i",name,"sh","-c",
      'exec psql -X -q -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"']
 r=subprocess.run(cmd,input=SQL,text=True,capture_output=True,timeout=40)
 if r.returncode:
  raise RuntimeError("Full-schema synthetic SQL data generation rejected: "+
                     r.stderr[-2000:])
 grouped={key:[] for key in TABLES}
 for kind,encoded in csv.reader(io.StringIO(r.stdout),strict=True):
  if kind not in grouped:raise RuntimeError("Unexpected synthetic SQL row category")
  value=json.loads(encoded)
  if not isinstance(value,dict):raise RuntimeError("Synthetic source must be an object")
  if kind=="catalogue":
   if value.get("tenant_id") is not None:raise RuntimeError("Unexpected tenant-scoped fake catalogue")
   if any(k in value for k in ("created_by_user_id","updated_by_user_id","qualified_by_user_id")):
    raise RuntimeError("Fake catalogue retains old user FK")
  grouped[kind].append(value)
 if any(len(x)!=1 for x in grouped.values()):
  raise RuntimeError("Expected one synthetic row of each kind, got "+str({k:len(v) for k,v in grouped.items()}))
 with tempfile.TemporaryDirectory() as td:
  tmp=Path(td)
  manifest_rows=[]
  for kind,table in TABLES.items():
   f=tmp/(kind+".jsonl")
   f.write_text("".join(json.dumps(row,separators=(",",":"),sort_keys=True)+"\n"
                  for row in grouped[kind]),encoding="utf-8")
   manifest_rows.append({"alias":kind,"table":table,"file":f.name,
                         "rows":len(grouped[kind]),
                         "sha256":hashlib.sha256(f.read_bytes()).hexdigest()})
  (tmp/"manifest.json").write_text(json.dumps({
   "format":"hi5central-global-software-seed-v1",
   "created_utc":datetime.now(timezone.utc).isoformat(),
   "tenant_scoped_catalogue_exported":False,
   "tables":manifest_rows,
  },indent=2)+"\n")
  with tarfile.open(path,"w:gz") as tar:
   for f in [tmp/"manifest.json",*(tmp/(kind+".jsonl") for kind in TABLES)]:
    tar.add(f,arcname=f.name)
 print("PASS: real-schema synthetic global seed generated from fully populated PostgreSQL records (SQL ROLLBACK).")
if __name__=="__main__":
 if len(sys.argv)!=2:raise SystemExit("usage: make_full_schema_seed.py OUTPUT.tar.gz")
 try:make(Path(sys.argv[1]))
 except (RuntimeError,OSError,ValueError,subprocess.CalledProcessError,
         subprocess.TimeoutExpired,csv.Error) as err:
  print("BLOCKED: "+str(err),file=sys.stderr);sys.exit(3)
