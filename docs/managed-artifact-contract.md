# Managed IONOS reinstall — exact artifact contract

**Current state: preparation and CI gates passed; the complete installer is
NOT ready.** `install-managed.sh --install` remains intentionally blocked.
The owner, not the script, resets IONOS manually only after acceptance.

## What the manifest does

`./install-managed.sh --check-manifest --manifest /private/managed-release.json`
reads an approved JSON document without contacting the registry or altering
the host. The strict schema `hi5central-managed-restore-v1` requires:

- `deployment_kind=managed_fresh`, `tenant_seed_count=0`,
  `release_rollout_paused=true`, `catalogue_seed_policy=global_only`,
  `externals_optional=true`.
- One 40-character immutable **Platform Git commit SHA**.
- Exactly 15 **digest-pinned** container artifacts (no floating `:dev`,
  `:latest`, `:stable`, or unqualified SHA tag): Platform API, ITSM, RMM,
  Admin, marketing/signup, deployment agent assets, certified release
  planner, stage executor, **protected host dispatcher**, PostgreSQL,
  Redis, Caddy, coturn/TURN, and private pgAdmin.
- Exactly nine separately verified native/download deliverables: Windows,
  Linux, macOS agent; Windows, Linux, macOS viewer; mobile-compatible
  viewer/web delivery; Avalonia/C# self-service package.
  Each requires HTTPS download URI, SHA-256 digest and its own source Git
  SHA. Native agent and viewer latest-release channels are **independent**
  of the version running on a tenant's ITSM/RMM applications.
- Human review references for the application release, managed infrastructure
  and trusted host dispatcher. A string reference is NOT a cryptographic
  signature or evidence of approvals on its own.

The check deliberately **does not** mean registry digests are retrievable,
that image provenance is verified, or that DNS, builds and services work.
Those must be added as separate real integration checks.

## Newly implemented (staging only) — pinned cloud core

The draft managed installer now contains `compose.managed-core.yml`,
derived from the older cloud stack at
`Hi5Central-Cloud@b4eb84434005586f0a69f03e955a88bf2e962a3e`.
It has a separate marketing container, Caddy gateway, API, ITSM/Portal,
RMM/Control, global Admin, PostgreSQL, Redis, coturn, agent assets and
database migration step. With `compose.pgadmin-private.yml` it adds the
private database browser. All launched images must be digest-pinned.

The clean-install config-init does **not** preseed `test` or any customer
hostname. Customer DNS routes must instead be added by a reviewed tenant
provisioning gateway with tenant identity and stage approval checks.

`scripts/render-managed-runtime.py` now combines the previously generated
local private secret file with the complete approved immutable image manifest
to produce `managed-runtime.env` (0600), without starting Docker. It
refuses old tenant IDs, disabled global pause, mismatched image manifests,
or secret overwrites. The entrypoint supports `--render-core --manifest`
and `--verify-core-compose`; neither action deploys services.

CI verifies the Compose rendering (actual Docker Compose parser), a
distinct marketing route, private pgAdmin loopback, no published PostgreSQL,
and no implicit customer DNS routes. This is **NOT proof of application
startup, working signup, correct Caddy cutover, full platform migrations
or secure generic worker deployment.** `--install` remains blocked.

## Tenant-independent Global Admin bootstrap — implemented and tested

The managed secrets preparation now creates an additional root-only,
independently generated `platform-owner-password`. That password is **not**
distributed in any application container's environment or SQL: the fresh
owner bootstrap derives the same `scrypt$16384$8$1$...` format used by the
Platform API's password verifier. The password is never displayed in logs.

`scripts/bootstrap-managed-platform-owner.py` provisions the initial
`users`, `platform_admin_members(role='owner',status='active')` and
`platform_admin_audit_events` records in **one database transaction**.
It rejects non-empty customer tenants, any pre-existing user, existing
release jobs, unpaused rollout, missing required Platform migration, wrong
Docker Compose project, or publicly exposed PostgreSQL. It creates **zero**
tenant rows or tenant memberships. A second invocation is refused.

