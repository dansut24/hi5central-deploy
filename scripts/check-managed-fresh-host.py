#!/usr/bin/env python3
"""Read-only preflight for the IONOS machine AFTER its manual fresh Ubuntu reset.

No install, apt, Docker pull/run, disk formatting, network changes or DNS edits.
A non-fresh VPS must REFUSE clean installation, even with operator override.
"""
import argparse
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys

BANNED_NAMES=("hi5central-postgres","hi5central-web","hi5central-api",
              "hi5central-certified-release-planner","hi5central-release-executor-live")
MIN_RAM_BYTES=6*1024**3
MIN_FREE_BYTES=20*1024**3
def check_host(*,os_release,architecture,ram_bytes,disk_free_bytes,
               existing_containers=(),is_root=True):
 reasons=[]
 details=[]
 if os_release.get("ID")!="ubuntu":
  reasons.append("Expected fresh Ubuntu (ID=ubuntu).")
 version=os_release.get("VERSION_ID","")
 if version not in ("24.04","26.04"):
  reasons.append("Only reviewed Ubuntu 24.04 or 26.04 LTS is supported.")
 if architecture not in ("x86_64","aarch64"):
  reasons.append("Unsupported CPU architecture.")
 if ram_bytes<MIN_RAM_BYTES:
  reasons.append("At least 6 GiB physical RAM required.")
 if disk_free_bytes<MIN_FREE_BYTES:
  reasons.append("At least 20 GiB available disk space required.")
 if not is_root:
  reasons.append("Run as root on the fresh IONOS Ubuntu VPS.")
 names=list(existing_containers)
 if names:
  reasons.append("Existing containers found; fresh install must not modify an existing Docker fleet.")
 if any(name in names for name in BANNED_NAMES):
  reasons.append("Existing Hi5Central Production container detected.")
 return reasons,{"os":version,"arch":architecture,"physical_memory_bytes":ram_bytes,
                 "disk_free_bytes":disk_free_bytes,
                 "existing_container_count":len(names),
                 "fresh_vps_candidate":not reasons}
def read_os_release():
 vals={}
 for line in Path("/etc/os-release").read_text().splitlines():
  if "=" in line:
   k,v=line.split("=",1)
   vals[k]=v.strip().strip('"').strip("'")
 return vals
def available_ram():
 # MemTotal only, never SwapTotal; a stale swap percentage is not a substitute.
 for line in Path("/proc/meminfo").read_text().splitlines():
  if line.startswith("MemTotal:"):
   return int(line.split()[1])*1024
 raise ValueError("Cannot identify physical memory.")
def running_containers():
 if not shutil.which("docker"):
  return []
 result=subprocess.run(["docker","ps","-a","--format","{{.Names}}"],
                       capture_output=True,text=True,timeout=12)
 if result.returncode:
  raise ValueError("Docker is installed but fleet inventory cannot be verified. Refusing fresh installation.")
 return [s for s in result.stdout.splitlines() if s]
def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument("--json",action="store_true")
 args=p.parse_args()
 try:
  release=read_os_release()
  disk=shutil.disk_usage("/")
  reasons,report=check_host(os_release=release,
             architecture=platform.machine(),
             ram_bytes=available_ram(),disk_free_bytes=disk.free,
             existing_containers=running_containers(),is_root=os.geteuid()==0)
 except (ValueError,OSError,subprocess.TimeoutExpired) as e:
  reasons=[str(e)];report={"fresh_vps_candidate":False}
 if args.json:
  print(json.dumps({"pass":not reasons,"errors":reasons,**report},sort_keys=True))
 else:
  print("Fresh IONOS Ubuntu preflight:", "PASS" if not reasons else "BLOCKED")
  if "os" in report:
   print("OS:",report["os"],"CPU:",report["arch"],
         "RAM GiB:",round(report["physical_memory_bytes"]/1024**3,1),
         "Free GiB:",round(report["disk_free_bytes"]/1024**3,1))
  for reason in reasons:print("BLOCKED:",reason)
  print("Read-only inspection; no server changes.")
 if reasons:sys.exit(3)
if __name__=="__main__":main()
