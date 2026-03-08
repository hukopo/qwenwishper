#!/bin/zsh
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <artifact-path>" >&2
  exit 1
fi

ARTIFACT_PATH="$1"

if [[ ! -f "$ARTIFACT_PATH" ]]; then
  echo "artifact not found: $ARTIFACT_PATH" >&2
  exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
  echo "xcrun is required for notarization" >&2
  exit 1
fi

submit_with_profile() {
  xcrun notarytool submit "$ARTIFACT_PATH" \
    --keychain-profile "$NOTARYTOOL_PROFILE" \
    --wait
}

submit_with_apple_id() {
  xcrun notarytool submit "$ARTIFACT_PATH" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" \
    --wait
}

if [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
  submit_with_profile
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
  submit_with_apple_id
else
  echo "missing notarization credentials" >&2
  echo "set NOTARYTOOL_PROFILE or APPLE_ID, APPLE_APP_SPECIFIC_PASSWORD, and APPLE_TEAM_ID" >&2
  exit 1
fi

if [[ "$ARTIFACT_PATH" == *.dmg ]]; then
  xcrun stapler staple "$ARTIFACT_PATH"
elif [[ "$ARTIFACT_PATH" == *.app ]]; then
  xcrun stapler staple "$ARTIFACT_PATH"
fi

echo "Notarized: $ARTIFACT_PATH"
