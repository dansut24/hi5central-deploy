#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

STRICT_DNS=${HI5_STRICT_DNS:-0}
SKIP_DNS=${HI5_SKIP_DNS_CHECK:-0}
PUBLIC_IP=${HI5_PUBLIC_IP:-}

usage() {
  cat <<'EOF'
Usage: ./scripts/preflight.sh [--strict-dns] [--public-ip IP] [--skip-dns]

Checks Docker, Compose, host resources, configured DNS and the generated
Hi5Central deployment model. It does not change the deployment.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --strict-dns) STRICT_DNS=1; shift ;;
    --public-ip) PUBLIC_IP=${2:?--public-ip requires a value}; shift 2 ;;
    --skip-dns) SKIP_DNS=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

command -v docker >/dev/null 2>&1 || { echo "FAIL Docker is not installed." >&2; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "FAIL Docker Compose v2 is not available." >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "FAIL Docker daemon is not reachable by this user." >&2; exit 1; }
[ -f .env ] || { echo "FAIL .env is missing. Run ./install.sh --configure-only first." >&2; exit 1; }

read_env() {
  awk -F= -v key="$1" '$1==key{print substr($0,index($0,"=")+1)}' .env | tail -1
}

docker compose config -q || { echo "FAIL Docker Compose configuration is invalid." >&2; exit 1; }

mem_kb=$(awk '/MemTotal:/{print $2}' /proc/meminfo 2>/dev/null || echo 0)
disk_kb=$(df -Pk . | awk 'NR==2{print $4}')
printf 'Docker:        %s\n' "$(docker --version | sed 's/,.*//')"
printf 'Compose:       %s\n' "$(docker compose version --short 2>/dev/null || docker compose version)"
[ "$mem_kb" -gt 0 ] && printf 'Memory:        %s GiB total\n' "$(awk -v kb="$mem_kb" 'BEGIN{printf "%.1f",kb/1024/1024}')"
[ -n "$disk_kb" ] && printf 'Disk free:     %s GiB\n' "$(awk -v kb="$disk_kb" 'BEGIN{printf "%.1f",kb/1024/1024}')"
if [ "$mem_kb" -gt 0 ] && [ "$mem_kb" -lt 4194304 ]; then
  echo "WARN Less than 4 GiB RAM detected. A full ITSM + RMM + Admin deployment may be constrained."
fi
if [ -n "$disk_kb" ] && [ "$disk_kb" -lt 20971520 ]; then
  echo "WARN Less than 20 GiB disk space is currently free."
fi

if [ "$SKIP_DNS" = 1 ]; then
  echo "DNS:           skipped"
  echo "Preflight passed."
  exit 0
fi

scheme=$(read_env APP_URL | sed -n 's#^\(https\?\)://.*#\1#p')
profiles=$(read_env COMPOSE_PROFILES)
hosts="$(read_env API_ADDRESS) $(read_env ITSM_ADDRESS) $(read_env DOWNLOADS_ADDRESS)"
case ",$profiles," in *,rmm,*) hosts="$hosts $(read_env RMM_ADDRESS) $(read_env TURN_HOST)" ;; esac
case ",$profiles," in *,admin,*) hosts="$hosts $(read_env ADMIN_ADDRESS)" ;; esac

# Address values may contain http:// in LAN mode.
clean_host() { printf '%s' "$1" | sed -e 's#^https\?://##' -e 's#[:/].*$##'; }
resolve_ipv4() {
  host=$1
  if command -v getent >/dev/null 2>&1; then
    getent ahostsv4 "$host" 2>/dev/null | awk '{print $1}' | sort -u
    return
  fi
  if command -v nslookup >/dev/null 2>&1; then
    nslookup "$host" 2>/dev/null | awk '/^Address: /{print $2}' | sort -u
    return
  fi
  return 1
}

failed=0
if [ "$scheme" = http ]; then
  echo "DNS:           informational (HTTP/LAN mode)"
fi
for raw in $hosts; do
  host=$(clean_host "$raw")
  [ -n "$host" ] || continue
  ips=$(resolve_ipv4 "$host" || true)
  if [ -z "$ips" ]; then
    echo "WARN DNS $host does not currently resolve."
    [ "$STRICT_DNS" = 1 ] && failed=1
    continue
  fi
  one_line=$(printf '%s\n' "$ips" | paste -sd, -)
  echo "DNS:           $host -> $one_line"
  if [ -n "$PUBLIC_IP" ] && ! printf '%s\n' "$ips" | grep -Fxq "$PUBLIC_IP"; then
    echo "WARN $host does not resolve to expected public IP $PUBLIC_IP."
    [ "$STRICT_DNS" = 1 ] && failed=1
  fi
done

if [ "$failed" = 1 ]; then
  echo "FAIL Strict DNS preflight failed." >&2
  exit 1
fi

echo "Preflight passed."
