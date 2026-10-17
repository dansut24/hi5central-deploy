"""Reject unsafe or partial fresh-install manifest inputs (no registry calls)."""
import copy
import importlib.util
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
p=ROOT/"scripts/validate-managed-image-manifest.py"
spec=importlib.util.spec_from_file_location("managed_manifest",p)
m=importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

def good_manifest():
 sha="a"*40
 images={k:"ghcr.io/dansut24/hi5central-"+k.replace("_","-")+"@sha256:"+("b"*64)
  for k in m.IMAGE_NAMES}
 images.update({
  "postgres":"docker.io/library/postgres@sha256:"+("c"*64),
  "redis":"docker.io/library/redis@sha256:"+("d"*64),
  "caddy":"docker.io/library/caddy@sha256:"+("e"*64),
  "turn":"docker.io/coturn/coturn@sha256:"+("f"*64),
  "pgadmin":"docker.io/dpage/pgadmin4@sha256:"+("1"*64),
 })
 native={k:{"status":"verified","url":"https://downloads.hi5central.com/verified/"+k,
            "sha256":"7"*64,"platform_git_sha":sha}
          for k in m.NATIVE_NAMES}
 return {"schema":"hi5central-managed-restore-v1","deployment_kind":"managed_fresh",
         "platform_git_sha":sha,"tenant_seed_count":0,"release_rollout_paused":True,
         "catalogue_seed_policy":"global_only","externals_optional":True,
         "images":images,"native_artifacts":native,
         "approvals":{"platform_release_review":"approved-platform-review-123",
                      "managed_infrastructure_review":"approved-infra-review-123",
                      "host_dispatcher_security_review":"approved-host-security-review-123"}}

class ManagedManifestTest(unittest.TestCase):
 def test_complete_valid_manifest(self):
  r=m.validate(good_manifest())
  self.assertEqual(r["tenant_seed_count"],0)
  self.assertEqual(r["images"],len(m.IMAGE_NAMES))
  self.assertTrue(r["rollout_paused"])
 def test_missing_mandatory_image_denied(self):
  d=good_manifest()
  del d["images"]["protected_host_dispatcher"]
  with self.assertRaisesRegex(ValueError,"Image names"):
   m.validate(d)
 def test_misleading_build_tag_denied(self):
  d=good_manifest()
  d["images"]["api"]="ghcr.io/dansut24/hi5central-platform-api:latest"
  with self.assertRaisesRegex(ValueError,"Unpinned"):
   m.validate(d)
 def test_real_tenants_or_active_rollout_denied(self):
  for k,v in [("tenant_seed_count",1),("release_rollout_paused",False)]:
   d=good_manifest();d[k]=v
   with self.assertRaises(ValueError):m.validate(d)
 def test_unpublished_installer_denied(self):
  d=good_manifest()
  d["native_artifacts"]["windows_agent"]["status"]="not_ready"
  with self.assertRaisesRegex(ValueError,"publication"):
   m.validate(d)
 def test_native_build_mismatch_denied(self):
  d=good_manifest()
  d["native_artifacts"]["macos_viewer"]["platform_git_sha"]="f"*40
  with self.assertRaisesRegex(ValueError,"exact Platform SHA"):
   m.validate(d)
 def test_external_accounts_may_be_skipped(self):
  d=good_manifest()
  self.assertTrue(m.validate(d)["validated_metadata_only"])
 def test_missing_security_approval_denied(self):
  d=good_manifest();d["approvals"]["host_dispatcher_security_review"]=""
  with self.assertRaisesRegex(ValueError,"independent review"):
   m.validate(d)

if __name__=="__main__":unittest.main()
