# Hi5Central: clean, reproducible managed VPS installation

**Status: design + read-only inventory. DO NOT WIPE THE CURRENT VPS.**
The existing public `install.sh` implements Standard/MSP installs and is **not**
the complete managed-platform bootstrap. A separate, fully integrated
`install-managed.sh` entry point must be certified before replacing the VPS.

## Target

One supported, immutable, signed/approved Platform release SHA + its compatible
public deployment manifest. Starting on clean Ubuntu with Docker Compose,
one operator command (after supplying DNS, email, approved images and private
secrets) installs ALL infrastructure and platform services, registers a fresh
platform administrator, and performs smoke tests. It must **not** reuse
host-tweaked Caddy routes, stale env files or the current database by default.

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
- **Optional** loopback-only pgAdmin via `compose.pgadmin-private.yml`, not an
  unauthenticated public website.

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
   Caddy routing, TURN connectivity, RMM devices, 10 tenant automation and
   failed/rollback paths in a disposable install before protected merge.

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

**Browser database access:** optional pgAdmin, bound to 127.0.0.1 only.
Connect via SSH port forwarding or a private VPN; use separate pgAdmin login
and a distinct read-only PostgreSQL role. Never connect via a PostgreSQL
superuser from the web UI or open 5432/5050 publicly. Read-only means no
DDL/DML credentials; role grants (including future partitions/RLS) require
independent security review.

## Actual ten-tenant acceptance before general automation

1. Secure privileged Docker host operator: no database superuser/Docker socket
   in generic planner/stage workers; explicit tenant+stage+fence+window+SHA
   permit at DB claim AND trusted host dispatch; no UAT→Live bypass.
2. Full migration reconciliation 155–169 under controlled review,
   independently verified role grants and backfill; preserve global pause.
3. Resolve Caddy **host file vs mounted file vs active config** drift, test
   cutover and rollback without weakening isolation.
4. Provision 10 *real* tenants through regular signup/onboarding: five Managed,
   five Custom, two also RMM. Verify MFA, roles, email, licensed modules and
   unique per-tenant windows; explicitly admit ONLY these 10 to pilot scope.
5. Certify Dev build and publish release notes; auto-discover/queue Test for 10.
   Verify designated two-Test-canary gate and per-tenant Test host proof.
   Managed Live moves in its own window; Custom UAT is auto-staged; Custom
   Live waits for exact customer acceptance and their approved window.
6. Verify device enrollment/online status, TURN relays and RMM agent update
   on the two RMM tenants independently of ITSM UAT/Test rollout. In addition,
   reconnect a dedicated Windows qualification agent, enable qualification
   dispatch explicitly, prove a harmless test qualification job and its
   cleanup, and ensure failed/slow jobs are reviewed before requeueing.
7. Verify all 10 exact SHA routes, per-tenant audit logs, dry-run,
   repeat scheduler idempotence, pause/revoke, failed upgrade, rollback,
   backup restore, host restart/recovery, and no cross-tenant leakage.
8. Only after independent acceptance + host security review, authorize
   `all_onboarded` admission. Any **new real ITSM tenant** completing
   onboarding is discovered on subsequent certified release scans, with
   Managed/Custom policy still honoured. RMM-only is never queued for ITSM
   releases.

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
validate smoke tests and 10-tenant readiness, and create a rollback/runbook
report. If the software qualification scheduler/schema, a reachable
configured Windows qualification runner for full acceptance, trusted host
executor, security tests or TURN verification is missing, full
`--verify` MUST report BLOCKED;
do not claim success from 'containers running' alone.
