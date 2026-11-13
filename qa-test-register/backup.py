#!/usr/bin/env python3
"""Online SQLite backup for the original VPS Hi5Central QA portal."""
import fcntl
import hashlib
import os
import sqlite3
import sys
from datetime import datetime, timezone, timedelta
from pathlib import Path

SOURCE=Path("/opt/hi5central/runtime/qa-register/data/tests.sqlite3")
ROOT=Path("/opt/hi5central/recovery/qa-register")
os.umask(0o077)
ROOT.mkdir(mode=0o700,parents=True,exist_ok=True)
with (ROOT/".backup.lock").open("w") as lock:
    try: fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
    except BlockingIOError: sys.exit("BACKUP_SKIPPED another QA backup is running")
    if not SOURCE.is_file(): sys.exit("BACKUP_FAILED source database missing")
    ts=datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    staging=ROOT/("."+ts+".part")
    final=ROOT/("qa-register-"+ts+".sqlite3")
    try:
        with sqlite3.connect(f"file:{SOURCE}?mode=ro",uri=True,timeout=10) as src:
            with sqlite3.connect(staging,timeout=10) as dst:
                src.backup(dst,pages=100,sleep=0.05)
        with sqlite3.connect(f"file:{staging}?mode=ro",uri=True) as check:
            result=check.execute("PRAGMA integrity_check").fetchone()[0]
            count=check.execute("SELECT COUNT(*) FROM tests").fetchone()[0]
            if result!="ok" or count<218: raise RuntimeError("integrity failure or missing rows")
        os.chmod(staging,0o600)
        staging.rename(final)
        digest=hashlib.sha256(final.read_bytes()).hexdigest()
        print("BACKUP_COMPLETE "+str(final)+" tests="+str(count)+" sha256="+digest,flush=True)
    finally:
        staging.unlink(missing_ok=True)
        Path(str(staging)+"-wal").unlink(missing_ok=True)
        Path(str(staging)+"-shm").unlink(missing_ok=True)
    cutoff=datetime.now(timezone.utc)-timedelta(days=30)
    for item in ROOT.glob("qa-register-*.sqlite3"):
        try:
            recorded=datetime.strptime(item.stem.replace("qa-register-",""),"%Y%m%dT%H%M%SZ").replace(tzinfo=timezone.utc)
            if recorded<cutoff:item.unlink()
        except ValueError:continue
