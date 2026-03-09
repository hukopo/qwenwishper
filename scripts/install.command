#!/bin/bash
# QwenWhisper installer — removes macOS quarantine and copies app to /Applications.
# Double-click this file from the DMG to install without Gatekeeper errors.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_SRC="$SCRIPT_DIR/QwenWhisper.app"
APP_DEST="/Applications/QwenWhisper.app"

echo "Installing QwenWhisper…"

if [[ ! -d "$APP_SRC" ]]; then
  echo "Error: QwenWhisper.app not found next to this script." >&2
  exit 1
fi

# Quit existing instance if running.
if pgrep -x QwenWhisperApp >/dev/null 2>&1; then
  echo "Quitting existing QwenWhisper…"
  pkill -x QwenWhisperApp || true
  sleep 1
fi

# Copy app to Applications, replacing any previous version.
echo "Copying to /Applications…"
rm -rf "$APP_DEST"
cp -R "$APP_SRC" "$APP_DEST"

# Remove macOS quarantine so the app opens without "damaged" errors.
echo "Removing quarantine attribute…"
xattr -cr "$APP_DEST"

echo ""
echo "✓ QwenWhisper installed to /Applications"
echo "  Open Spotlight (⌘ Space) and search for QwenWhisper to launch."
echo ""
echo "Press any key to close this window."
read -n1 -s
