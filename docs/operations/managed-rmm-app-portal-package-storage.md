# Original VPS: RMM App Portal private package storage

Date: 13 November 2026. Target: original primary VPS \`ubuntu\` only.
Do **not** use on any \`h5c-eu-*\` servers.

## Incident and root cause

The \`newtest\` tenant had a draft custom App Portal item called \`7Zip\` whose
installer had not uploaded successfully.

The production RMM API uses \`APP_PORTAL_PACKAGE_DIR\` or defaults to
\`/srv/app-portal-packages\`. The running API image was deployed with no volume
for that directory. The service runs as unprivileged uid/gid 1000 and cannot
create the required directory under root-owned \`/srv\`. The upload pipeline
therefore raises an EACCES error and responds HTTP 500 "Package upload failed."

This was not caused by the Lenovo Agent, GitHub build or available disk space
(the original VPS had >200 GB available).

## Implemented fix

The **managed** runtime compose on \`ubuntu\` has this line under \`rmm-api:\`
\`volumes:\`:

\`\`\`yaml
      - /opt/hi5central/runtime/rmm/app-portal-packages:/srv/app-portal-packages:rw
\`\`\`

Host directory created with owner uid:gid \`1000:1000\` and mode \`0700\`.
This protects packages from other host users, persists across container
recreation, and allows the \`node\` runtime user to create tenant/app/revision
subdirectories. No binary installer or user credentials are stored in Git.

Only the existing \`rmm-api\` container was recreated using the same image,
not the RMM web, viewer, Agent, TURN or ITSM services. The RMM API health
returned healthy, mount inspected as RW, and an unprivileged storage
write/read/hash/delete smoke test passed.

The managed VPS compose configuration is located at
\`/opt/hi5central/runtime/compose.yml\`; do **not** replace it with the
self-hosting template in this repository. Its original backup is stored as
\`/opt/hi5central/runtime/compose.before-app-portal-storage-<UTC>.yml\`.

## Verification and acceptance

1. \`docker inspect hi5central-rmm-api-1\` confirms the mount and health.
2. \`docker exec hi5central-rmm-api-1 sh -c 'id;test -w /srv/app-portal-packages'\`
   succeeds as unprivileged \`node\`.
3. Public tenant site \`https://newtest-rmm.hi5central.com/\` returns 200 and
   an unauthenticated App Portal API returns 401. No auth bypass introduced.
4. **Outstanding live test:** signed-in \`newtest\` admin retries uploading a
   trusted MSI or EXE. Verify returned SHA-256, byte count, published revision,
   stored file in the new package volume and subsequent authenticated Agent
   package download. Do not mark APP-003 or APP-006 Passed until on-device
   evidence is recorded.
5. The first failed \`7Zip\` draft has no package. Retrying the existing web
   Create flow creates a separate draft; avoid treating the original failed
   revision as published or successful.

## Product requirement — separate, unresolved

The Windows Software Self-Service application must be automatically installed
on an enrolled endpoint **when Software Self Service is enabled for that device
in RMM**. Manual per-user installer download is not the normal production flow.
This desired-state rollout is tracked separately in
https://github.com/dansut24/Hi5Central-Platform/issues/179.

The app's deployment, its Agent named-pipe interface, and end-user application
assignments are independent lifecycle stages. Do not auto-assign a custom
application to the whole estate as a workaround.

## Recovery / retention

Packages are not included in the PostgreSQL logical backup and must receive
separate encrypted off-host backups, integrity checks, quota/retention rules,
revision retirement and protected download access prior to commercial rollout.
The host directory is not publicly web-served; package download should only
use existing Agent-authenticated time-limited tokens.

This runbook documents a verified managed-VPS hotfix. It is not itself an
authorization to change infrastructure on the EU environment.
