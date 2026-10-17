# Hi5Central: clean, reproducible managed VPS installation

**Status: design + read-only inventory. DO NOT WIPE THE CURRENT VPS.**
The existing public `install.sh` implements Standard/MSP installs and is **not**
the complete managed-platform bootstrap. A separate, fully integrated
`install-managed.sh` entry point must be certified before replacing the VPS.

## Target

One supported, immutable, signed/approved Platform release SHA + its compatible
public deployment manifest. Starting on clean Ubuntu with Docker Compose,
one operator command provisions the core platform with a new database,
restores the verified global software catalogue and vendor sources, creates
the initial platform administrator, and performs core smoke checks. It must
start with **zero tenants**. External SMTP, billing, DNS, device signers and
Windows qualification endpoints can be registered after setup (or skipped),
without pretending that unconfigured features are operational. It must **not**
reuse host-tweaked Caddy routes, stale env files or the old database.

Required service inventory:
- Marketing/site, shared authentication and onboarding; ITSM workspace and
  requester Portal; RMM/Control workspace and Control API; Platform Admin +
  per-tenant billing/admin surface; PostgreSQL 17 and Redis.
- Caddy edge + managed Test/UAT/Live routing, Dev control plane, independent
  per-tenant environments and automatic version updates.
- **coturn/TURN** with shared secrets, relay network and externally reachable
  ICE path; remote viewer/agent installer distribution and downloads.
- **Software Qualification Runner is a registered Windows RMM agent,
  not a VPS Docker container.** Its scheduling / queue-processing code lives in
  `services/api/src/rmmSoftwareQualification.js` and
  `rmmSoftwareVendorIntel.js`; `runSoftwareQualificationQueue` dispatches
  through the RMM agent jobs API to a device registered in
  `rmm_software_vendor_qualification_runners`. The Control API's qualification
  queue/progression timers and durable queue, software catalogue, vendor intel
  and runner registration schema MUST be included with the approved API image.
  The qualification Windows device, PatchHost capabilities and its own
  isolated installer scratch directory cannot be created by a VPS-only
  script: enroll/rebind and verify its agent heartbeat, job-scoped artifact
  cleanup and download/install/uninstall capability after fresh install.
  A full `--verify-qualification` check MUST report BLOCKED if no eligible
  connected Windows runner is present, rather than claim success.
- Generic certified release planner, Test/UAT/Live workers, emergency pause,
  fenced job leases, isolated host deployment authority, release notes,
  audit history and safe rollback.
- Backups, scheduled backup validation, metrics/health and alerting.
- **Required private database browser:** pgAdmin via `compose.pgadmin-private.yml`
  installed by the managed bootstrap, listening on loopback only and reachable
  through authenticated SSH port forwarding/VPN. Provide a separate PostgreSQL
  database-admin login with **full application-data editing** (view/insert/
  update/delete, and authorised schema maintenance) restricted to the new
  Hi5Central database. It must not expose pgAdmin/5432 to the Internet.

No module silently disappears on a fresh install, even if it currently runs
as a manually created container. RMM is **single Live workspace** (no RMM
Test/UAT tenant portals); ITSM Managed gets Live + Test, Custom gets Live +
Test + UAT. All environments share authorised identity but use independent
release gates.

## Approved retention scope — fresh platform, preserve RMM software intelligence

The requested destination is a **new empty PostgreSQL installation**, not an
import of legacy tenants. ITSM records, old user accounts and sessions, six
QA tenants, RMM devices, enrollment tokens, agent jobs, device/session/patch
history, release jobs, Test/UAT approvals and 161 historical qualification
review records can be **absent from the new database**. The original full
Production backup and audit trail must be preserved separately until verified
new infrastructure and software catalogue are accepted.

Preserve the **global software catalogue and its source data** in a separate
restricted-permission seed export, currently comprising:

1. `rmm_software_catalogue` where `tenant_id IS NULL` (global entries,
   including qualification/version/trust metadata). Strip former user foreign
   keys: `created_by_user_id`, `updated_by_user_id`,
   `qualified_by_user_id` when preparing data.
2. `rmm_software_vendor_sources` (configured global vendor feeds).
3. `rmm_software_vendor_bindings` (source-to-product mappings).
4. `rmm_software_vendor_releases` (release versions, downloads, hashes,
   trust/source payloads and evidence).

`scripts/export-global-software-catalogue.py` produces a consistent,
single-query, read-only JSONL seed archive with SHA-256 manifest and exact row
counts. It does **not** create tenants, retain ticket/device records, alter
Production, or import the data. The exporter requires the known verified full
recovery dump and MUST be tested by a separate checked importer in an
isolated, fresh, migrated PostgreSQL database before any wipe.

The new install **must not restore** tenant-specific `rmm_tenant_vendor_sources`
or vendor releases: those belong to accounts being intentionally discarded.
`rmm_vulnerabilities`, `rmm_vulnerability_products`, OUI and other public
vulnerability/reference intelligence may be repopulated from canonical
upstream feeds after verified sync/seed jobs. Since these tables account for
most current database storage, leaving them out of the fresh seed avoids
cloning obsolete QA intelligence; preserve source config and exact metadata
needed to rebuild. Confirm importer/upstream availability before approving
the destructive cutover. No blanket `TRUNCATE`, `DROP`, or PostgreSQL
volume removal on the existing VPS is part of this plan.

