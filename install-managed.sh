#!/usr/bin/env bash
# Hi5Central one-command managed restore entrypoint (under development).
# SAFE TODAY: --dry-run, --prepare, --verify-secrets only.
# --install deliberately fails closed until all managed services are certified.
# IONOS VPS reset is done manually by owner. No reset/wipe logic in installer.
set -Eeuo pipefail
set +x
ROOT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
SECRET_DIR="$(printenv HI5_MANAGED_SECRET_DIR || true)"
SECRET_DIR="$(printf '%s' "$SECRET_DIR")"
if [[ -z "$SECRET_DIR" ]];then SECRET_DIR="/etc/hi5central/managed";fi
DOMAIN="hi5central.com"
ADMIN_EMAIL=""
ACTION=""
CATALOGUE=""
MANIFEST=""
usage(){
 cat <<'EOF'
Usage:
  sudo ./install-managed.sh --dry-run --admin-email ADMIN@DOMAIN
  sudo ./install-managed.sh --prepare --admin-email ADMIN@DOMAIN
  sudo ./install-managed.sh --verify-secrets
  ./install-managed.sh --check-manifest --manifest PATH
  sudo ./install-managed.sh --install --admin-email ADMIN@DOMAIN --catalogue PATH

STATUS: Only non-deploying preflight and secret preparation are implemented so far.
       --install intentionally fails closed until full managed restore passes CI.
       Owner resets IONOS VPS manually; this script never wipes the server.

Ultimate --install contract:
  - verify fresh Ubuntu VPS and approved immutable images
  - install/configure Docker, PostgreSQL, Redis, marketing/signup, ITSM/Portal,
    RMM/Control, Admin, Dev, Caddy/TURN, qualification API, downloads
  - generate all new Hi5Central-owned passwords, credentials and signing keys
  - validate and import global software catalogue + vendor sources
  - install private pgAdmin with independent full-DML database editor login
  - apply reviewed migrations, seed ZERO tenants, global rollout PAUSED
  - install stage-restricted release workers and fenced host deploy service
  - verify core smoke, backup/restore, restart and idempotency
  - external SMTP, Stripe, DNS/TURN, qualification agent, code signing
    may be configured later or marked NOT CONFIGURED
EOF
}
while (($#));do
 case "$1" in
 --dry-run|--prepare|--verify-secrets|--check-manifest|--install)
   if [[ -n "$ACTION" ]];then echo "Choose exactly one action." >&2;exit 2;fi
   ACTION="$1";shift;;
 --admin-email) ADMIN_EMAIL="$2";shift 2;;
 --root-domain) DOMAIN="$2";shift 2;;
 --catalogue) CATALOGUE="$2";shift 2;;
 --manifest) MANIFEST="$2";shift 2;;
 --secret-dir) SECRET_DIR="$2";shift 2;;
 --help|-h) usage;exit 0;;
 *) echo "Unknown option: $1" >&2;usage >&2;exit 2;;
 esac
done
[[ -n "$ACTION" ]] || { usage >&2;exit 2;}
command -v python3 >/dev/null || { echo "Python3 required." >&2;exit 1;}
case "$ACTION" in
 --dry-run)
  if [[ -n "$MANIFEST" ]];then
    python3 "$ROOT_DIR/scripts/validate-managed-image-manifest.py" "$MANIFEST"
  fi
  python3 "$ROOT_DIR/scripts/prepare-managed-secrets.py" \
    --root "$SECRET_DIR" --root-domain "$DOMAIN" \
    --admin-email "$ADMIN_EMAIL" --dry-run
  echo "DRY RUN: Full cloud installation is not yet implemented."
  ;;
 --prepare)
  [[ $EUID -eq 0 ]] || { echo "Run as root." >&2;exit 1;}
  if command -v docker >/dev/null && docker inspect hi5central-postgres >/dev/null 2>&1;then
    echo "REFUSED: old Production PostgreSQL is still present. Do not prepare a new restore on the existing VPS." >&2
    exit 3
  fi
  python3 "$ROOT_DIR/scripts/prepare-managed-secrets.py" \
    --root "$SECRET_DIR" --root-domain "$DOMAIN" --admin-email "$ADMIN_EMAIL"
  ;;
 --verify-secrets)
  python3 "$ROOT_DIR/scripts/prepare-managed-secrets.py" --root "$SECRET_DIR" --verify
  ;;
 --check-manifest)
  [[ -n "$MANIFEST" ]] || { echo "--manifest FILE is required." >&2; exit 2; }
  python3 "$ROOT_DIR/scripts/validate-managed-image-manifest.py" "$MANIFEST"
  ;;
 --install)
  echo "BLOCKED: full Hi5Central managed installer is NOT READY." >&2
  echo "Missing: complete routed Compose and protected release workers, approved image manifest," >&2
  echo "catalogue import and private pgAdmin integration on disposable fresh DB," >&2
  echo "full reset/recovery/core smoke tests. No changes performed." >&2
  echo "Do NOT reset the IONOS VPS on the basis of this branch." >&2
  exit 3
  ;;
esac
