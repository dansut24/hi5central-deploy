#!/usr/bin/env bash
# Encrypt a verified recovery archive using the OFF-VPS owner public age key.
# Upload to private versioned S3-compatible object storage; download to verify.
# No Docker, database, gateway or service writes. Never put secrets in GitHub.
set -Eeuo pipefail
set +x
umask 077
usage() {
 cat <<'EOF'
Usage:
 sudo scripts/upload-managed-recovery.sh \
  --archive /secure/hi5central-catalogue-recovery-20261017.tar.gz \
  --recipient age1PUBLICRECIPIENT --s3-uri s3://private-bucket/backups/h5c/ \
  [--endpoint-url https://private-s3-provider] --dry-run|--upload

Requirements for --upload: root, age and configured AWS CLI v2 with S3
read+write access. Create/store private age key OFF THE VPS. Only public
age recipient belongs on this machine. Confirm bucket versioning/retention
separately. No source repository should contain this archive.
EOF
}
action=""; archive=""; recipient=""; uri=""; endpoint=""
while (($#));do
 case "$1" in
 --archive|--recipient|--s3-uri|--endpoint-url)
  (($#>=2)) || { echo "Missing argument to $1" >&2;exit 2; }
  case "$1" in
  --archive) archive="$2";;
  --recipient) recipient="$2";;
  --s3-uri) uri="$2";;
  --endpoint-url) endpoint="$2";;
  esac
  shift 2;;
 --dry-run|--upload)
  [[ -z "$action" ]] || { echo "Choose one action." >&2;exit 2; }
  action="$1";shift;;
 --help|-h) usage;exit 0;;
 *) echo "Unknown argument: $1" >&2;exit 2;;
 esac
done
[[ -n "$action" && -n "$archive" && -n "$recipient" && -n "$uri" ]] || {
 usage >&2;exit 2;
}
[[ "$archive" == /* && "$archive" == *.tar.gz && -f "$archive" && ! -L "$archive" ]] || {
 echo "Expected an absolute, regular, nonsymlink .tar.gz recovery bundle." >&2;exit 3;
}
[[ "$recipient" =~ ^age1[a-z0-9]{30,100}$ ]] || {
 echo "Expected PUBLIC age1 recipient, not a private decryption key." >&2;exit 3;
}
[[ "$uri" =~ ^s3://[a-z0-9][a-z0-9.-]{2,62}/[A-Za-z0-9/_-]+/$ ]] || {
 echo "Expected s3://private-bucket/nonempty-prefix/ (trailing slash)." >&2;exit 3;
}
if [[ -n "$endpoint" && ! "$endpoint" =~ ^https://[A-Za-z0-9.-]+(:[0-9]{2,5})?$ ]];then
 echo "Custom S3 endpoint must be HTTPS hostname without credentials/path." >&2
 exit 3
fi
[[ "$(stat -c '%a' "$archive")" == 600 ]] || {
 echo "Private plaintext archive must be 0600." >&2;exit 3;
}
[[ "$(stat -c '%s' "$archive")" -gt 2000 ]] || {
 echo "Recovery archive unexpectedly small." >&2;exit 3;
}
members="$(tar -tzf "$archive")" || {
 echo "Recovery archive invalid." >&2;exit 3;
}
grep -Fxq 'SHA256SUMS.txt' <<<"$members" || {
 echo "Missing checksum manifest." >&2;exit 3;
}
grep -Eq '^global-software-seed-[0-9TZ]+[.]tar[.]gz$' <<<"$members" || {
 echo "Missing importer-compatible catalogue archive." >&2;exit 3;
}
echo "PASS: root-only recovery archive format validated."
echo "Source SHA256: $(sha256sum "$archive" | cut -d' ' -f1)"
if [[ "$action" == --dry-run ]];then
 echo "DRY RUN: no credentials read, no encryption/upload/network requests."
 exit 0
fi
[[ "$(id -u)" -eq 0 ]] || { echo "Upload requires root." >&2;exit 3; }
for binary in age aws sha256sum;do
 command -v "$binary" >/dev/null || {
  echo "Missing tool $binary; install before offsite upload." >&2;exit 3;
 }
done
receipt="$(dirname "$archive")/$(basename "$archive").offsite-receipt.txt"
[[ ! -e "$receipt" && ! -L "$receipt" ]] || {
 echo "Existing receipt must be retained; refusing to overwrite." >&2;exit 3;
}
scratch="$(mktemp -d)"
chmod 700 "$scratch"
trap 'rm -rf -- "$scratch"' EXIT
encrypted="$scratch/recovery.tar.gz.age"
retrieved="$scratch/verified-roundtrip.age"
age -r "$recipient" -o "$encrypted" "$archive" >/dev/null
chmod 600 "$encrypted"
encrypted_sha="$(sha256sum "$encrypted" | cut -d' ' -f1)"
remote="$uri$(basename "$archive").age"
s3_cp() {
 if [[ -n "$endpoint" ]];then
  aws --endpoint-url "$endpoint" s3 cp "$@"
 else
  aws s3 cp "$@"
 fi
}
s3_cp "$encrypted" "$remote" --only-show-errors --no-progress --sse AES256
s3_cp "$remote" "$retrieved" --only-show-errors --no-progress
download_sha="$(sha256sum "$retrieved" | cut -d' ' -f1)"
[[ "$download_sha" == "$encrypted_sha" ]] || {
 echo "OFFSITE VERIFICATION FAILED: downloaded encrypted bytes do not match." >&2;exit 3;
}
{
 echo "format=hi5central-offsite-recovery-v1"
 echo "verified_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
 echo "plain_sha256=$(sha256sum "$archive" | cut -d' ' -f1)"
 echo "encrypted_sha256=$encrypted_sha"
 echo "remote_object=$remote"
 echo "recipient=$recipient"
 echo "encrypted_download_roundtrip_pass=true"
 echo "owner_offline_private_key_verified=false"
 echo "bucket_versioning_and_retention_independently_verified=false"
} > "$receipt"
chmod 600 "$receipt"
echo "PASS: encrypted recovery uploaded and round-trip download SHA256 verified."
echo "Receipt: $receipt"
echo "RESET STILL BLOCKED until offline private-key decryption is tested."
