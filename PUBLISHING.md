# Hi5Central repository publishing map

This file defines the canonical repository and artifact boundaries for the split Hi5Central platform.

## Repositories

| Local repository | GitHub target | Current local commit | Published artifact |
| --- | --- | --- | --- |
| hi5central-control-server | dansut24/hi5central-control-server | 459bf04ba5d0 | ghcr.io/dansut24/hi5central-control-server |
| hi5central-itsm | dansut24/hi5central-itsm | 714c4589202a | ghcr.io/dansut24/hi5central-itsm |
| hi5central-rmm | dansut24/hi5central-rmm | 19fcb5054c0a | ghcr.io/dansut24/hi5central-rmm |
| hi5central-admin | dansut24/hi5central-admin | 4c1f8e4751e3 | ghcr.io/dansut24/hi5central-admin |
| Hi5Central-Agent | dansut24/Hi5Central-Agent | existing production repo | Native Agent installers/packages |
| hi5central-app-portal | dansut24/hi5central-app-portal | f2224a291c84 | Native App Portal builds |
| hi5central-viewer | dansut24/hi5central-viewer | f909d4a646d7 | Native Viewer installers/builds |
| hi5central-deploy | dansut24/hi5central-deploy | this repository | Compose/self-host deployment |

## Ownership rules

- Control Server is the only database migration owner until backend services are deliberately separated.
- ITSM owns the analyst workspace and browser requester Self-Service frontend.
- RMM owns the RMM web frontend.
- Admin owns the platform administration and software-qualification UI.
- Software qualification orchestration remains in Control Server for now.
- Agent owns privileged endpoint execution and the cross-platform endpoint service.
- App Portal owns the native end-user software portal and talks to Agent through a local authenticated broker.
- Viewer owns the native remote-session viewer and is versioned independently from Agent.
- Deploy owns Compose, Caddy/gateway, TURN, self-host configuration and deployment scripts.

## Publishing sequence

1. Create/grant access to the seven new private GitHub repositories.
2. Push the prepared local `main` branch of each repository.
3. Require the independent CI workflow to pass before any cutover.
4. Publish Control Server, ITSM, RMM and Admin images to GHCR.
5. Publish App Portal and Viewer native build artifacts.
6. Pin `hi5central-deploy` image variables to immutable release tags.
7. Run the split stack side-by-side with production against a cloned/test database.
8. Validate authentication, ITSM, RMM, Admin, Agent jobs, Viewer sessions and App Portal APIs.
9. Switch live gateway routes one surface at a time.
10. Only after successful cutover remove duplicated source from `lsl-itsm-platform` and `Hi5Central-Agent`.

## Production release policy

- Never deploy `latest` in a production self-hosted release manifest.
- Tag server images with a semantic release tag and immutable SHA tag.
- Deploy repository releases pin all component versions together.
- Native Agent, Viewer and App Portal versions are independently versioned but compatibility is documented in each Deploy release.
- Database migrations execute once through the Control Server `migrate` service before Control Server starts.

## Legacy repositories

`lsl-itsm-platform` remains the production rollback source until ITSM, RMM, Admin and Control Server have completed side-by-side cutover. It should then be archived rather than immediately deleted.

`Hi5Central-Agent` remains the production Agent source. App Portal and Viewer source copies stay in that repository until their standalone repositories have completed their first successful GitHub CI/release and Agent packaging has been changed to consume pinned release artifacts.
