"""The upload helper must reject unsafe archives and never call cloud tools on dry-run."""
import hashlib
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
from io import BytesIO

ROOT=Path(__file__).resolve().parents[1]
SCRIPT=ROOT/"scripts/upload-managed-recovery.sh"
RECIPIENT="age1"+"q"*55
S3="s3://hi5central-private-recovery/pre-reset/"

def create_fixture(path):
 records={
  "global-software-seed-20261017T145713Z.tar.gz":b"t"*3000,
  "hi5central-global-software-20261017.pgdump":b"p"*3000,
  "production-schema-20261017.pgdump":b"s"*3000,
 }
 sums="".join(hashlib.sha256(v).hexdigest()+"  "+k+"\n" for k,v in records.items())
 records["SHA256SUMS.txt"]=sums.encode()
 with tarfile.open(path,"w:gz") as t:
  for name,payload in records.items():
   info=tarfile.TarInfo(name);info.size=len(payload);info.mode=0o600
   t.addfile(info,BytesIO(payload))
 path.chmod(0o600)

class OffsiteGuardTest(unittest.TestCase):
 def invoke(self,path,action="--dry-run",recipient=RECIPIENT,uri=S3):
  return subprocess.run(["bash",str(SCRIPT),"--archive",str(path),
       "--recipient",recipient,"--s3-uri",uri,action],
       capture_output=True,text=True)
 def test_valid_backup_dry_run_does_not_upload(self):
  with tempfile.TemporaryDirectory() as td:
   p=Path(td)/"hi5central-catalogue-recovery-20261017.tar.gz"
   create_fixture(p)
   result=self.invoke(p)
   self.assertEqual(result.returncode,0,result.stderr)
   self.assertIn("DRY RUN",result.stdout)
 def test_refuse_world_readable_backup(self):
  with tempfile.TemporaryDirectory() as td:
   p=Path(td)/"hi5central-catalogue-recovery-20261017.tar.gz"
   create_fixture(p);p.chmod(0o644)
   self.assertNotEqual(self.invoke(p).returncode,0)
 def test_refuse_local_symlink(self):
  with tempfile.TemporaryDirectory() as td:
   p=Path(td)/"hi5central-catalogue-recovery-20261017.tar.gz"
   create_fixture(p)
   link=Path(td)/"copy.tar.gz"
   link.symlink_to(p)
   self.assertNotEqual(self.invoke(link).returncode,0)
 def test_refuse_wrong_destination_and_bad_public_key(self):
  with tempfile.TemporaryDirectory() as td:
   p=Path(td)/"hi5central-catalogue-recovery-20261017.tar.gz"
   create_fixture(p)
   self.assertNotEqual(self.invoke(p,uri="https://github.com/example/data").returncode,0)
   self.assertNotEqual(self.invoke(p,recipient="AGE-SECRET-KEY-1notpublic").returncode,0)
 def test_refuse_empty_or_missing_bundle(self):
  with tempfile.TemporaryDirectory() as td:
   p=Path(td)/"hi5central-catalogue-recovery-20261017.tar.gz"
   p.write_bytes(b"short");p.chmod(0o600)
   self.assertNotEqual(self.invoke(p).returncode,0)
if __name__=="__main__":unittest.main()
