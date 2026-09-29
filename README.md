# Hi5Central Deploy

Canonical Docker Compose and gateway configuration for managed and self-hosted Hi5Central.

Server components:
- PostgreSQL 17
- Redis 8
- Hi5Central Control Server
- Hi5Central ITSM + browser Self Service
- Hi5Central RMM
- Hi5Central Admin
- coturn
- Caddy gateway

Native endpoint applications (Agent, Viewer and App Portal) are not Docker services.

Only the migrate service, using the Control Server image, applies database migrations.

Start by copying .env.example to .env, setting strong secrets, creating the TURN secret/config files, then running docker compose pull and docker compose up -d.

Pin all Hi5Central image variables to immutable release tags for production.

## Local integration smoke test

After building the four server images locally as:

- hi5central-control-server:extract-test
- hi5central-itsm:extract-test
- hi5central-rmm:extract-test
- hi5central-admin:extract-test

run:

    ./scripts/smoke-local.sh

The script creates a disposable Compose project with fresh PostgreSQL and Redis volumes, runs every Control Server migration, starts Control Server + ITSM + RMM + Admin, checks all health endpoints/product titles and confirms the migrated schema. It then removes the disposable containers, volumes and network automatically.

See PUBLISHING.md for the canonical repository and artifact map.
