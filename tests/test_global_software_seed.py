"""Offline contract tests for the privacy-filtered RMM software seed."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
VALIDATOR=ROOT/"scripts/verify-global-software-catalogue.py"
KINDS={
 "catalogue":"rmm_software_catalogue",
 "vendor_sources":"rmm_software_vendor_sources",
 "vendor_bindings":"rmm_software_vendor_bindings",
 "vendor_releases":"rmm_software_vendor_releases",
}
class SeedTest(unittest.TestCase):
 def pack(self,path,*,tenant_id=None,break_hash=False,source_ref="source1"):
  contents={
   "catalogue":[{"id":"cat1","tenant_id":tenant_id,"catalogue_source":"vendor","external_key":"vendor:foo","status":"active"}],
   "vendor_sources":[{"source_key":"source1","source_type":"vendor_json","source_url":"https://example.invalid/source"}],
   "vendor_bindings":[{"id":"binding1","source_key":source_ref,"provider_package_id":"Foo","channel":"stable","platform":"windows","architecture":"x64"}],
   "vendor_releases":[{"id":"release1","source_key":"source1","provider_package_id":"Foo","channel":"stable","platform":"windows","architecture":"x64","version":"1.0"}],
  }
  with tempfile.TemporaryDirectory() as td:
   tmp=Path(td)
   rows=[]
   for kind,table in KINDS.items():
    p=tmp/(kind+".jsonl")
    p.write_text("".join(json.dumps(x)+"\n" for x in contents[kind]),encoding="utf-8")
    checksum=hashlib.sha256(p.read_bytes()).hexdigest()
    rows.append({"alias":kind,"table":table,"file":p.name,
      "sha256":"0"*64 if break_hash and kind=="catalogue" else checksum,
      "rows":len(contents[kind])})
   (tmp/"manifest.json").write_text(json.dumps({
     "format":"hi5central-global-software-seed-v1",
     "tenant_scoped_catalogue_exported":False,"tables":rows
   }),encoding="utf-8")
   with tarfile.open(path,"w:gz") as t:
    for member in [tmp/"manifest.json",*(tmp/(k+".jsonl") for k in KINDS)]:
     t.add(member,arcname=member.name)
 def check(self,**opts):
  with tempfile.TemporaryDirectory() as td:
   path=Path(td)/"bundle.tar.gz"
   self.pack(path,**opts)
   return subprocess.run([sys.executable,str(VALIDATOR),str(path)],
     capture_output=True,text=True,check=False)
 def test_valid_global_export(self):
  out=self.check()
  self.assertEqual(out.returncode,0,out.stderr)
  self.assertIn("PASS:",out.stdout)
 def test_tenant_rows_denied(self):
  out=self.check(tenant_id="some-tenant")
  self.assertNotEqual(out.returncode,0)
  self.assertIn("Tenant-scoped",out.stderr)
 def test_hash_mismatch_denied(self):
  out=self.check(break_hash=True)
  self.assertNotEqual(out.returncode,0)
  self.assertIn("SHA256 mismatch",out.stderr)
 def test_missing_vendor_source_denied(self):
  out=self.check(source_ref="missing-source")
  self.assertNotEqual(out.returncode,0)
  self.assertIn("Unresolved vendor source reference",out.stderr)

if __name__=="__main__":
 unittest.main()
