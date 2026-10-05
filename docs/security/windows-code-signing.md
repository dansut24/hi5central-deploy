# Windows executable signing

## Default distribution model

Hi5Central signs the Windows binaries it publishes. Standard self-hosters and MSPs do not need a code-signing certificate simply to deploy Hi5Central.

The signed release set includes, as applicable:

- Agent service and installer;
- unattended/attended remote-control components;
- Viewer;
- Connect portable client;
- PatchHost and helper executables/DLLs;
- App Portal;
- updater/uninstaller;
- MSI/EXE bootstrap installers.

Signing is a release operation, not a customer deployment operation.

## Release pipeline

1. Build from an immutable release commit.
2. Generate hashes/SBOM/provenance.
3. Authenticode-sign PE/MSI artifacts using an organisational code-signing identity held in a protected signing service/HSM.
4. Apply an RFC 3161 timestamp.
5. Verify the Authenticode chain and timestamp.
6. Recalculate and publish SHA-256 hashes.
7. Publish only verified artifacts.
8. Record the signer, build commit, version and hash in release metadata.

The signing private key must not be copied to a VPS, committed to Git, baked into a container or distributed to a customer.

## Self-hosters

A self-hoster normally deploys Hi5Central-signed binaries unchanged. Internal deployment tools such as Intune, RMM, GPO or software distribution systems can deploy those binaries without re-signing them.

Customers may sign their own wrapper/bootstrap package if organisational policy requires their own publisher identity. Modifying a signed Hi5Central binary invalidates its original signature and is not part of the supported deployment flow.

## MSP white-labelling

Runtime branding (logo, colours, organisation name, support details, portal names and tenant configuration) does not modify the executable and therefore does not affect its signature.

Windows' Publisher identity comes from the signing certificate, not from the MSP branding record. Therefore the default white-label model keeps the trusted Hi5Central publisher on the core binaries.

For MSPs that require their own Publisher identity, use an MSP-signed bootstrap/wrapper that enrols/downloads the normal Hi5Central-signed core components. A fully rebranded binary would require a separate build/signing pipeline and the MSP's own signing identity; it should not be the default model.

## Verification

Windows release CI must fail if a required artifact is unsigned, has an invalid signature, lacks the expected signer, fails timestamp validation, or its published SHA-256 does not match the final signed artifact.
