"""Prove derived Compose settings cannot seed tenants, unpause or leak secrets."""
import importlib.util
import json
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import patch
from test_managed_image_manifest import good_manifest

SRC=Path(__file__).resolve().parents[1]/"scripts/render-managed-runtime.py"
spec=importlib.util.spec_from_file_location("render_managed_runtime",SRC)
mod=importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

def source_env():
 return {
  "COMPOSE_PROJECT_NAME":"hi5central-managed",
  "DEPLOYMENT_MODE":"managed",
  "TENANCY_MODE":"multi",
  "ROOT_DOMAIN":"hi5central.com",
  "PRIMARY_TENANT_SLUG":"",
  "MANAGED_TENANT_SLUGS":"",
  "POSTGRES_PASSWORD":"a"*96,
  "TURN_SHARED_SECRET":"b"*64,
  "RELEASE_ROLLOUT_PAUSED":"true",
  "BACKGROUND_WORKERS_ENABLED":"false",
 }
class RenderTest(unittest.TestCase):
 def test_render_only_pinned_services_and_empty_tenant(self):
  data=mod.render(source_env(),good_manifest())
  self.assertEqual(data["HI5_IMAGE_MARKETING"],good_manifest()["images"]["marketing"])
  self.assertEqual(data["HI5_PGADMIN_IMAGE"],good_manifest()["images"]["pgadmin"])
  self.assertEqual(data["HI5_IMAGE_CONFIG_INIT"],good_manifest()["images"]["config_init"])
  self.assertEqual(data["MANAGED_TENANT_SLUGS"],"")
  self.assertEqual(data["PRIMARY_TENANT_SLUG"],"")
  self.assertEqual(data["RELEASE_ROLLOUT_PAUSED"],"true")
  self.assertEqual(data["BACKGROUND_WORKERS_ENABLED"],"false")
  self.assertEqual(data["MARKETING_ADDRESS"],"hi5central.com")
 def test_deny_preseeded_tenant_or_unpaused(self):
  for key,value in (("PRIMARY_TENANT_SLUG","test"),
                    ("MANAGED_TENANT_SLUGS","test"),
                    ("RELEASE_ROLLOUT_PAUSED","false"),
                    ("COMPOSE_PROJECT_NAME","existing")):
   d=source_env()
   d[key]=value
   with self.assertRaises(ValueError): mod.render(d,good_manifest())
 def test_env_parser_denies_expansion_and_duplicates(self):
  with tempfile.TemporaryDirectory() as td:
   p=Path(td)/"generated.env"
   p.write_text("POSTGRES_PASSWORD=secret\nPOSTGRES_PASSWORD=again\n")
   p.chmod(0o600)
   with self.assertRaises(ValueError):mod.parse_env(p)
   p.write_text("POSTGRES_PASSWORD=$(malicious)\n")
   with self.assertRaises(ValueError):mod.parse_env(p)
 def test_env_file_cannot_be_world_readable(self):
  with tempfile.TemporaryDirectory() as td:
   p=Path(td)/"generated.env"
   p.write_text("POSTGRES_PASSWORD=private\n")
   p.chmod(0o644)
   with self.assertRaises(ValueError):mod.parse_env(p)
if __name__=="__main__":unittest.main()
