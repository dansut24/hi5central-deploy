# Hi5Central QA Test Register

Internal, standalone web register: https://tests.hi5central.com

- 218 baseline tests in 17 product/platform areas
- Search, product/priority/status/method filters, totals and percentage progress
- Manually save status, notes, tester, environment and evidence per test
- Revision-safe concurrent edits, timeline of revisions, permanent SQLite storage
- CSV / JSON export. Original Pass and Smoke checked results retained from the audit
- Responsive desktop and mobile layout
- No automatic execution of tests (staff update outcomes with evidence)

## Original VPS deployment

All runtime files belong under /opt/hi5central/runtime/qa-register. Put
server.py, index.html, app.js, styles.css and seed.csv under app/, and
compose.yaml at the runtime root. Create data/ root-only, chown to 10001:10001.
Run docker compose -f /opt/hi5central/runtime/qa-register/compose.yaml up -d.

Caddy on the original VPS routes tests.hi5central.com to
hi5central-qa-test-register:8080 on the private hi5central-internal Docker network.
All public requests, including API and CSV/JSON exports, MUST pass HTTPS Basic
Auth. Store only a strong password hash in Caddy, never credentials in the repo.
Validate with caddy validate before reload. Do not touch the separate EU server.

The database is persistent. The application imports missing test IDs from the
tracked seed CSV on startup without overwriting previous test outcomes.

## Security and recovery

This is internal-only and for a single QA team. Never enter customer secrets or
personally identifying ticket data into the notes. Mutations require JSON and
an exact same-origin header. Container has no published ports, is unprivileged
and has read-only root filesystem.

An online SQLite backup is required for disaster recovery; an ordinary file
copy during WAL activity is NOT sufficient. Export CSV regularly until an
automated backup for the QA database is configured. Authentication via the
existing Admin SSO and per-reviewer identities is recommended before wider
staff rollout.
