"""Verify the new global owner password hash exactly matches API scrypt format."""
import base64
import hmac
import hashlib
import importlib.util
from pathlib import Path
import sys
import unittest

MODULE=Path(__file__).resolve().parents[1]/"scripts/bootstrap-managed-platform-owner.py"
spec=importlib.util.spec_from_file_location("managed_owner_bootstrap",MODULE)
bootstrap=importlib.util.module_from_spec(spec)
spec.loader.exec_module(bootstrap)

def check(encoded,password):
 parts=encoded.strip().split("$")
 if len(parts)!=6: return False
 scheme,n,r,p,salt,expected=parts
 if (scheme,n,r,p)!=("scrypt","16384","8","1"): return False
 pad=lambda s:s+"="*((-len(s))%4)
 try:
  salt_bytes=base64.urlsafe_b64decode(pad(salt))
  expected_bytes=base64.urlsafe_b64decode(pad(expected))
  result=hashlib.scrypt(password.encode(),salt=salt_bytes,
                       n=16384,r=8,p=1,dklen=64,maxmem=64*1024*1024)
  return hmac.compare_digest(result,expected_bytes)
 except (ValueError,TypeError):return False

class OwnerPasswordTest(unittest.TestCase):
 def test_password_format_and_verification(self):
  encoded=bootstrap.encoded_password("A-clean-generated-owner-credential-with-ample-length")
  self.assertTrue(check(encoded,"A-clean-generated-owner-credential-with-ample-length"))
  self.assertFalse(check(encoded,"wrong"))
  self.assertTrue(encoded.startswith("scrypt$16384$8$1$"))
 def test_salt_is_unique(self):
  p="Some lengthy new owner credential never exposed to API logs"
  self.assertNotEqual(bootstrap.encoded_password(p),bootstrap.encoded_password(p))

if __name__=="__main__":
 if len(sys.argv)==3:
  h=Path(sys.argv[1]).read_text().strip()
  password=Path(sys.argv[2]).read_text().strip()
  if not check(h,password):raise SystemExit("FAIL: real database owner hash/password mismatch")
  print("PASS: Platform-compatible scrypt owner password verified.")
 else:unittest.main()
