# Releasing Barometer

Barometer's build, check, and release workflows run only when manually dispatched. A build produces a Developer
ID-signed DMG.
The Check and Build macOS workflows share a required Tests job. Packaging and certificate import start only
when that job passes; Release inherits this gate through Build macOS. `make test` executes Swift Testing even
with the Command Line Tools installation used for local development.
Notarization is disabled by default and runs only when the person dispatching the workflow explicitly enables it.

## Repository secrets

Create these under **Settings → Secrets and variables → Actions**:

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE` | Base64-encoded Developer ID Application `.p12` |
| `MACOS_CERTIFICATE_PASSWORD` | Password used when exporting the `.p12` |
| `APPLE_ID` | Apple Developer account email; needed only for notarization |
| `APPLE_TEAM_ID` | Ten-character Apple Developer team ID; needed only for notarization |
| `APPLE_APP_PASSWORD` | Apple ID app-specific password; needed only for notarization |

Encode the certificate without copying binary data into the browser:

```bash
base64 -i ~/Desktop/DeveloperIDApplication.p12 | pbcopy
```

Paste the clipboard into the `MACOS_CERTIFICATE` secret. Never commit the `.p12`, its password, or the encoded
certificate.

## Build a signed DMG

1. Open **Actions → Build macOS → Run workflow**.
2. Enter a `major.minor.patch` version.
3. Leave **Notarize and staple the DMG** off.
4. Download the `barometer-dmg` artifact after the job succeeds.

The workflow imports the certificate into an ephemeral keychain, signs the single `Barometer.app` executable with
the hardened runtime, stamps the requested version into the app bundle, builds `Barometer-VERSION.dmg`, verifies the
stamped version and both artifacts, and deletes the temporary certificate. CI supplies the release version directly;
the repository `VERSION` file is only the fallback for local development builds.

## Prepare a release

Open **Actions → Release → Run workflow**, enter the version and optional release notes, and choose whether to
notarize. After every build, signing, and requested notarization check passes, the workflow creates or refreshes a
**draft** GitHub release and attaches only the versioned DMG.

The workflow never publishes. A draft is not public, is not tagged latest, and does not appear on the releases page
to anyone else, so the notes and the notarized DMG can be reviewed before anything ships.

To ship it, open **Releases**, check the draft, and press **Publish release**. GitHub marks it latest at that point.

Re-dispatching the same version refreshes the draft and replaces its DMG. If that version has already been
published the workflow fails instead, because rewriting a public release would change what people have already
downloaded; bump the version instead.

Pushing a commit never builds, signs, notarizes, or releases anything. This workflow remains manual-dispatch only.

## Optional future notarization

After the three Apple account secrets are configured, explicitly enable the notarization checkbox on a Build macOS
or Release dispatch. The workflow submits the DMG with `notarytool`, waits for acceptance, staples the ticket, and
validates it before upload. Merely pushing a commit never signs, notarizes, or releases anything.
