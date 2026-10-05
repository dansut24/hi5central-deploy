# Hi5Central Self-Hosted

This repository is the public deployment surface for Hi5Central. Application source remains in the private `Hi5Central-Platform` monorepo; self-hosters receive versioned container images, signed native applications and this deployment package.

## Editions

### Standard — free

For an organisation managing its own environment.

Includes:

- ITSM
- browser Self Service
- RMM
- PostgreSQL 17
- Redis 8
- Caddy
- coturn
- persistent Docker volumes
- database migrations
- backup and restore tooling

Platform/MSP Admin is not enabled in Standard.

### MSP — licensed

Uses the same runtime images with a signed MSP entitlement and enables:

- multi-tenancy
- Platform/MSP Admin
- white-label entitlements
- customer portal/custom-domain entitlements
- licensed tenant/device/user limits

The raw MSP key is used for activation and is not stored in `.env`.

## Simple guided installation

On a clean Linux VPS with Docker Engine and Docker Compose v2:

```sh
git clone https://github.com/dansut24/hi5central-deploy.git
cd hi5central-deploy
./install.sh
```

The installer checks the host first, then asks only for the settings it needs.

Typical Standard installation:

```text
Hi5Central Self-Hosted Setup
============================

Docker ............... OK
Docker Compose ....... OK
Memory ............... 8.0 GiB
Disk free ............ 100.0 GiB

Installation type:
  1) Standard - Free
  2) MSP - Licensed
Select [1]:

Install:
  1) ITSM + RMM
  2) ITSM only
  3) RMM only
Select [1]:

Primary domain:
> hi5.example.com

Use automatic HTTPS with Let's Encrypt? [Y/n]:
Update channel:
  1) Stable (recommended)
  2) Early Access
Select [1]:

HTTP port [80]:
HTTPS port [443]:
TURN port [3478]:
Use default TURN relay range 49160-49200? [Y/n]:
Use advanced/custom hostnames? [y/N]:
Configure SMTP now? [y/N]:
Generate secure installation secrets automatically? [Y/n]:

Start installation? [Y/n]:
```

Pressing Enter accepts the recommended defaults.

## Secrets

Automatic generation is the default and recommended option.

Hi5Central generates cryptographically random values for PostgreSQL, Redis, MFA encryption, RMM recovery encryption, Connect HMAC, tenant installer HMAC and TURN. The generated `.env` is written with restrictive permissions and secrets are not echoed to the terminal.

If you want to provide secrets yourself, answer **No** to automatic secret generation or use:

```sh
HI5_SECRET_MODE=manual \
HI5_POSTGRES_PASSWORD='...' \
HI5_REDIS_PASSWORD='...' \
HI5_MFA_ENCRYPTION_KEY='64-hex-characters...' \
HI5_RMM_RECOVERY_KEY_ENCRYPTION_KEY='64-hex-characters...' \
HI5_CONNECT_CODE_HMAC_KEY='64-hex-characters...' \
HI5_TENANT_INSTALLER_HMAC_KEY='64-hex-characters...' \
HI5_TURN_SHARED_SECRET='64-hex-characters...' \
./install.sh --domain hi5.example.com
```

This allows secrets to come from a password manager, provisioning system or other secret-management workflow.

## Domains

A single base domain is enough.

For `hi5.example.com`, defaults are derived automatically:

- `itsm.hi5.example.com`
- `rmm.hi5.example.com`
- `api.hi5.example.com`
- `downloads.hi5.example.com`
- `turn.hi5.example.com`
- `admin.hi5.example.com` for MSP only

Choose advanced/custom hostnames during setup if these defaults do not suit the environment.

## Ports

Defaults:

- TCP 80 — HTTP / ACME redirect
- TCP/UDP 443 — HTTPS / HTTP3
- TCP/UDP 3478 — TURN
- UDP 49160-49200 — TURN relay range

The preflight checks required host ports on a fresh installation and stops before container startup if a conflict is detected.

All main ports can be overridden interactively or with `HI5_*` environment variables.

## HTTPS

Automatic HTTPS through Caddy is the normal public deployment.

For an internal/LAN deployment, or when TLS is terminated elsewhere:

```sh
./install.sh --domain hi5.internal --http
```

## Release channels

Self-host installations never consume development or production images directly.

Two self-host channels are supported:

- **Stable** — recommended/default; only explicitly published, production-verified releases.
- **Early Access** — optional release candidates for customers who choose to test ahead of Stable.

The installer writes the selected channel into `.env`. The deployment validator rejects `:latest` for self-hosted platform images.

Internal Hi5Central flow:

```text
feature / PR
    ↓
Development
    ↓
tested
    ↓
Production
    ↓
production smoke checks
    ↓
explicit Publish Self-Hosted Release
    ├── stable
    └── early-access
```

A Production deployment does **not** automatically publish a self-host release.

## Updating

Run:

```sh
./scripts/update.sh
```

The updater:

1. validates configuration;
2. creates a pre-update application backup when PostgreSQL is running;
3. pulls the approved selected release channel;
4. applies database migrations;
5. recreates changed services;
6. waits for core services to become healthy;
7. prunes unused image layers.

Set `HI5_SKIP_UPDATE_BACKUP=1` only when an equivalent external backup has already been taken.

## Backup and restore

Create a backup:

```sh
./backup.sh
```

Restore:

```sh
./restore.sh backups/hi5central-backup-YYYYMMDDTHHMMSSZ.tar.gz
```

Backup archives contain `.env` and therefore contain secrets. Store them as sensitive material.

## Non-interactive installation

Standard:

```sh
HI5_ROOT_DOMAIN=hi5.example.com \
HI5_EDITION=standard \
HI5_PRODUCTS=itsm,rmm \
HI5_RELEASE_CHANNEL=stable \
./install.sh
```

MSP:

```sh
HI5_ROOT_DOMAIN=msp.example.com \
HI5_EDITION=msp \
HI5_LICENSE_KEY='hi5_msp_...' \
HI5_PRODUCTS=itsm,rmm \
HI5_RELEASE_CHANNEL=stable \
./install.sh
```

Use `./install.sh --help` for command-line options.

## Configure without starting

```sh
./install.sh --configure-only
```

This generates and validates configuration without pulling or starting application containers.

## Existing installation commands

- `./scripts/up.sh` — validate, pull and start.
- `./scripts/update.sh` — backup, update and health-check.
- `./scripts/down.sh` — stop without deleting persistent volumes.
- `./scripts/validate.sh` — validate secrets, release channel and Compose.
- `./preflight.sh` — host/resource/DNS/port checks.
- `./backup.sh` — application-aware backup.
- `./restore.sh <archive>` — restore a protected backup.

## Testing a candidate release on a second VPS

A clean second VPS is the preferred acceptance environment because it behaves like a real new customer's server and cannot accidentally depend on the existing Hi5Central host.

See `docs/SECOND_VPS_ACCEPTANCE.md` for the full acceptance checklist.

## Repository boundary

`Hi5Central-Platform` is the private canonical product monorepo.

`hi5central-deploy` is intentionally separate and public. It contains only the deployment surface required by self-host customers: Compose, gateway configuration, install/update/backup/restore tooling and documentation.

Container distribution does not make delivered software impossible to inspect; repository access, signed artifacts, licensing and release controls remain part of the protection model.
