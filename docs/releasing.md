# Releasing QwenWhisper

This repository can produce a standalone macOS `.app`, `.zip`, and `.dmg` from the SwiftPM executable.

## Requirements

- Apple Silicon Mac
- macOS 14+
- full Xcode installation for the cleanest release builds
- Developer ID Application certificate for signing
- Apple notarization credentials

## Local Unsigned Build

```bash
./scripts/package_release.sh 0.0.2
```

Artifacts:

- `dist/QwenWhisper.app`
- `dist/QwenWhisper-0.0.2-macos-arm64.zip`
- `dist/QwenWhisper-0.0.2-macos-arm64.dmg`

## Local Signed Build

Export these environment variables first:

```bash
export SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export APPLE_ID="name@example.com"
export APPLE_APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx"
export APPLE_TEAM_ID="TEAMID"
```

Then run:

```bash
./scripts/package_release.sh 0.0.2
./scripts/notarize_release.sh dist/QwenWhisper-0.0.2-macos-arm64.dmg
```

## GitHub Actions Release

The workflow at `.github/workflows/release.yml` builds on tag push `v*`.

Required repository secrets for a signed and notarized release:

- `DEVELOPER_ID_APPLICATION`
- `DEVELOPER_ID_APPLICATION_CERT_BASE64`
- `DEVELOPER_ID_APPLICATION_CERT_PASSWORD`
- `BUILD_KEYCHAIN_PASSWORD`
- `APPLE_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`
- `APPLE_TEAM_ID`

Behavior:

- if signing secrets are present, the workflow signs the app and the DMG
- if notarization secrets are present, the workflow notarizes and staples the DMG
- release assets are uploaded to the GitHub Release for that tag

## Recommended Release Flow

1. Commit changes on `main`.
2. Create and push a version tag like `v0.0.2`.
3. Wait for the GitHub Actions workflow to finish.
4. Download the generated `.dmg` from the GitHub Release.
5. Verify the final app on a clean Apple Silicon Mac before announcing the release.
