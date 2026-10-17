#!/usr/bin/env python3
"""Restore four global RMM software datasets to a NEW, EMPTY managed database.

- Requires a verified archive, a dedicated clean managed Compose postgres,
  zero tenants, zero RMM agents, no qualification jobs, and paused release jobs.
- Executes source deletions + imports in ONE PostgreSQL transaction so a failure
  restores the previous fresh-DB migration seeds exactly.
- Does NOT operate on old VPS/Production postgres, even if invoked as root.
- Does not migrate users, tenants, ITSM tickets or RMM device state.
"""
import argparse
import csv
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile

KINDS=("vendor_sources","vendor_bindings","vendor_releases","catalogue")
TABLES={kind:"rmm_software_"+kind for kind in KINDS}
TABLES["catalogue"]="rmm_software_catalogue"
if TABLES["vendor_sources"]!="rmm_software_vendor_sources":
 raise RuntimeError("Broken table definitions")
def fail(msg): raise RuntimeError(msg)
def sha256(blob): return hashlib.sha256(blob).hexdigest()

def payload(archive):
 with tarfile.open(archive,"r:gz") as t:
  members={m.name:m for m in t.getmembers()}
  needed={"manifest.json",*(k+".jsonl" for k in KINDS)}
  if set(members)!=needed or not all(m.isfile() and m.size<=100*1024*1024 for m in members.values()):
   fail("Archive member list/size unsafe.")
  manifest=json.loads(t.extractfile("manifest.json").read())
  if manifest.get("format")!="hi5central-global-software-seed-v1":
   fail("Unknown software seed version.")
  meta={x["alias"]:x for x in manifest.get("tables",[])}
  if set(meta)!=set(KINDS):fail("Missing source dataset.")
  rows=[]
  counts={}
  source_ids=set()
  for kind in KINDS:
   raw=t.extractfile(kind+".jsonl").read()
   if sha256(raw)!=meta[kind]["sha256"]:fail("Archive checksum mismatch: "+kind)
   if meta[kind]["table"]!=TABLES[kind] or meta[kind]["file"]!=kind+".jsonl":
    fail("Archive table alias mismatch.")
   entries=[json.loads(line) for line in raw.splitlines() if line.strip()]
   if len(entries)!=meta[kind]["rows"]:fail("Archive row count mismatch: "+kind)
   counts[kind]=len(entries)
   for row in entries:
    if not isinstance(row,dict):fail("Nonobject source row.")
    if kind=="catalogue":
     if row.get("tenant_id") is not None: fail("Tenant row in global catalogue.")
     for key in ("created_by_user_id","updated_by_user_id","qualified_by_user_id"):
      if key in row:fail("Legacy user foreign key in catalogue.")
    if kind=="vendor_sources":
     source_ids.add(row.get("source_key"))
    rows.append((kind,json.dumps(row,separators=(",",":"),sort_keys=True)))
  for kind,doc in rows:
   if kind in ("vendor_bindings","vendor_releases"):
    if json.loads(doc).get("source_key") not in source_ids:
     fail("Missing vendor source reference.")
  if not counts["catalogue"] or not counts["vendor_sources"]:
   fail("Empty catalogue or vendor source dataset.")
  return counts,rows

