# Hi5Central Deploy

Public deployment surface for Hi5Central managed and self-hosted installations.

Hi5Central application source code is maintained separately from this deployment repository. Self-hosters consume versioned runtime container images and signed native binaries; they do not need access to the application source repositories.

> Containerisation is distribution, not perfect anti-reverse-engineering. Production images are built without the raw Control Server source tree, but any software delivered to a customer can ultimately be inspected. Repository access, licences, signing and build/release controls remain part of the protection model.

## Editions

### Self-Hosted Standard — free

Standard is permanently free and does not require a licence key.

It is intended for an organisation managing its own environment and installs:

- PostgreSQL
- Redis
- Hi5Central Control Server / Hono API
- ITSM + browser Self Service
- RMM
- coturn
- Caddy gateway
- persistent Docker volumes and automatic migrations

Platform Admin is not installed or routed in Standard, and the API reports the installation as edition=standard with single-organisation entitlements.

### Self-Hosted MSP — paid

MSP uses the same application images but enables licensed MSP capabilities through a signed entitlement:

- multi-tenancy
- MSP / Platform Admin
- white-labelling entitlement
- customer portals and custom-domain entitlement
- licensed tenant/device/user limits

A licence is bound to an installation ID. The installed Control Server verifies Hi5Central-signed entitlements locally and periodically refreshes them. Normal requests do not depend on the licensing service being online.

The raw licence key is used for activation and is not written to the deployment .env. After activation, the database holds the key hash, the signed entitlement and an installation-bound refresh credential.

### Hi5Central Managed

Managed deployments are operated by Hi5Central and include Platform Admin/control-plane functionality. Managed Dev and Prod are separate Compose projects, data stores and image channels.

## One-run self-host installation

On a clean Linux host with Docker Engine and Docker Compose v2:

~~~sh
git clone https://github.com/dansut24/hi5central-deploy.git
cd hi5central-deploy
./install.sh --domain example.com --email admin@example.com
~~~

That defaults to the free Standard edition. It installs ITSM and RMM and does **not** install Admin.

Explicitly:

~~~sh
./install.sh \
  --edition standard \
  --domain example.com \
  --email admin@example.com
~~~

To install only one product:

~~~sh
./install.sh --edition standard --domain example.com --products itsm
~~~

For an internal/LAN deployment where TLS terminates elsewhere:

~~~sh
./install.sh --edition standard --domain hi5.internal --http
~~~
## MSP installation

A fresh MSP installation requires a Hi5Central MSP licence key:

~~~sh
./install.sh \
  --edition msp \
  --license-key 'hi5_msp_...' \
  --domain msp.example.com \
  --email admin@example.com
~~~

Interactive installs prompt for the key without echoing it. For automation, use HI5_LICENSE_KEY.

The installer starts the stack, waits for the API to become healthy and then activates the licence through /api/v1/system/license/activate. Existing licensed MSP installations can be restarted without supplying the original key because the refresh credential is already installation-bound.

The MSP signing public key is supplied as deployment trust configuration. The corresponding private signing key exists only in the Hi5Central managed licensing authority and must never be distributed to self-host installations.

## What the installer does

A full installation:

1. validates Docker and Docker Compose;
2. selects Standard or MSP;
3. validates the selected ITSM/RMM products;
4. generates PostgreSQL and Redis credentials;
5. generates MFA, RMM recovery and Connect encryption/HMAC material;
6. generates the coturn shared secret and runtime gateway configuration;
7. writes a mode-600 .env;
8. validates the Compose model and runs preflight;
9. pulls the configured Hi5Central runtime images;
10. starts isolated PostgreSQL and Redis services;
11. applies every database migration;
12. starts Control Server, selected web apps, coturn and Caddy;
13. waits for application health checks;
14. activates or verifies the MSP licence when required;
15. verifies database state and prints the resulting URLs.

No external PostgreSQL or Redis installation is required.

Use --configure-only to create and validate configuration without starting containers.

### Non-interactive Standard

~~~sh
HI5_ROOT_DOMAIN=hi5.example.com \
HI5_ACME_EMAIL=admin@example.com \
HI5_EDITION=standard \
HI5_PRODUCTS=itsm,rmm \
./install.sh
~~~

### Non-interactive MSP

~~~sh
HI5_ROOT_DOMAIN=msp.example.com \
HI5_ACME_EMAIL=admin@example.com \
HI5_EDITION=msp \
HI5_LICENSE_KEY='hi5_msp_...' \
HI5_PRODUCTS=itsm,rmm \
./install.sh
~~~

Advanced image, SMTP, Microsoft identity, networking and licensing settings can be supplied through the HI5_* variables documented by ./install.sh --help and scripts/install.sh.
## DNS and firewall

Standard self-hosting normally uses:

- itsm.<domain>
- rmm.<domain>
- api.<domain>
- downloads.<domain>
- turn.<domain>

MSP additionally uses:

- admin.<domain>

Allow TCP 80/443, TURN TCP/UDP 3478 and UDP 49160-49200 as appropriate for the host/network design.

The gateway and TURN host ports are configurable with GATEWAY_HTTP_PORT, GATEWAY_HTTPS_PORT, TURN_LISTEN_PORT, TURN_RELAY_MIN_PORT and TURN_RELAY_MAX_PORT.

## Managed Dev / Prod separation

Hi5Central development is intentionally separate from production.

Image channels:

