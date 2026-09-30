# Hi5Central Deploy

Canonical Docker Compose deployment for managed and self-hosted Hi5Central.

The stack includes:

- PostgreSQL 17
- Redis 8
- Hi5Central Control Server
- ITSM + browser Self Service
- RMM
- Admin
- coturn
- Caddy gateway
- persistent Docker volumes
- automatic database migrations

Native endpoint applications such as the Agent, Viewer and App Portal are not Docker services.

## One-run self-host installation

On a clean Linux host with Docker Engine and Docker Compose v2 installed:

```sh
git clone https://github.com/dansut24/hi5central-deploy.git
cd hi5central-deploy
./install.sh --domain example.com --email admin@example.com
```

The installer:

1. validates Docker/Compose;
2. generates PostgreSQL and Redis credentials;
3. generates the MFA, RMM recovery and Connect encryption/HMAC keys;
4. generates the coturn shared secret and Docker-managed Caddy/TURN runtime configuration;
5. writes a locked-down `.env`;
6. validates the full Compose configuration;
7. pulls the configured Hi5Central images;
8. starts PostgreSQL and Redis;
9. applies all database migrations;
10. starts Control Server, ITSM, RMM, Admin, coturn and Caddy;
11. waits for application health checks;
12. verifies the database schema and prints the resulting URLs.

No external PostgreSQL or Redis installation is required.

By default all products are installed. To install a subset:

```sh
./install.sh --domain example.com --products itsm,rmm
```

For an internal/LAN deployment where TLS is terminated elsewhere:

```sh
./install.sh --domain hi5.internal --http
```

Use `--configure-only` to generate the configuration without starting containers.

### Non-interactive automation

The same installer can be fully automated:

```sh
HI5_ROOT_DOMAIN=hi5.example.com \
HI5_ACME_EMAIL=admin@example.com \
HI5_PRODUCTS=itsm,rmm,admin \
./install.sh
```

Advanced settings such as images, SMTP, Microsoft identity and host ports can be supplied with the documented `HI5_*` environment variables in `scripts/install.sh`.

## DNS and firewall

For the default HTTPS deployment, point these names at the self-host server:

- `itsm.<domain>`
- `rmm.<domain>`
- `admin.<domain>`
- `api.<domain>`
- `downloads.<domain>`
- `turn.<domain>`

Allow TCP 80/443, UDP 443, TURN TCP/UDP 3478 and UDP 49160-49200.

The gateway and TURN host ports can be overridden with `GATEWAY_HTTP_PORT`, `GATEWAY_HTTPS_PORT`, `TURN_LISTEN_PORT`, `TURN_RELAY_MIN_PORT` and `TURN_RELAY_MAX_PORT`.

## Existing installations

- `./scripts/up.sh` validates and starts an already configured deployment.
- `./scripts/update.sh` pulls configured images, recreates services and prunes unused images.
- `./scripts/down.sh` stops the stack without deleting persistent volumes.
- `./scripts/validate.sh` validates secrets and the Compose model.

Back up `.env` and the persistent Docker volumes before upgrades. Caddy/TURN runtime configuration is regenerated into Docker-managed volumes and does not require host-file bind mounts.

## Disposable integration smoke test

`./scripts/smoke-local.sh` creates a disposable Compose project with fresh PostgreSQL and Redis volumes, applies every migration, starts Control Server + ITSM + RMM + Admin, verifies health and schema, then removes the disposable stack.

See `PUBLISHING.md` for the canonical repository and artifact map.