# These four allowlisted tables are the ONLY target data tables. The new
# database may have vendor defaults seeded by migration 043; clear only those
# after confirming the entire managed database is empty of tenants/agents.
SQL_BEGIN=r"""
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL statement_timeout='180s';
SET LOCAL lock_timeout='15s';
DO $h5$
BEGIN
 IF (SELECT count(*) FROM public.tenants)<>0
 OR (SELECT count(*) FROM public.users)<>0
 OR (SELECT count(*) FROM public.rmm_agent_devices)<>0
 OR (SELECT count(*) FROM public.itsm_records)<>0
 OR (SELECT count(*) FROM public.rmm_software_qualification_queue)<>0
 OR (SELECT count(*) FROM public.tenant_release_rollout_jobs)<>0
 OR (SELECT paused FROM public.platform_release_rollout_control WHERE singleton=true)
    IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'Not a blank, globally paused new managed installation';END IF;
END $h5$;
-- Freeze concurrent updates and start from fresh migration vendor defaults.
DELETE FROM public.rmm_software_vendor_releases;
DELETE FROM public.rmm_software_vendor_bindings;
DELETE FROM public.rmm_software_vendor_sources;
DELETE FROM public.rmm_software_catalogue;
CREATE TEMP TABLE hi5_import_seed(kind text NOT NULL, doc jsonb NOT NULL) ON COMMIT DROP;
COPY hi5_import_seed(kind,doc) FROM STDIN WITH (FORMAT csv, DELIMITER E'\t');
"""
SQL_END=r"""\.
DO $h5$
DECLARE bad integer;
BEGIN
 SELECT count(*) INTO bad FROM hi5_import_seed
 WHERE kind NOT IN ('vendor_sources','vendor_bindings','vendor_releases','catalogue');
 IF bad<>0 THEN RAISE EXCEPTION 'Nonallowlisted data in import';END IF;
END $h5$;
INSERT INTO public.rmm_software_vendor_sources
 SELECT (jsonb_populate_record(NULL::public.rmm_software_vendor_sources,doc)).*
 FROM hi5_import_seed WHERE kind='vendor_sources';
INSERT INTO public.rmm_software_vendor_bindings
 SELECT (jsonb_populate_record(NULL::public.rmm_software_vendor_bindings,doc)).*
 FROM hi5_import_seed WHERE kind='vendor_bindings';
INSERT INTO public.rmm_software_vendor_releases
 SELECT (jsonb_populate_record(NULL::public.rmm_software_vendor_releases,doc)).*
 FROM hi5_import_seed WHERE kind='vendor_releases';
INSERT INTO public.rmm_software_catalogue
 SELECT (jsonb_populate_record(NULL::public.rmm_software_catalogue,doc)).*
 FROM hi5_import_seed WHERE kind='catalogue';
DO $h5$
BEGIN
 IF (SELECT count(*) FROM public.rmm_software_vendor_sources)
  <> (SELECT count(*) FROM hi5_import_seed WHERE kind='vendor_sources')
 OR (SELECT count(*) FROM public.rmm_software_vendor_bindings)
  <> (SELECT count(*) FROM hi5_import_seed WHERE kind='vendor_bindings')
 OR (SELECT count(*) FROM public.rmm_software_vendor_releases)
  <> (SELECT count(*) FROM hi5_import_seed WHERE kind='vendor_releases')
 OR (SELECT count(*) FROM public.rmm_software_catalogue)
  <> (SELECT count(*) FROM hi5_import_seed WHERE kind='catalogue')
 OR EXISTS (SELECT 1 FROM public.rmm_software_catalogue WHERE tenant_id IS NOT NULL)
 THEN RAISE EXCEPTION 'Software catalogue import count or tenant isolation failure';END IF;
END $h5$;
COMMIT;
"""

def main():
 parser=argparse.ArgumentParser()
 parser.add_argument("--archive",type=Path,required=True)
 parser.add_argument("--container",default="hi5central-managed-postgres-1")
 parser.add_argument("--dry-run",action="store_true")
 parser.add_argument("--apply",action="store_true")
 args=parser.parse_args()
 if args.dry_run==args.apply:fail("Specify exactly one of --dry-run or --apply.")
 counts,rows=payload(args.archive)
 if args.dry_run:
  print("PASS: archive checked; no PostgreSQL or Docker access was attempted.")
  print("Datasets:",json.dumps(counts,sort_keys=True))
  print("To import after NEW managed migrations only, use --apply.")
  return
 if os.geteuid()!=0:fail("Importer must run as root on the fresh installation.")
 if args.container!="hi5central-managed-postgres-1":
  fail("Importer is restricted to the isolated NEW managed project postgres name.")
 c=json.loads(subprocess.check_output(["docker","inspect",args.container],text=True))[0]
 labels=c.get("Config",{}).get("Labels") or {}
 if labels.get("com.docker.compose.project")!="hi5central-managed" or labels.get("com.docker.compose.service")!="postgres":
  fail("Not a verified dedicated managed Compose PostgreSQL container.")
 if any(p for p in (c.get("NetworkSettings",{}).get("Ports") or {}).values()):
  fail("Database has an unexpected published host port.")
 buffer=io.StringIO()
 buffer.write(SQL_BEGIN)
 writer=csv.writer(buffer,delimiter="\t",lineterminator="\n")
 writer.writerows(rows)
 buffer.write(SQL_END)
 cmd=["docker","exec","-i",args.container,"sh","-c",
      'exec psql -X -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"']
 res=subprocess.run(cmd,input=buffer.getvalue(),text=True,capture_output=True)
 if res.returncode!=0:
  if os.environ.get("GITHUB_ACTIONS")=="true" and args.archive.name=="seed.tar.gz" and any(
      '"source_key":"synthetic_release_ci"' in doc for _,doc in rows):
   # Only artificial CI fixtures are permitted here; no real vendor secrets.
   print("CI SYNTHETIC ONLY PostgreSQL diagnostic: "+res.stderr[-3000:],file=sys.stderr)
  fail("Catalogue import failed and PostgreSQL transaction was rolled back (exit "+
       str(res.returncode)+").")
 print("PASS: global catalogue/source seed transaction committed in the NEW managed database.")
 print("Imported:",json.dumps(counts,sort_keys=True))
 print("No tenant, agent, ITSM ticket, approval or qualification-job history imported.")
if __name__=="__main__":
 try:main()
 except (RuntimeError,OSError,ValueError,json.JSONDecodeError,subprocess.CalledProcessError,tarfile.TarError) as e:
  print("BLOCKED: "+str(e),file=sys.stderr)
  sys.exit(1)