- develop branch → :dev
- main branch → :prod and :latest
- release tags → versioned image tags
- every branch build also receives an immutable SHA tag

Managed environment templates live under:

~~~text
environments/dev.env.example
environments/test.env.example
environments/uat.env.example
environments/prod.env.example
~~~

The four environments have deliberately different responsibilities:

| Environment | Feature mode | Data | Image policy |
| --- | --- | --- | --- |
| Dev | all enabled | development | follows `:dev` |
| Test | all enabled | disposable test data | follows `:dev`; resettable |
| UAT | controlled | release-cycle test data | exact Test image digests |
| Live | controlled | production | exact UAT-tested image digests |

Create private runtime files from the templates and replace all placeholder secrets before startup. Real environment files are ignored by Git.

Use:

~~~sh
./scripts/environment.sh dev up
./scripts/environment.sh test up
./scripts/environment.sh uat up
./scripts/environment.sh prod update
~~~

Every environment uses a different `COMPOSE_PROJECT_NAME`, PostgreSQL/Redis volume set, private Docker network, gateway name and host/TURN port range.

Managed environments also load `compose.managed-edge.yml`. This joins only the managed gateway to the existing edge Docker network while application, PostgreSQL and Redis services remain isolated on the environment's private network.

### Release and promotion model

~~~text
feature work
    ↓
develop / :dev
    ↓
Dev integration
    ↓
Test — all registered features ON
    │     disposable data / Reset button
    │
    ├── Test result: Pass / Fail / Blocked
    ↓
select passed changes
    ↓
UAT — controlled feature switches
    │     exact Test image digests
    │
    ├── UAT result: Pass / Fail / Blocked
    ↓
tick UAT-passed feature-gated changes
    ↓
Push selected to Live
    ↓
Live — exact UAT image digests + selected flags ON
~~~

Release changes, test evidence, feature switches and promotion requests are stored in the managed Platform Admin control plane. Test must pass before UAT evidence is accepted. UAT must pass before a change can be selected for Live.

Selective Live promotion requires a registered feature flag. This is intentional: an unselected change may exist inside the same immutable candidate image, but it remains dormant until its Live feature switch is explicitly promoted.

The Hono API never receives the Docker socket. It only queues validated environment actions. A separate Hi5Central Release Operator claims those actions, resets the disposable Test project, captures exact registry digests from Test/UAT and deploys the target environment. Live execution is additionally blocked unless the operator is started with `LIVE_PROMOTION_ENABLED=1`.

Install the operator against the current managed control plane with:

~~~sh
./scripts/install-release-operator.sh dev
~~~

After the new managed Live control plane is cut over, reinstall it against Live with:

~~~sh
./scripts/install-release-operator.sh prod
~~~

The installer copies `test.env`, `uat.env`, the optional `prod.env`, and the operator credential into a dedicated Docker volume with restrictive permissions. The operator container alone receives the Docker socket. Before cutover, Live promotion remains disabled. At the controlled cutover, use `HI5_ENABLE_LIVE_PROMOTION=1` when reinstalling the operator.

Production is never updated directly from a mutable `:dev` image.

## Preflight

Run the non-destructive preflight:

~~~sh
./preflight.sh
~~~

For strict public DNS validation:

~~~sh
./preflight.sh --strict-dns --public-ip 203.0.113.10
~~~

The installer runs preflight automatically before startup. HI5_SKIP_PREFLIGHT=1 is intended only for controlled automation/CI where equivalent checks run elsewhere.
## Backup and restore

Create an application-aware backup:

~~~sh
./backup.sh
~~~

The protected archive under backups/ contains deployment configuration, a PostgreSQL logical dump and persistent Redis/download/App Portal/Caddy volume data. Treat it as a secret.

Restore with:

~~~sh
./restore.sh backups/hi5central-backup-YYYYMMDDTHHMMSSZ.tar.gz
~~~

Interactive restore requires typing RESTORE; automation can use --yes.

## Existing installations

- ./scripts/up.sh validates and starts the configured self-host stack.
- ./scripts/update.sh pulls configured images and recreates services.
- ./scripts/down.sh stops the stack without deleting persistent volumes.
- ./scripts/validate.sh validates secrets and Compose configuration.
- ./preflight.sh validates Docker, resources, DNS and configuration.
- ./backup.sh creates a protected application backup.
- ./restore.sh <archive> restores a backup.
- ./scripts/environment.sh <dev|prod> ... operates Hi5Central managed environments.

Back up .env and persistent volumes before upgrades.

## Disposable integration testing

./scripts/smoke-local.sh creates a disposable Compose project with fresh PostgreSQL and Redis volumes, applies every migration, starts the application services, verifies health/schema and removes the test stack afterward.

The deployment CI separately validates that Standard does not include admin-web and that MSP does.

## Source and artifact model

Recommended repository visibility:

- hi5central-control-server — **private**
- hi5central-itsm — **private**
- hi5central-rmm — **private**
- hi5central-admin — **private**
- hi5central-deploy — public
- native Agent/Viewer/App Portal source — private unless intentionally released otherwise

Runtime images intended for free self-hosting can be publicly pullable GHCR packages independently of source repository visibility.

The Control Server image is built as a multi-stage image. Raw /src is not copied into the runtime image; only the bundled/minified runtime, production dependencies and SQL migrations are distributed. Front-end containers similarly ship built browser assets rather than their source trees.

See `docs/README.md` for the documentation map and `PUBLISHING.md` for the canonical repository and artifact map.
