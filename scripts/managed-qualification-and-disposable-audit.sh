#!/usr/bin/env bash
# Read-only qualification, resource and orphan-rehearsal inventory.
# No SQL writes, no Docker stop/rm/prune, no secrets dumped.
set -Eeuo pipefail
set +x
echo '===== HI5CENTRAL QUALIFICATION + RESTORE RESIDUE CHECK (READ ONLY) ====='
date -u '+UTC: %Y-%m-%dT%H:%M:%SZ'
echo
echo '1. Host pressure'
free -h
printf '\nvmstat: si/so swap-in/out (three samples):\n'
vmstat 1 3 || true
echo
echo '2. Disposable PostgreSQL candidates (metadata only)'
python3 - <<'PY'
import json,subprocess
names=[
 'hi5central-migration155-e77bb81c27',
 'hi5central-migration156-6e187ad56404',
 'hi5central-migration157-c6eadb3b6a42',
 'hi5central-restore-check-77968d7fa245',
]
for n in names:
 try:
  c=json.loads(subprocess.check_output(['docker','inspect',n],text=True))[0]
 except subprocess.CalledProcessError:
  print(n+': missing');continue
 print('\n'+n)
 print(' state:',c.get('State',{}).get('Status'))
 print(' created:',c.get('Created'))
 print(' restart:',(c.get('HostConfig',{}).get('RestartPolicy') or {}).get('Name'))
 print(' networks:',','.join(sorted((c.get('NetworkSettings',{}).get('Networks') or {}).keys())) or 'none')
 print(' network_mode:',c.get('HostConfig',{}).get('NetworkMode'))
 ports=c.get('NetworkSettings',{}).get('Ports') or {}
 print(' PUBLIC PORTS:',','.join(k for k,v in ports.items() if v) or 'none')
 mounts=c.get('Mounts') or []
 print(' named volume mounts:',','.join(m.get('Name','') for m in mounts if m.get('Type')=='volume') or 'none')
 print(' bound host path count:',sum(m.get('Type')=='bind' for m in mounts))
 labels=c.get('Config',{}).get('Labels') or {}
 print(' compose project:',labels.get('com.docker.compose.project','none'))
 print(' compose service:',labels.get('com.docker.compose.service','none'))
print('\nThese are CANDIDATES, not authorised for deletion by this script.')
PY
echo
echo '3. Qualification runner registration and queue statistics'
docker exec -i hi5central-postgres sh -c \
  'exec psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -X -v ON_ERROR_STOP=1' <<'SQL'
BEGIN READ ONLY;
SET LOCAL statement_timeout='15s';
SELECT
 to_regclass('public.rmm_software_vendor_qualification_runners') IS NOT NULL AS runner_registry_exists,
 to_regclass('public.rmm_software_qualification_queue') IS NOT NULL AS queue_exists,
 to_regclass('public.rmm_agent_devices') IS NOT NULL AS agent_table_exists;
SELECT
 q.enabled,q.dispatch_enabled,a.websocket_status,
 (a.disabled_at IS NULL) AS agent_not_disabled,
 (a.last_telemetry_at > now() - interval '90 seconds') AS telemetry_current,
 COALESCE((a.patch_capabilities->>'softwareInstall')::boolean,false) AS software_install_capable,
 COALESCE(a.patch_capabilities->'vendorDirect'->>'artifactStorage','')='job_scoped' AS isolated_artifact_storage,
 COALESCE((a.patch_capabilities->'vendorDirect'->>'jobDirectoryPurgedOnExit')::boolean,false) AS cleanup_capable,
 COALESCE((a.patch_capabilities->'vendorDirect'->>'winInetCacheUsed')::boolean,true)=false AS no_wininet_cache,
 q.updated_at
FROM rmm_software_vendor_qualification_runners q
LEFT JOIN rmm_agent_devices a ON a.id=q.agent_device_id
ORDER BY q.updated_at DESC LIMIT 20;
SELECT state,test_type,count(*) AS jobs
FROM rmm_software_qualification_queue
GROUP BY state,test_type ORDER BY state,test_type;
SELECT count(*) AS outstanding_qualification_jobs
FROM rmm_software_qualification_queue
WHERE state IN ('queued','running','cleanup_pending','cleanup_running','review_required');
SELECT count(*) AS registered_qualification_runners
FROM rmm_software_vendor_qualification_runners;
SELECT count(*) AS registered_agent_devices
FROM rmm_agent_devices;
SELECT
 pg_size_pretty(pg_total_relation_size('rmm_vulnerabilities')) AS vulnerabilities_size,
 pg_size_pretty(pg_total_relation_size('rmm_vulnerability_products')) AS affected_products_size,
 pg_size_pretty(pg_total_relation_size('rmm_software_qualification_queue')) AS qualification_queue_size;
ROLLBACK;
SQL
echo
echo '4. Candidate private PostgreSQL browser role: privileges only'
docker exec -i hi5central-postgres sh -c \
  'exec psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -X -v ON_ERROR_STOP=1' <<'SQL'
BEGIN READ ONLY;
SELECT rolname,rolcanlogin,rolsuper,rolbypassrls,rolcreatedb,rolcreaterole
FROM pg_roles WHERE rolname='hi5_master_testing_ro';
SELECT
 has_schema_privilege('hi5_master_testing_ro','public','USAGE') AS schema_usage,
 has_table_privilege('hi5_master_testing_ro','public.tenants','SELECT') AS tenants_select,
 has_table_privilege('hi5_master_testing_ro','public.tenants','INSERT') AS tenants_insert,
 has_table_privilege('hi5_master_testing_ro','public.tenants','UPDATE') AS tenants_update,
 has_table_privilege('hi5_master_testing_ro','public.tenants','DELETE') AS tenants_delete;
ROLLBACK;
SQL
echo
echo '===== READ-ONLY QUALIFICATION AND RESIDUE AUDIT COMPLETE ====='
