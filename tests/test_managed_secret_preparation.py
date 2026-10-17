"""Offline new-VPS bootstrap tests. No VPS Docker, DB or external network."""
import contextlib
import importlib.util
import io
from pathlib import Path
import stat
import sys
import tempfile
import unittest
from unittest.mock import patch

SOURCE=Path(__file__).resolve().parents[1]/"scripts/prepare-managed-secrets.py"
spec=importlib.util.spec_from_file_location("prepare_managed_secrets",SOURCE)
module=importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class ManagedSecretPreparationTest(unittest.TestCase):
 def invoke(self,args):
  output=io.StringIO()
  with patch.object(sys,"argv",["prepare-managed-secrets.py",*args]):
   with contextlib.redirect_stdout(output),contextlib.redirect_stderr(output):
    with patch.object(module.os,"geteuid",return_value=0):
     module.main()
  return output.getvalue()
 def test_full_creation_private_and_no_credentials_in_output(self):
  with tempfile.TemporaryDirectory() as td:
   p=Path(td)/"managed"
   log=self.invoke(["--root",str(p),"--root-domain","hi5central.com",
      "--admin-email","platform-admin@example.invalid"])
   self.assertTrue(p.is_dir())
   self.assertEqual(stat.S_IMODE(p.stat().st_mode),0o700)
   self.assertEqual({x.name for x in p.iterdir()},set(module.FILES))
   for x in p.iterdir():
    self.assertEqual(stat.S_IMODE(x.stat().st_mode),0o600)
   conf=(p/"managed.env").read_text()
   self.assertIn("POSTGRES_PASSWORD=",conf)
   self.assertIn("RELEASE_ROLLOUT_PAUSED=true",conf)
   self.assertIn("SMTP_HOST=\n",conf)
   self.assertIn("TENANCY_MODE=multi",conf)
   self.assertIn("MANAGED_TENANT_SLUGS=\n",conf)
   self.assertIn("HI5_PGADMIN_PASSWORD_FILE="+str(p/"pgadmin-password"),conf)
   self.assertNotIn("CHANGE_ME",conf)
   self.assertNotIn("hi5central:",conf)
   secret=next(x.split("=",1)[1] for x in conf.splitlines() if x.startswith("POSTGRES_PASSWORD="))
   self.assertGreaterEqual(len(secret),64)
   self.assertNotIn(secret,log)
   self.assertIn("NOT completed",log)
   self.invoke(["--root",str(p),"--verify"])
   with self.assertRaises(RuntimeError):
    self.invoke(["--root",str(p),"--admin-email","platform-admin@example.invalid"])
 def test_dry_run_creates_nothing(self):
  with tempfile.TemporaryDirectory() as td:
   p=Path(td)/"managed"
   out=self.invoke(["--root",str(p),"--admin-email","owner@example.invalid","--dry-run"])
   self.assertIn("DRY RUN",out)
   self.assertFalse(p.exists())
 def test_existing_path_not_overwritten_even_when_empty(self):
  with tempfile.TemporaryDirectory() as td:
   p=Path(td)/"managed"
   p.mkdir()
   (p/"existing-secret").write_text("keep")
   with self.assertRaises(RuntimeError):
    self.invoke(["--root",str(p),"--admin-email","owner@example.invalid"])
   self.assertEqual((p/"existing-secret").read_text(),"keep")
 def test_rejects_unsafe_admin_email(self):
  with tempfile.TemporaryDirectory() as td:
   p=Path(td)/"managed"
   with self.assertRaises(RuntimeError):
    self.invoke(["--root",str(p),"--admin-email","evil\nPOSTGRES_PASSWORD=no"])
   self.assertFalse(p.exists())

if __name__=="__main__":
 unittest.main()
