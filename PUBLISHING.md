# Hi5Central publishing model

## Canonical repositories

### Hi5Central-Platform — private

Canonical application/product monorepo containing:

- API / Control Server
- ITSM
- RMM
- Platform/MSP Admin
- Agent build sources and packaging
- Viewer build sources and packaging
- App Portal build sources and packaging
- shared packages
- CI and product release workflows

Platform container images are published to GHCR using immutable `sha-<commit>` tags first.

### hi5central-deploy — public

Public self-host distribution surface containing:

- Compose
- Caddy/gateway configuration
- coturn configuration
- guided installer
- validation/preflight
- updater
- backup/restore
- self-host documentation

Self-hosters do not require source access to the private monorepo.

## Internal environments

Hi5Central operates two hosted application environments:

1. **Development** — receives approved development builds for integration testing.
2. **Production** — live Hi5Central service; receives a tested immutable image set.

Production and self-host release publication are deliberately separate decisions.

## Build once, promote

Each platform commit is built into immutable images:

```text
ghcr.io/dansut24/hi5central-platform-api:sha-<commit>
ghcr.io/dansut24/hi5central-platform-itsm:sha-<commit>
ghcr.io/dansut24/hi5central-platform-rmm:sha-<commit>
ghcr.io/dansut24/hi5central-platform-admin:sha-<commit>
```

Development/Production aliases point to those already-built images. A self-host release also promotes the already-built SHA; it does not rebuild application code.

## Self-host release publication

After a Production deployment has passed smoke testing, run the **Publish Self-Hosted Release** workflow in `Hi5Central-Platform`.

Inputs:

- exact 40-character tested commit SHA;
- semantic version, e.g. `v1.4.0` or `v1.5.0-rc.1`;
- channel: `stable` or `early-access`.

The workflow verifies all required immutable images exist, then promotes the exact set to:

```text
:<semantic-version>
:<selected-channel>
```

No image is rebuilt during publication.

## Policy

- Never use `:latest` in a self-host release.
- Stable is the default self-host channel.
- Early Access is opt-in.
- A push/merge to Production never changes Stable automatically.
- Database migrations are owned by the Control Server migration service.
- Native Agent/Viewer/App Portal artifacts remain independently versioned but their compatible versions must be recorded with each platform release.
- Self-host deployment changes are validated independently in `hi5central-deploy`.
- Fresh-install acceptance is performed on a clean VPS before the deployment package is declared production-ready.

## Legacy repositories

Older split repositories remain rollback/history sources while the monorepo cutover is being completed. New product development and release orchestration should target `Hi5Central-Platform`; do not introduce new cross-repository build dependencies unless there is a deliberate exception.
