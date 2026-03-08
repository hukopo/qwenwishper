#!/bin/zsh
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <version>" >&2
  exit 1
fi

VERSION="$1"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="QwenWhisper"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
EXECUTABLE_SRC="$ROOT_DIR/.build/arm64-apple-macosx/release/QwenWhisperApp"
EXECUTABLE_DST="$MACOS_DIR/QwenWhisperApp"
ZIP_PATH="$DIST_DIR/${APP_NAME}-${VERSION}-macos-arm64.zip"

rm -rf "$APP_DIR" "$ZIP_PATH"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cd "$ROOT_DIR"
swift build -c release

cp "$EXECUTABLE_SRC" "$EXECUTABLE_DST"
chmod +x "$EXECUTABLE_DST"

cat > "$CONTENTS_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>QwenWhisperApp</string>
  <key>CFBundleIdentifier</key>
  <string>com.hukopo.qwenwhisper</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>QwenWhisper</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>QwenWhisper records microphone audio for local dictation.</string>
</dict>
</plist>
EOF

ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

echo "Created:"
echo "  $APP_DIR"
echo "  $ZIP_PATH"
