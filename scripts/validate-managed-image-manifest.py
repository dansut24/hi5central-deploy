#!/usr/bin/env python3
"""Validate a pinned, complete Hi5Central clean-install artifact manifest.

Read-only, standard-library only. This validates the declared image/artifact
IDENTITIES and checksums, not remote registry access, signatures, malware,
supply-chain attestation or that any services are operational.
"""
import argparse
import json
from pathlib import Path
import re
import sys

IMAGE_NAMES=(
 "api","itsm","rmm","admin","marketing","agent_deployment_assets",
 "release_planner","release_executor","protected_host_dispatcher",
 "postgres","redis","caddy","turn","pgadmin",
)
PLATFORM=("api","itsm","rmm","admin")
NATIVE_NAMES=(
 "windows_agent","linux_agent","macos_agent",
 "windows_viewer","linux_viewer","macos_viewer","mobile_viewer",
 "avalonia_self_service",
)
HEXDIGEST=re.compile(r"^[0-9a-f]{64}$")
SHA=re.compile(r"^[0-9a-f]{40}$")
IMAGE=re.compile(r"^[a-z0-9.-]+(?::[0-9]+)?/(?:[a-z0-9._-]+/)*[a-z0-9._-]+@sha256:([0-9a-f]{64})$")
HTTPS=re.compile(r"^https://[A-Za-z0-9._~:/?#@!$&'()*+,;=%-]+$")
def require(cond,detail):
 if not cond: raise ValueError(detail)
def validate(manifest):
 require(isinstance(manifest,dict),"Manifest must be an object.")
 require(manifest.get("schema")=="hi5central-managed-restore-v1","Wrong manifest schema.")
 require(manifest.get("deployment_kind")=="managed_fresh","Expected managed_fresh only.")
 require(manifest.get("tenant_seed_count")==0,"Fresh install must seed ZERO tenants.")
 require(manifest.get("release_rollout_paused") is True,"Generic release rollout MUST start paused.")
 sha=manifest.get("platform_git_sha")
 require(isinstance(sha,str) and SHA.fullmatch(sha),"Exact platform source SHA (40 lowercase hex) required.")
 images=manifest.get("images")
 require(isinstance(images,dict) and set(images)==set(IMAGE_NAMES),
         "Image names must match ALL required application, workers, infrastructure and private pgAdmin services.")
 for key,name in images.items():
  require(isinstance(name,str) and IMAGE.fullmatch(name),
          "Unpinned, incomplete or noncanonical image for "+key)
  if key in ("api","itsm","rmm","admin","marketing","agent_deployment_assets",
             "release_planner","release_executor","protected_host_dispatcher"):
   require(name.startswith("ghcr.io/dansut24/"),
           "First-party image must be an approved Hi5Central GHCR artifact: "+key)
 native=manifest.get("native_artifacts")
 require(isinstance(native,dict) and set(native)==set(NATIVE_NAMES),
         "Complete Windows/Linux/macOS agents/viewers, mobile viewer and Avalonia artifacts are mandatory manifest entries.")
 for key,entry in native.items():
  require(isinstance(entry,dict),"Invalid artifact entry: "+key)
  require(entry.get("status")=="verified","Artifact must have passed publication verification: "+key)
  url=entry.get("url")
  require(isinstance(url,str) and HTTPS.fullmatch(url),
          "An HTTPS download URL is required for "+key)
  digest=entry.get("sha256")
  require(isinstance(digest,str) and HEXDIGEST.fullmatch(digest),
          "Immutable SHA256 required for "+key)
  require(entry.get("platform_git_sha")==sha,
          "Native artifact must be tied to exact Platform SHA: "+key)
 approvals=manifest.get("approvals")
 require(isinstance(approvals,dict),"Missing human approval object.")
 for k in ("platform_release_review","managed_infrastructure_review",
           "host_dispatcher_security_review"):
  ref=approvals.get(k)
  require(isinstance(ref,str) and len(ref)>=12 and len(ref)<=400,
          "Missing explicit independent review reference: "+k)
 require(manifest.get("catalogue_seed_policy")=="global_only",
         "Only preserved GLOBAL software catalogue/vendor sources may be seeded.")
 require(manifest.get("externals_optional") is True,
         "Third-party SMTP/Stripe/TURN proof/external Windows qualifier must be configurable later.")
 return {
  "platform_git_sha":sha,
  "images":len(images),
  "native_artifacts":len(native),
  "tenant_seed_count":0,
  "rollout_paused":True,
  "validated_metadata_only":True,
 }

def main():
 ap=argparse.ArgumentParser(description=__doc__)
 ap.add_argument("manifest",type=Path)
 ap.add_argument("--quiet",action="store_true")
 args=ap.parse_args()
 p=args.manifest
 if not p.is_file() or p.is_symlink() or p.stat().st_size>128*1024:
  raise ValueError("Manifest must be an ordinary regular file <128 KiB.")
 report=validate(json.loads(p.read_text(encoding="utf-8")))
 if not args.quiet:
  print("PASS: complete digest-pinned managed restore declaration checked.")
  print("Platform SHA:",report["platform_git_sha"])
  print("Images:",report["images"],"Native artifacts:",report["native_artifacts"])
  print("Tenants: 0; release rollout paused: true")
  print("NOTE: This validates local declarations, NOT image/URL availability or signatures.")
if __name__=="__main__":
 try: main()
 except (ValueError,OSError,UnicodeError,json.JSONDecodeError) as exc:
  print("BLOCKED: "+str(exc),file=sys.stderr)
  sys.exit(3)
