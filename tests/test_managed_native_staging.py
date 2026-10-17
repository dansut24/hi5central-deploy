"""Native build package protection tests; all fixtures are fake tiny files."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from test_managed_image_manifest import good_manifest

PATH=Path(__file__).resolve().parents[1]/"scripts/stage-managed-native-artifacts.py"
spec=importlib.util.spec_from_file_location("native_staging",PATH)
m=importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

def fixture(source,manifest):
 for key,info in manifest["native_artifacts"].items():
  p=source/key/info["filename"]
  p.parent.mkdir(parents=True,exist_ok=True)
  data=("hi5c-ci-"+key).encode()
  p.write_bytes(data)
  info["size_bytes"]=len(data)
  info["sha256"]=hashlib.sha256(data).hexdigest()
 return json.dumps(manifest,sort_keys=True).encode()

class NativeStagingTest(unittest.TestCase):
 def test_atomic_full_publish_and_idempotent(self):
  with tempfile.TemporaryDirectory() as td:
   root=Path(td);source=root/"source";source.mkdir()
   dest=root/"downloads"
   manifest=good_manifest()
   raw=fixture(source,manifest)
   with patch.object(m.os,"geteuid",return_value=0):
    m.stage(raw,manifest,source,dest,False)
    m.stage(raw,manifest,source,dest,False)
   meta=json.loads((dest/"latest.json").read_text())
   self.assertEqual(set(meta["artifacts"]),set(m.validator.NATIVE_NAMES))
   self.assertTrue(meta["agent_viewer_versions_are_managed_centrally"])
   for key,entry in meta["artifacts"].items():
    p=dest/entry["path"]
    self.assertEqual(hashlib.sha256(p.read_bytes()).hexdigest(),entry["sha256"])
    self.assertFalse(p.is_symlink())
 def test_refuses_partial_publish_if_package_tampered(self):
  with tempfile.TemporaryDirectory() as td:
   root=Path(td);source=root/"source";source.mkdir()
   dest=root/"downloads"
   manifest=good_manifest()
   raw=fixture(source,manifest)
   (source/"windows_agent"/"windows_agent.bin").write_bytes(b"tampered")
   with patch.object(m.os,"geteuid",return_value=0):
    with self.assertRaises(RuntimeError):m.stage(raw,manifest,source,dest,False)
   self.assertFalse(dest.exists())
 def test_dry_run_checks_all_bytes_but_writes_nothing(self):
  with tempfile.TemporaryDirectory() as td:
   root=Path(td);source=root/"source";source.mkdir()
   dest=root/"downloads"
   manifest=good_manifest()
   raw=fixture(source,manifest)
   m.stage(raw,manifest,source,dest,True)
   self.assertFalse(dest.exists())
 def test_does_not_follow_symlink_package(self):
  with tempfile.TemporaryDirectory() as td:
   root=Path(td);source=root/"source";source.mkdir()
   dest=root/"downloads"
   manifest=good_manifest()
   raw=fixture(source,manifest)
   p=source/"linux_viewer"/"linux_viewer.bin"
   p.unlink()
   p.symlink_to(source/"windows_agent"/"windows_agent.bin")
   with self.assertRaises(RuntimeError):m.stage(raw,manifest,source,dest,True)
 def test_refuses_replacing_centrally_managed_release_silently(self):
  with tempfile.TemporaryDirectory() as td:
   root=Path(td);source=root/"source";source.mkdir()
   dest=root/"downloads"
   first=good_manifest()
   raw=fixture(source,first)
   with patch.object(m.os,"geteuid",return_value=0):
    m.stage(raw,first,source,dest,False)
   other=good_manifest()
   different=fixture(source,other)
   other["native_artifacts"]["windows_agent"]["source_git_sha"]="e"*40
   different=json.dumps(other,sort_keys=True).encode()
   with self.assertRaises(RuntimeError):m.stage(different,other,source,dest,False)
 def test_rejects_missing_required_platform(self):
  with tempfile.TemporaryDirectory() as td:
   root=Path(td);source=root/"source";source.mkdir()
   dest=root/"downloads"
   manifest=good_manifest()
   raw=fixture(source,manifest)
   (source/"avalonia_self_service"/"avalonia_self_service.bin").unlink()
   with self.assertRaises(RuntimeError):m.stage(raw,manifest,source,dest,True)
if __name__=="__main__":
 unittest.main()
