# Stripe sandbox webhook — guarded Test gateway preparation

This change supports the **Hi5Central Stripe test sandbox only**. It does **not** deploy, restart, edit a Docker volume, update Production routing, enable live Stripe transactions or add a Stripe webhook destination.

## Why the gateway cannot be edited directly

On `hi5central-prod-01`, the existing `hi5central-test-gateway` receives a **read-only** `/etc/caddy` named-volume mount from the `hi5central-deploy` release operator. This mount is an intentional security boundary. The operator's existing `config-init` is the intended writer to that volume. Its current Caddy generator would overwrite newer pilot routes including the current `testing-test.hi5central.com` API/web SHA-pinned pool and Test AI Assist route; therefore **do not run the normal release operator Test recreate, config-init, reset or `down -v`** to install a Stripe route.

## Guarded review workflow

The render-only script `scripts/prepare-stripe-test-gateway-candidate.sh` requires:

- `HI5_STRIPE_TEST_GATEWAY_PREFLIGHT=render-only`
- `RUNTIME_ENVIRONMENT=test`
- `COMPOSE_PROJECT_NAME=hi5central-test`
- Original Caddyfile with a unique `http://testing-test.hi5central.com` stanza, the expected `@testReleaseApi` selector, and the exact previously accepted API upstream `hi5pool-test-unified-acd8e2c2-api:3001`.
- A **new output filename**; refuses to overwrite the original or any prior output.

It generates a candidate inserting **only** an exact-method and exact-path `POST /api/platform/v1/billing/stripe/webhook` handler to `stripeqa-api:3001`, before the catchall Test API handler. Every other route is preserved byte-for-byte (aside from the insertion). Fail closed on unknown SHA pool route, duplicate host, duplicate Stripe section, wrong project/environment or prior output.

Example on an isolated copy of the current config:

~~~sh
HI5_STRIPE_TEST_GATEWAY_PREFLIGHT=render-only \
RUNTIME_ENVIRONMENT=test COMPOSE_PROJECT_NAME=hi5central-test \
sh scripts/prepare-stripe-test-gateway-candidate.sh \
  ./Caddyfile.before-stripe ./Caddyfile.stripe-candidate
~~~

The GitHub Actions `Stripe Test Gateway Preflight` job verifies the output is purely additive, rejects unsafe invocations, and validates the candidate with Caddy.

## Explicitly blocked until approved gateway rollout

- Do **not** copy the candidate into the running gateway's read-only path, write its named volume from a helper container, change public Production Caddy routing, or invoke the release operator's broad Test reset.
- First reconcile the Test gateway's persisted declarative startup source with **all** currently active existing Test pilot routes, not just Stripe. Review the effective-diff and stage a gateway-only update through the approved release process, including a verified startup/restart persistence test and an immediate rollback procedure.
- After the dedicated Test route is verified publicly (invalid signature returns 400 with the Test pilot marker; rest of workspace unchanged), create a Stripe **test-mode only** endpoint and provision the real `whsec_` to the isolated API through the secret manager. The synthetic HMAC secret used for local QA must not be used to register Stripe.
- Verify real Stripe-signed delivery and replay protection in the isolated PostgreSQL ledger. Never attach synthetic customers to real tenants automatically and never enable Production billing.

Pilot evidence on host: `/opt/hi5central/deployment/pilots/stripe-sandbox-20261013/QA-STATUS-20261013.md`. Application work: `dansut24/Hi5Central-Platform` PR #64.
