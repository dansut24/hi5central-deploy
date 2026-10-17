#!/usr/bin/env python3
"""Offline, read-only verification of the global software seed archive.
Does not import into Postgres; don't wipe VPS until fresh import is tested.
"""
import hashlib
import json
from pathlib import Path
import sys
import tarfile

KINDS={
 "catalogue":"rmm_software_catalogue",
 "vendor_sources":"rmm_software_vendor_sources",
 "vendor_bindings":"rmm_software_vendor_bindings",
 "vendor_releases":"rmm_software_vendor_releases",
}
def need(ok,msg):
 if not ok:raise RuntimeError(msg)
def main():
 need(len(sys.argv)==2,"Usage: verify-global-software-catalogue.py PRIVATE_ARCHIVE.tar.gz")
 p=Path(sys.argv[1])
 need(p.is_file(),"Archive not found.")
 with tarfile.open(p,"r:gz") as archive:
  members={m.name:m for m in archive.getmembers()}
  expected={"manifest.json",*(k+".jsonl" for k in KINDS)}
  need(set(members)==expected,"Unexpected missing/extra archive member.")
  need(all(m.isfile() and "/" not in m.name and not m.issym() and not m.islnk()
           for m in members.values()),"Unexpected archive structure.")
  man=json.load(archive.extractfile("manifest.json"))
  need(man.get("format")=="hi5central-global-software-seed-v1","Wrong manifest format.")
  need(man.get("tenant_scoped_catalogue_exported") is False,"Tenant-scoped catalogue included.")
  indexed={e["alias"]:e for e in man.get("tables",[])}
  need(set(indexed)==set(KINDS),"Manifest table set differs from allowlist.")
  counts={}
  refs=set()
  bindings=set()
  releases=set()
  catalog_ids=set()
  external=set()
  for kind,tablename in KINDS.items():
   item=indexed[kind]
   need(item["table"]==tablename and item["file"]==kind+".jsonl",
        "Manifest table/file mismatch: "+kind)
   h=hashlib.sha256()
   n=0
   with archive.extractfile(kind+".jsonl") as f:
    for line in f:
     h.update(line)
     row=json.loads(line)
     need(isinstance(row,dict),"Not a JSON object")
     if kind=="catalogue":
      need(row.get("tenant_id") is None,"Tenant-scoped catalogue found")
      need(not any(x in row for x in (
        "created_by_user_id","updated_by_user_id","qualified_by_user_id")),
        "Legacy user FK found in global catalogue")
      need(row.get("id") not in catalog_ids,"Duplicate catalogue ID")
      catalog_ids.add(row.get("id"))
      key=(row.get("catalogue_source"),row.get("external_key"))
      if key[1] and row.get("status")!="archived":
       need(key not in external,"Duplicate active global catalogue external key")
       external.add(key)
     if kind=="vendor_sources":
      need(row.get("source_key") not in refs,"Duplicate vendor source")
      refs.add(row.get("source_key"))
     if kind=="vendor_bindings":
      key=tuple(row.get(x) for x in (
       "source_key","provider_package_id","channel","platform","architecture"))
      need(key not in bindings,"Duplicate vendor binding")
      bindings.add(key)
     if kind=="vendor_releases":
      key=tuple(row.get(x) for x in (
       "source_key","provider_package_id","channel","platform","architecture","version"))
      need(key not in releases,"Duplicate vendor release")
      releases.add(key)
     n+=1
   need(h.hexdigest()==item["sha256"],"SHA256 mismatch in "+kind)
   need(n==item["rows"],"Row count mismatch in "+kind)
   counts[kind]=n
  need(counts["catalogue"]>0 and counts["vendor_sources"]>0,
       "Empty global software catalogue or sources.")
  # Intra-bundle vendor relations: read release/binding lists only, source IDs.
  for kind in ("vendor_bindings","vendor_releases"):
   with archive.extractfile(kind+".jsonl") as f:
    for line in f:
     source=json.loads(line).get("source_key")
     need(source in refs,"Unresolved vendor source reference in "+kind)
 print("PASS: Offline global software seed archive hash, rows, allowlist and vendor FK consistency.")
 print("Counts (no record data printed): "+json.dumps(counts,sort_keys=True))
 print("This is NOT an import/restore acceptance test.")
if __name__=="__main__":
 try:main()
 except (OSError,ValueError,KeyError,RuntimeError,tarfile.TarError) as e:
  print("BLOCKED: "+str(e),file=sys.stderr);sys.exit(1)
