# Original VPS — scheduled PostgreSQL recovery snapshots

This script targets **only** the original Hi5Central managed VPS (`ubuntu`) and its Docker PostgreSQL container `hi5central-db-1`. It does not run on the EU servers and is **not** the self-hosted single-tenant backup workflow.

The current database set is `hi5central`, `hi5central_dev`, `hi5central_test`, and `hi5central_uat`. `scripts/backup-managed-runtime.sh` writes custom-format logical backups and role globals with root-only permissions. Archives are verified with `pg_restore --list` and SHA-256, saved under `/opt/hi5central/recovery/scheduled-postgres/<UTC stamp>/`, with 14-day local retention and an exclusive lock.

Proposed cron (UTC; install only on the **original** VPS after manual validation):

```cron
SHELL=/bin/bash
PATH=/usr/sbin:/usr/bin:/sbin:/bin
15 2 * * * root /usr/local/sbin/hi5central-postgres-backup >> /var/log/hi5central-postgres-backup.log 2>&1
```

Run `bash -n scripts/backup-managed-runtime.sh`, install as root mode 0700, run once and confirm all four valid archives plus globals before enabling cron.

**Limitations:** This is a local PostgreSQL logical backup, not a verified restore, encrypted off-server backup or full recovery archive. It does not include Caddy, TURN, Redis, uploaded App Portal packages, download assets, application keys, tenant secrets or other persistent volumes. Those require a separately approved disaster-recovery design and off-server retention. Never display the backups or globals file contents in CI/logs/chat.

Do not use the self-host `scripts/restore.sh` against this managed VPS; its restore operation would replace live data.
