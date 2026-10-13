#!/bin/sh
# Render-only Caddy Test pilot overlay. This script deliberately cannot deploy or
# modify the source file or a running container's read-only Caddy mount.
set -eu
umask 077

usage() {
  echo "Usage: $0 <existing-Test-Caddyfile> <new-candidate-Caddyfile>" >&2
  exit 2
}

[ "$#" -eq 2 ] || usage
SOURCE=$1
DEST=$2
[ "${HI5_STRIPE_TEST_GATEWAY_PREFLIGHT:-}" = "render-only" ] ||
  { echo "Explicit render-only opt-in required." >&2; exit 3; }
[ "${RUNTIME_ENVIRONMENT:-}" = "test" ] ||
  { echo "Only the Test runtime is permitted." >&2; exit 3; }
[ "${COMPOSE_PROJECT_NAME:-}" = "hi5central-test" ] ||
  { echo "Only the hi5central-test project is permitted." >&2; exit 3; }
[ -f "$SOURCE" ] && [ -s "$SOURCE" ] && [ ! -L "$SOURCE" ] ||
  { echo "Expected an existing non-symlink Caddyfile." >&2; exit 3; }
[ ! -e "$DEST" ] && [ ! -L "$DEST" ] ||
  { echo "Refusing to overwrite any existing output." >&2; exit 3; }

# Only the known Test pilot host, API selector and isolated upstream are allowed.
# The exact selector must be unique. Existing extra Test pilot routes are kept.
[ "$(grep -c '^http://testing-test\.hi5central\.com {$' "$SOURCE" || :)" -eq 1 ] ||
  { echo "Missing or duplicate exact Test pilot hostname." >&2; exit 4; }
[ "$(grep -Fc '    @testReleaseApi path /api/v1/* /api/*' "$SOURCE" || :)" -eq 1 ] ||
  { echo "Missing or duplicate pinned Test API selector." >&2; exit 4; }
[ "$(grep -c '^        reverse_proxy hi5pool-test-unified-acd8e2c2-api:3001$' "$SOURCE" || :)" -eq 1 ] ||
  { echo "Unknown Test pilot API upstream; review new build before proceeding." >&2; exit 4; }
if grep -qE 'HI5_STRIPE_SANDBOX_PILOT_(START|END)|@stripeSandboxWebhook|stripeqa-api:3001' "$SOURCE"; then
  echo "Existing Stripe pilot route detected; refusing double insertion." >&2
  exit 4
fi

TMP=$(mktemp "${DEST}.tmp.XXXXXX")
trap 'rm -f "$TMP"' EXIT HUP INT TERM

awk '
  $0 == "http://testing-test.hi5central.com {" { in_pilot=1; pilots++ }
  in_pilot && $0 == "    @testReleaseApi path /api/v1/* /api/*" {
    print "    # HI5_STRIPE_SANDBOX_PILOT_START"
    print "    @stripeSandboxWebhook {"
    print "        method POST"
    print "        path /api/platform/v1/billing/stripe/webhook"
    print "    }"
    print "    handle @stripeSandboxWebhook {"
    print "        header X-Hi5-Stripe-Sandbox-Test \"pilot\""
    print "        reverse_proxy stripeqa-api:3001"
    print "    }"
    print "    # HI5_STRIPE_SANDBOX_PILOT_END"
    inserted++
  }
  in_pilot && $0 == "}" { in_pilot=0 }
  { print }
  END { if (pilots != 1 || inserted != 1) exit 5 }
' "$SOURCE" > "$TMP"

# Verify pure additive change and that the two route markers are unique.
[ "$(grep -c '^    # HI5_STRIPE_SANDBOX_PILOT_START$' "$TMP" || :)" -eq 1 ]
[ "$(grep -c '^    # HI5_STRIPE_SANDBOX_PILOT_END$' "$TMP" || :)" -eq 1 ]
[ "$(grep -c '^        reverse_proxy stripeqa-api:3001$' "$TMP" || :)" -eq 1 ]

mv "$TMP" "$DEST"
chmod 600 "$DEST"
echo "Rendered isolated Test-only Caddy candidate: $DEST"
echo "No running gateway, Docker volume, environment file or Production route modified."