**Trust:** Existing `qualified` flags and installer URLs are historical
evidence, NOT an exemption from new patch/installer verification. The
dedicated Windows qualification agent must be newly registered and revalidated
after the rebuild, because its device identity intentionally does not migrate.

The export archive might include credential-bearing source metadata or
private source URLs. Protect it as a secret, copy it off-host securely, and
review sensitive fields before importing. Do not check JSONL or archives into
public GitHub.

## GitHub repository cleanup BEFORE any reset

1. Pick one authoritative source of each component in
   `dansut24/Hi5Central-Platform` and record the actual working code/image
   SHA. Old `hi5central-itsm`, `hi5central-rmm`,
   `hi5central-control-server`, `hi5central-admin`, agent/viewer and
   other imported repos are **provenance**; do not delete them automatically.
2. Review open PRs, especially draft #76 and #79, dependencies, migration
   checks, RMM agent templates, billing and onboarding. Merge only through
   normal protected review and green required checks. Do not force-push main.
3. Classify `deployment/qa26` scripts, Compose overlays, temporary Caddy
   test pools and old SHA-specific artifacts into (a) reusable tested runtime
   features, (b) archival QA evidence, (c) obsolete but unverified.
   Keep history in git/docs while consolidating ONE canonical managed
   deployment and release workflow. Do not blindly remove QA code still used
   by existing runtime/tests.
4. Keep the public `hi5central-deploy` customer distribution separate from
   private managed operator credentials. Source repo should not carry secrets.
5. Require an immutable manifest (exact digest for each image) and a supply
   chain verification gate for API, ITSM, RMM, Admin, Agent/Viewer/downloads,
   qualification runner and release workers. Never silently use :latest in
   Production or mix releases across components.
6. Test syntax, Compose config, fresh DB migrations, restore, job queues,
   Caddy routing, core startup, pgAdmin private access and real writable DB
   permissions, backup/restore, and restart/idempotency in a disposable install.
   No tenants or ten-tenant rollout are required for a clean reinstall.

## Database cleanup and reset policy

**Before reset:** use `scripts/managed-prewipe-inventory.sh` and verify
protected full `pg_dump -Fc` plus object storage/off-host copies. Restore it
into isolated PostgreSQL using `pg_restore --single-transaction --exit-on-error`
and verify row counts and backup digest. Independently export/verify tenant
attachments, RMM device secrets, installer artifacts, qualification-runner
result artifacts, logs/audit trails and custom configuration not included in
PostgreSQL. Restore of a DB backup alone does NOT prove all these survive.

**Fresh install:** create NEW PostgreSQL data volume. Apply reviewed canonical
migrations exactly once in order; assert schema_migrations is consistent,
constraints valid, required indexes/triggers/RLS present. Seed the reviewed global software catalogue/vendor source export as a
separately validated post-migration step, then create only the platform
owner/roles, version metadata, global release pause=true, required
environment defaults and intentionally empty tenant state. Do not carry
QA26 tenant rows, old release jobs, test Stripe subscriptions, stale sessions,
expired tokens, audit-event spam or CI credentials into the NEW database.
Do not 'clean' `schema_migrations` by deleting rows, fabricate approvals,
or purge append-only audit events. Review migration 158/159/161/163/164/165
schema+ownership+ACL equivalence rather than copying manual ledger repairs.

**Old Production DB:** retain secured off-host recovery archive with named
retention/expiry and deletion approval; remove only old isolated QA/obsolete
volumes after all verifications. The future wipe must require an explicit,
separate operator action referencing host identity, backup digest and the
approved deployment/change ID. This document and the optional pgAdmin overlay
DO NOT PERFORM A WIPE OR DROP/DELETE ANY DATABASE OBJECTS.

**Browser database access:** pgAdmin is a required managed-install component,
bound to `127.0.0.1` only. It is accessible via SSH tunnel/VPN with a distinct
pgAdmin web login AND a separate Hi5Central database-admin login. The
PostgreSQL login has full application-table read/write privileges (SELECT,
INSERT, UPDATE, DELETE, applicable sequences) and reviewed schema-management
privileges within the fresh application database. **No cluster SUPERUSER**,
`BYPASSRLS`, `CREATEROLE`, or public/guest connection. For existing or
future tables, default privileges/grant ownership need verification in CI;
full row editing must be demonstrated in a disposable database. Schema
changes may require owner/migration credentials, stored separately.
Do not open PostgreSQL port 5432 or pgAdmin port 5050 to the public Internet.
Database editing bypasses some application workflows and should require
backup-before-change and privileged-access audit; never let this admin login
serve customer API or unattended release-worker connections.

## Clean-install acceptance: ZERO tenants

