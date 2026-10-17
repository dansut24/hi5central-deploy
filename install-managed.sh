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
NATIVE_SOURCE=""
RECOVERY_BUNDLE=""
usage(){
 cat <<'EOF'
Usage:
  sudo ./install-managed.sh --dry-run --admin-email ADMIN@DOMAIN
  sudo ./install-managed.sh --prepare --admin-email ADMIN@DOMAIN
  sudo ./install-managed.sh --verify-secrets
  ./install-managed.sh --check-manifest --manifest PATH
  sudo ./install-managed.sh --fresh-host-preflight
  sudo ./install-managed.sh --render-core --manifest /private/reviewed-release.json
  sudo ./install-managed.sh --verify-core-compose
  sudo ./install-managed.sh --bootstrap-owner
  sudo ./install-managed.sh --stage-native-assets --manifest FILE --native-source-dir DIR
  ./install-managed.sh --preflight-install --manifest FILE --catalogue SEED \
    --native-source-dir DIR --recovery-bundle BUNDLE
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
 --dry-run|--prepare|--verify-secrets|--check-manifest|--fresh-host-preflight|--render-core|--verify-core-compose|--bootstrap-owner|--stage-native-assets|--preflight-install|--install)
   if [[ -n "$ACTION" ]];then echo "Choose exactly one action." >&2;exit 2;fi
   ACTION="$1";shift;;
 --admin-email) ADMIN_EMAIL="$2";shift 2;;
 --root-domain) DOMAIN="$2";shift 2;;
 --catalogue) CATALOGUE="$2";shift 2;;
 --manifest) MANIFEST="$2";shift 2;;
 --native-source-dir) NATIVE_SOURCE="$2";shift 2;;
 --recovery-bundle) RECOVERY_BUNDLE="$2";shift 2;;
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
 --fresh-host-preflight)
  python3 "$ROOT_DIR/scripts/check-managed-fresh-host.py"
  ;;
 --render-core)
  [[ $EUID -eq 0 ]] || { echo "Run as root." >&2;exit 1;}
  [[ -n "$MANIFEST" ]] || { echo "--manifest FILE required." >&2;exit 2;}
  python3 "$ROOT_DIR/scripts/check-managed-fresh-host.py"
  python3 "$ROOT_DIR/scripts/prepare-managed-secrets.py" --root "$SECRET_DIR" --verify
  python3 "$ROOT_DIR/scripts/render-managed-runtime.py"     --root "$SECRET_DIR" --manifest "$MANIFEST" --apply
  echo "CORE CONFIG PREPARED — no containers started, installer NOT ready."
  ;;
 --verify-core-compose)
  [[ -r "$SECRET_DIR/managed-runtime.env" ]] || {
   echo "Private managed-runtime.env missing; run --render-core on fresh VPS." >&2; exit 3;
  }
  command -v docker >/dev/null || { echo "Docker Compose required." >&2;exit 3;}
  docker compose -f "$ROOT_DIR/compose.managed-core.yml"     -f "$ROOT_DIR/compose.pgadmin-private.yml"     --env-file "$SECRET_DIR/managed-runtime.env"     --profile itsm --profile rmm --profile admin --profile database-browser     config --quiet
  echo "PASS: managed core Compose configuration is structurally valid."
  echo "No services started; does not prove readiness for IONOS reset."
  ;;
 --bootstrap-owner)
  [[ $EUID -eq 0 ]] || { echo "Run as root on disposable fresh managed installation." >&2;exit 1;}
  python3 "$ROOT_DIR/scripts/prepare-managed-secrets.py" --root "$SECRET_DIR" --verify
  python3 "$ROOT_DIR/scripts/bootstrap-managed-platform-owner.py" --root "$SECRET_DIR" --apply
  echo "Owner bootstrap complete; core installation and MFA verification still required."
  ;;
 --stage-native-assets)
  [[ $EUID -eq 0 ]] || { echo "Run as root on the fresh Ubuntu VPS." >&2;exit 1;}
  [[ -n "$MANIFEST" && -n "$NATIVE_SOURCE" ]] || {
    echo "--manifest FILE and --native-source-dir DIR are required." >&2;exit 2;
  }
  python3 "$ROOT_DIR/scripts/check-managed-fresh-host.py"
  python3 "$ROOT_DIR/scripts/stage-managed-native-artifacts.py" \
    --manifest "$MANIFEST" --source-dir "$NATIVE_SOURCE" \
    --destination /var/lib/hi5central/native-downloads --apply
  echo "Native assets staged; not evidence of complete app startup."
  ;;
 --preflight-install)
  [[ -n "$MANIFEST" && -n "$CATALOGUE" && -n "$NATIVE_SOURCE" && -n "$RECOVERY_BUNDLE" ]] || {
    echo "Require --manifest, --catalogue, --native-source-dir and --recovery-bundle." >&2
    exit 2
  }
  python3 "$ROOT_DIR/scripts/verify-managed-reset-inputs.py" \
    --manifest "$MANIFEST" --catalogue "$CATALOGUE" \
    --native-source-dir "$NATIVE_SOURCE" --recovery-bundle "$RECOVERY_BUNDLE"
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
