# Second VPS self-host acceptance test

Use a clean VPS that has never hosted Hi5Central. This is the release gate for the public self-host installer.

## Recommended test host

- Ubuntu LTS
- 4 GiB RAM minimum; 8 GiB recommended for full ITSM + RMM testing
- 40+ GiB free disk
- public IPv4 where remote access/TURN is being tested
- Docker Engine
- Docker Compose v2
- DNS records available for the chosen test domain

Do not copy the existing production `.env`, Docker volumes or database to this host for the fresh-install tests.

## Candidate branch test

Until the installer PR is merged:

```sh
git clone --branch selfhost-guided-installer https://github.com/dansut24/hi5central-deploy.git
cd hi5central-deploy
./install.sh
```

For a release-candidate image set choose **Early Access**. After Stable publication choose **Stable**.

## Pass 1 — default customer path

Use:

- Standard
- ITSM + RMM
- automatic HTTPS
- Stable (or Early Access while validating the candidate)
- default ports
- default hostnames
- SMTP later
- automatically generated secrets

Accept defaults wherever possible.

Required result:

- configuration validation passes;
- port/DNS preflight is understandable and actionable;
- images pull successfully;
- PostgreSQL and Redis become healthy;
- migrations complete;
- API becomes healthy;
- ITSM and RMM become healthy;
- Caddy serves valid HTTPS;
- coturn starts;
- login/first account creation works;
- ITSM can create/read a record;
- RMM UI loads;
- a Windows/Linux/macOS agent can obtain the correct deployment package;
- an enrolled device reports online;
- terminal/files work where supported;
- a remote session can be initiated;
- downloads hostname serves expected artifacts.

## Pass 2 — advanced/manual path

Wipe the candidate deployment and Docker volumes, then reinstall using:

- custom host ports;
- manual secrets;
- optional custom hostnames;
- one-product selection, then repeat for the other if needed;
- MSP configure-only mode to validate the Admin profile without consuming a real licence.

Required result:

- manual secrets are never echoed;
- invalid secrets are rejected before startup;
- conflicting ports are rejected before startup;
- custom URLs/ports are written correctly;
- Standard does not expose Admin;
- MSP profile includes Admin;
- unused product web services are not started.

## Update test

With Pass 1 running:

1. create normal application test data;
2. run `./scripts/update.sh`;
3. confirm a pre-update backup is created;
4. publish/promote a newer candidate on the same channel;
5. run the updater again;
6. verify migrations and health checks complete;
7. verify test data remains intact;
8. verify Agent/Viewer/App Portal download metadata remains valid.

## Backup/restore test

1. create incidents/devices/test configuration;
2. run `./backup.sh`;
3. stop the stack;
4. restore the backup into a clean deployment state;
5. verify users, ITSM data, RMM data and configuration;
6. verify secrets and permissions remain protected.

## Failure tests

Deliberately test:

- DNS missing;
- TCP 80 occupied;
- TCP/UDP 443 occupied;
- TURN port occupied;
- insufficient/invalid manual secret;
- invalid release channel;
- platform image configured as `:latest`;
- unavailable image tag;
- interrupted image pull;
- failed container health check.

Errors should state what is wrong and leave existing data recoverable.

## Release gate

A self-host release is approved only when:

- deployment CI is green;
- Platform candidate is already proven in Hi5Central Production;
- fresh Standard install passes;
- advanced/manual configuration passes;
- update passes;
- backup/restore passes;
- ITSM/RMM core smoke tests pass;
- Agent deployment works;
- remote access/TURN works;
- no source repositories or private signing material are required by the customer host.

Record the tested Platform commit SHA and self-host version with the release notes.
