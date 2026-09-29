#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

[ -f .env ] || { echo "Missing .env (copy .env.example)." >&2; exit 1; }
[ -s secrets/turn_shared_secret ] || { echo "Missing secrets/turn_shared_secret. Run scripts/generate-turn-config.sh." >&2; exit 1; }
[ -s secrets/turnserver.conf ] || { echo "Missing secrets/turnserver.conf. Run scripts/generate-turn-config.sh." >&2; exit 1; }

if grep -Eq '(^|=)(CHANGE_ME|64_HEX_CHARACTERS)$' .env; then
  echo "Placeholder secrets remain in .env." >&2
  exit 1
fi

MFA=$(awk -F= '$1=="MFA_ENCRYPTION_KEY"{print substr($0,index($0,"=")+1)}' .env | tail -1)
RMM=$(awk -F= '$1=="RMM_RECOVERY_KEY_ENCRYPTION_KEY"{print substr($0,index($0,"=")+1)}' .env | tail -1)

echo "$MFA" | grep -Eq '^[0-9a-fA-F]{64}$' || { echo "MFA_ENCRYPTION_KEY must be 64 hex characters." >&2; exit 1; }
echo "$RMM" | grep -Eq '^[0-9a-fA-F]{64}$' || { echo "RMM_RECOVERY_KEY_ENCRYPTION_KEY must be 64 hex characters." >&2; exit 1; }

docker compose config -q
echo "Hi5Central deployment configuration is valid."
