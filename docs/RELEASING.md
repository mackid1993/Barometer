# Releasing Barometer

Barometer's GitHub workflows run only when manually dispatched. A build produces a Developer ID-signed DMG.
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
the hardened runtime, builds `Barometer-VERSION.dmg`, verifies both artifacts, and deletes the temporary certificate.

## Create a draft release

Open **Actions → Release → Run workflow**, enter the version and optional release notes, and leave notarization off.
The workflow creates or updates a draft GitHub release and attaches only the DMG. Review the draft before publishing
it.

## Optional future notarization

After the three Apple account secrets are configured, explicitly enable the notarization checkbox on a Build macOS
or Release dispatch. The workflow submits the DMG with `notarytool`, waits for acceptance, staples the ticket, and
validates it before upload. Merely pushing a commit never signs, notarizes, or releases anything.