The fresh VPS must install **all core capabilities**, restore global software
catalogue/vendor source data into a freshly migrated database, bootstrap a
new global Admin identity, confirm configuration/health, and start with exactly
**zero tenants**, zero ITSM tickets and zero RMM device/agent/rollout records.
Application release automation starts in a safe, paused/approval-gated state.
The previous ten-tenant QA exercise is **separate later work**, not an
acceptance condition for resetting and reinstalling a blank platform.

Features requiring outside credentials or real devices are **installed but
configurable later**, with explicit status and no misleading success flag:
- SMTP: skip credentials initially; account verification/password reset must
  report not configured until an end-to-end mail check passes.
- Stripe or other payments: billing schema/tenant Admin remains available but
  no live charges or Stripe webhooks activate until configured.
- Windows qualification RMM device: server queue/catalogue retained; runner
  can be enrolled after reset and dispatch starts disabled until verified.
- Agent/viewer signing, publishing and remote mobile viewer: keep packages,
  endpoints and build manifest; verify actual artifacts when supplied.
- Public DNS/TLS and external TURN relay: retain Caddy/TURN services and
  templates. Report required DNS/network steps where not configured.
- Other optional integrations: no credentials are silently fabricated.
- pgAdmin is **not optional for the final managed setup**: the private
  database browser must support full row editing, with no Internet exposure.

Use independent readiness reports for core services and integrations, e.g.
CORE READY, SMTP NOT CONFIGURED, PAYMENTS SKIPPED, QUALIFICATION SKIPPED,
TURN EXTERNAL CHECK PENDING. An unavailable optional external dependency
must not fail a successfully installed core service.

There is no requirement to create ten tenants—or any tenant—to prove a fresh
installation. Test automated onboarding/upgrades later with whichever
legitimately created tenants are available, after independently reviewing
security, deployment permissions and rollback.

## IONOS-owned reset and automated credential restoration

The **owner will reset Ubuntu via the IONOS control panel after we confirm
the installer is complete and independently validated**. This repository
must never contain a VPS wipe, disk repartition, force-delete or Docker
prune step. The installer then rebuilds the application and database using
a NEW independent configuration.

A single managed restore command will:
1. Generate entirely new root-only database, Redis, MFA, recovery, agent
   onboarding, TURN, internal release/operator, session, initial setup,
   pgAdmin web login and independent database editor passwords, plus
   internal Ed25519 release-signing key pair. Never reuse old live secrets.
2. Prepare private `/etc/hi5central/managed/` secret storage with mode
   0700 directory / 0600 credential files. Refuse existing/partial
   configuration, never print a password, and require protected off-host
   recovery copies before deleting the original machine.
3. Pull one approved immutable image set and apply canonical migrations
   to an **empty** new PostgreSQL database; initial global rollout paused,
   no pre-created customer tenants, tickets, RMM devices or jobs.
4. Import and validate the exported global software catalogue/vendor
   sources. A fresh-DB importer operates transactionally and refuses any
   existing tenant/user, RMM device, qualification job, release job or
   unpaused rollout.
5. Launch a private loopback-only pgAdmin browser with distinct web/DB
   credentials and a dedicated non-superuser `hi5_pgadmin_editor` account
   granting full app record CRUD, sequence access and controlled CREATE.
   Protected row-level policies and DDL ownership rules still apply.
6. Set up marketing/signup, ITSM/Portal, RMM/Control, Admin, Hi5Dev,
   Caddy/TURN, download/agent/viewer assets, safe release workers and
   restore/backup checks. External SMTP, Stripe, code-signing certificates,
   DNS/relay proof and Windows qualifier can be added later or skipped.

**Implemented in draft PR only:** `install-managed.sh` with safe
`--dry-run`, `--prepare` and `--verify-secrets`; the preparation
module, transactionally guarded catalogue importer and limited pgAdmin
DB-editor provisioning. Disposable PostgreSQL CI verifies accepted import,
editor SELECT/INSERT/UPDATE/DELETE and rejection on nonempty databases.

**Not implemented:** Actual `--install` activation and full managed image,
network/routing, bootstrap and host-worker startup. `--install`
intentionally refuses execution. This draft is **not evidence** that the
IONOS reset is ready. The installer will be marked ready only after it
can deploy end-to-end from a clean Ubuntu VPS and pass all core checks.

## One-command installer acceptance criteria (not yet implemented)

The future command should behave like:

```bash
sudo ./install-managed.sh --manifest releases/<approved-manifest>.json \
  --config /secure/hi5central-managed.env --mode fresh --verify
```

It must show a plan and block destructive or irreversible steps until
privately reviewed, support `--dry-run`, generate missing secrets without
displaying them, check DNS/TLS/Docker/resources/firewall/backup, pin images,
provision roles and database migrations, install all required services,
validate core service health, zero-tenant state, private pgAdmin login and
full database record editing against a temporary test table, and create a
rollback/runbook report. Missing OPTIONAL external credentials/devices must
be flagged `SKIPPED`/`NOT CONFIGURED`, not treated as a core install failure.
Missing mandatory code, migration, core infrastructure or safe installer
permissions remains a hard failure. Do not claim success from 'containers
running' alone.
