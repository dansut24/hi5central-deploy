"""Full offline input checks before the single clean-install command runs."""
from io import BytesIO
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest
from test_global_software_seed import SeedTest
from test_managed_image_manifest import good_manifest

ROOT=Path(__file__).resolve().parents[1]
CHECK=ROOT/"scripts/verify-managed-reset-inputs.py"

class ManagedRestorePreflightTest(unittest.TestCase):
 def create(self,dir):
  root=Path(dir)
  catalogue=root/"global-software-seed-20261017T145713Z.tar.gz"
  SeedTest().pack(catalogue)
  manifest=good_manifest()
  sources=root/"native";sources.mkdir()
  for name,asset in manifest["native_artifacts"].items():
   data=("hi5-native-ci-"+name).encode()
   p=sources/name/asset["filename"]
   p.parent.mkdir()
   p.write_bytes(data)
   asset["sha256"]=hashlib.sha256(data).hexdigest()
   asset["size_bytes"]=len(data)
  manifest_file=root/"release.json"
  manifest_file.write_text(json.dumps(manifest),encoding="utf-8")
  recovery=root/"hi5central-catalogue-recovery-20261017.tar.gz"
  parts={
    "global-software-seed-20261017T145713Z.tar.gz":catalogue.read_bytes(),
    "hi5central-global-software-20261017.pgdump":b"PG custom fixture"*180,
    "production-schema-20261017.pgdump":b"Schema fixture"*180
  }
  sums="".join(hashlib.sha256(b).hexdigest()+"  "+n+"\n" for n,b in parts.items())
  parts["SHA256SUMS.txt"]=sums.encode("ascii")
  with tarfile.open(recovery,"w:gz") as t:
   for name,data in parts.items():
    info=tarfile.TarInfo(name);info.size=len(data);info.mode=0o600
    t.addfile(info,BytesIO(data))
  recovery.chmod(0o600)
  return manifest_file,catalogue,sources,recovery
 def check(self,manifest,catalogue,sources,recovery):
  return subprocess.run([sys.executable,str(CHECK),
    "--manifest",str(manifest),"--catalogue",str(catalogue),
    "--native-source-dir",str(sources),
    "--recovery-bundle",str(recovery)],
    capture_output=True,text=True,check=False)
 def test_complete_offline_restore_inputs_pass(self):
  with tempfile.TemporaryDirectory() as td:
   f=self.create(td)
   r=self.check(*f)
   self.assertEqual(r.returncode,0,r.stderr)
   self.assertIn("NO Docker, DB or network writes",r.stdout)
   self.assertIn("RESET NOT READY",r.stdout)
 def test_tampered_recovery_bundle_refused(self):
  with tempfile.TemporaryDirectory() as td:
   f=self.create(td)
   tampered=Path(td)/"bad.tar.gz"
   with tarfile.open(tampered,"w:gz") as out:
    with tarfile.open(f[3],"r:gz") as original:
     for member in original.getmembers():
      buf=original.extractfile(member).read()
      if member.name.startswith("global-software-seed-"):buf=b"modified"+buf
      member.size=len(buf)
      out.addfile(member,BytesIO(buf))
   self.assertNotEqual(self.check(f[0],f[1],f[2],tampered).returncode,0)
 def test_missing_native_asset_refused(self):
  with tempfile.TemporaryDirectory() as td:
   f=self.create(td)
   (f[2]/"windows_agent"/"windows_agent.bin").unlink()
   self.assertNotEqual(self.check(*f).returncode,0)
 def test_different_catalogue_than_recovery_refused(self):
  with tempfile.TemporaryDirectory() as td:
   f=self.create(td)
   second=Path(td)/"different-seed.tar.gz"
   SeedTest().pack(second)
   # Even identical logical rows produce a different archive header/digest.
   self.assertNotEqual(self.check(f[0],second,f[2],f[3]).returncode,0)
if __name__=="__main__": unittest.main()
