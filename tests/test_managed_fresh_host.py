"""Ensure the IONOS fresh-server preflight cannot accept occupied hosts."""
import importlib.util
from pathlib import Path
import unittest
p=Path(__file__).resolve().parents[1]/"scripts/check-managed-fresh-host.py"
spec=importlib.util.spec_from_file_location("host_preflight",p)
m=importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
def probe(**kw):
 args={"os_release":{"ID":"ubuntu","VERSION_ID":"26.04"},
       "architecture":"x86_64","ram_bytes":8*1024**3,
       "disk_free_bytes":80*1024**3,"existing_containers":[],"is_root":True}
 args.update(kw)
 return m.check_host(**args)[0]
class HostPreflight(unittest.TestCase):
 def test_fresh_ionos_ubuntu_ready(self):
  self.assertEqual(probe(),[])
 def test_old_hi5central_never_allowed(self):
  self.assertTrue(probe(existing_containers=["hi5central-postgres"]))
 def test_no_existing_docker_fleet_at_all(self):
  self.assertTrue(probe(existing_containers=["other-customer-db"]))
 def test_unsupported_os_denied(self):
  self.assertTrue(probe(os_release={"ID":"debian","VERSION_ID":"12"}))
  self.assertTrue(probe(os_release={"ID":"ubuntu","VERSION_ID":"22.04"}))
 def test_low_ram_or_disk_denied(self):
  self.assertTrue(probe(ram_bytes=4*1024**3))
  self.assertTrue(probe(disk_free_bytes=10*1024**3))
 def test_non_root_denied(self):
  self.assertTrue(probe(is_root=False))
if __name__=="__main__":unittest.main()
