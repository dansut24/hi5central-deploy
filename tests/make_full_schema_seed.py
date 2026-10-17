#!/usr/bin/env python3
"""Synthetic *global-only* software vendor/catalogue archive for full-schema CI.

The included examples are fake and may never be distributed as real software.
Makes archive in target path with manifest+SHA; no DB connection.
"""
from datetime import datetime,timezone
from pathlib import Path
import hashlib
import json
import sys
import tarfile
import tempfile

def make(path):
 ids={
  "catalogue":"00000000-0000-4000-8000-000000000101",
  "vendor_binding":"00000000-0000-4000-8000-000000000102",
  "vendor_release":"00000000-0000-4000-8000-000000000103",
 }
 src="synthetic_release_ci"
 fixtures={
  "catalogue":[{
    "id":ids["catalogue"],"tenant_id":None,
    "canonical_name":"Synthetic CI Package",
    "publisher":"HI5 CI fixture only",
    "name_pattern":"Synthetic CI Package",
    "publisher_pattern":"HI5 CI fixture only",
    "platform":"windows","provider":"winget",
    "provider_package_id":"Synthetic.Example",
    "target_version":"1.2.3","release_channel":"stable",
    "installer_type":"exe","status":"active",
  }],
  "vendor_sources":[{
    "source_key":src,
    "display_name":"Synthetic CI Vendor",
    "source_type":"vendor_api",
    "source_url":"https://example.invalid/ci-fake-vendor-api",
    "enabled":False,"priority":10,"poll_minutes":1440,
    "metadata":{"ci_fixture":True},
  }],
  "vendor_bindings":[{
    "id":ids["vendor_binding"],"source_key":src,
    "provider_package_id":"Synthetic.Example",
    "canonical_name":"Synthetic CI Package",
    "publisher":"HI5 CI fixture only",
    "channel":"stable","platform":"windows",
    "architecture":"x64","enabled":False,
    "metadata":{"ci_fixture":True},
  }],
  "vendor_releases":[{
    "id":ids["vendor_release"],"source_key":src,
    "provider_package_id":"Synthetic.Example",
    "canonical_name":"Synthetic CI Package",
    "publisher":"HI5 CI fixture only",
    "channel":"stable","platform":"windows","architecture":"x64",
    "version":"1.2.3",
    "installer_url":"","installer_sha256":"","installer_type":"",
    "source_priority":10,"source_payload":{"ci_fixture":True},
  }],
 }
 tables={
  "catalogue":"rmm_software_catalogue",
  "vendor_sources":"rmm_software_vendor_sources",
  "vendor_bindings":"rmm_software_vendor_bindings",
  "vendor_releases":"rmm_software_vendor_releases",
 }
 with tempfile.TemporaryDirectory() as td:
  tmp=Path(td)
  info=[]
  for kind,table in tables.items():
   text="".join(json.dumps(row,separators=(",",":"),sort_keys=True)+"\n"
                for row in fixtures[kind])
   p=tmp/(kind+".jsonl")
   p.write_text(text,encoding="utf-8")
   info.append({"alias":kind,"file":p.name,"table":table,
       "rows":len(fixtures[kind]),
       "sha256":hashlib.sha256(p.read_bytes()).hexdigest()})
  manifest={
   "format":"hi5central-global-software-seed-v1",
   "created_utc":datetime.now(timezone.utc).isoformat(),
   "tenant_scoped_catalogue_exported":False,
   "tables":info,
  }
  (tmp/"manifest.json").write_text(json.dumps(manifest,indent=2)+"\n")
  with tarfile.open(path,"w:gz") as archive:
   for p in [tmp/"manifest.json",*(tmp/(k+".jsonl") for k in tables)]:
    archive.add(p,arcname=p.name)
if __name__=="__main__":
 if len(sys.argv)!=2: raise SystemExit("usage: make_full_schema_seed.py OUT.tar.gz")
 make(Path(sys.argv[1]))
 print("PASS: synthetic one-row-per-allowlisted-table archive created; no real catalogue data.")