`install-managed.sh --bootstrap-owner` exposes this operation only after
fresh managed migrations exist. It is a building block for the eventual
automatic one-command `--install`, which still refuses execution.
Disposable PostgreSQL 17 CI tests prove owner registration, creation audit,
correct scrypt password derivation and the refusal to bootstrap twice.

**Not yet proven:** real complete-schema startup, web sign-in session and
MFA setup. These remain mandatory before proclaiming the installer READY.

## Known gaps in the existing source

| Existing source | Discovered difference | Required work before READY |
| --- | --- | --- |
| `Hi5Central-Cloud/deploy/compose.cloud.yml` | Defines Postgres, Redis, API, ITSM, RMM, Admin, TURN and Caddy but uses floating tags | Import/consolidate into one managed fresh-install definition with checked immutable digests |
| `Hi5Central-Cloud/scripts/setup-managed-region.sh` | Defaults `PRIMARY_TENANT_SLUG=test` and `MANAGED_TENANT_SLUGS=test` | Start with **zero tenants**; no temporary production customer |
| `Hi5Central-Cloud/scripts/bootstrap-managed-admin.sh` | Requires existing tenant and membership | Provide a **tenant-independent global Admin** bootstrap that retains zero tenants |
| Cloud Caddy `config-init` | Generates `slug-portal` hostname; user wants `slug.hi5central.com/portal` | Verify exact tenant hostname rules; Portal at /portal, optional RMM domain, Test, Custom-only UAT and tenant Admin; prevent wildcard route collisions |
| Current VPS marketing container `deployment-web` | No confirmed canonical pinned marketing/signup image in existing cloud Compose | Move the existing signup/marketing source into a reproducible image and verify signup |
| Generic PR #79 Test/UAT/Live worker Dockerfile | Old deployed executors use DB superuser and root+writable Docker socket | Replace with independent protected host authority and non-superuser, stage-limited Postgres identities; audit rollback, canary and tenant gates |
| Platform migrations + catalogue seed importer | CI importer passed against a **minimal disposable test schema**, not the full Platform migration history | Rehearse complete migration source and real catalogue export against disposable PostgreSQL before IONOS reset |
| Caddy/TURN and native viewer distributions | Existing release routing and viewer/agent artifacts have multiple source locations | Reconcile active Caddy source, Windows/macOS/Linux installers, mobile viewer, Avalonia portal, TURN relay, and signed binary delivery |
| pgAdmin Compose override | Private loopback port and test DB editor account have passed syntax/fixture checks | Verify real pgAdmin web login and full app table DML, ensure least privilege in new full-schema database |
| Initial secret generation | `--prepare` generates internal secrets without overwriting old ones | Map ALL application environment keys, rotation, signing/public-key distribution and encrypted off-host recovery into full installer |
| Backups and recovery | Old VPS backup previously restored successfully; fresh managed bootstrap not yet exercised | Prove new volume backups, recovery, installer rerun/idempotency and notification status with no tenants |

## Full restore acceptance on clean Ubuntu

1. Operator resets the VPS manually via IONOS and runs the single pinned
   installer with a private approved release manifest and catalogue archive.
2. Fresh-host preflight passes without existing containers. All required
   secrets are generated privately; no previous Production secrets carried over.
3. PostgreSQL canonical migrations and global software catalogue import
   complete with **zero tenants, zero tickets, zero RMM devices**.
4. Core services healthy: marketing/signup, Hi5Dev, global Admin, tenant
   provisioning, ITSM/Portal, RMM/Control, Caddy, coturn, approved release
   workers and native package distribution. Initial automatic global release
   rollout remains paused while security authorization is independently checked.
5. The private pgAdmin web interface is accessible only through SSH/VPN,
   with its own login and a separate full-record-edit PostgreSQL identity.
6. Backup/restore, interrupted-run recovery and a second installer run prove
   idempotency. Evidence must come from a disposable clean Ubuntu before any
   live IONOS rebuild.
7. SMTP, Stripe, public DNS/TLS/TURN connectivity, agent signing and external
   Windows qualification endpoint may be **NOT CONFIGURED** or **SKIPPED**.
   The server-side integration must remain installed; unavailable external
   services cannot misleadingly report READY.

**No ten-tenant rollout trial is required for a clean platform reset.** New
tenants are added later through normal signup, on the user's schedule.
