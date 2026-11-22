#!/bin/zsh
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <version>" >&2
  exit 1
fi

VERSION="$1"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="${APP_NAME:-QwenWhisper}"
EXECUTABLE_NAME="${EXECUTABLE_NAME:-QwenWhisperApp}"
BUNDLE_ID="${BUNDLE_ID:-com.hukopo.qwenwhisper}"
MIN_OS_VERSION="${MIN_OS_VERSION:-14.0}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
ENTITLEMENTS_PATH="${ENTITLEMENTS_PATH:-$ROOT_DIR/scripts/macos/entitlements.plist}"
# MLX Metal shaders — must be bundled next to the executable for Qwen inference.
# Path is taken from the env or the default dev-build cache location.
MLX_METALLIB="${MLX_METALLIB:-$ROOT_DIR/.build/mlx.metallib}"
MLX_VERSION="0.32.2"
MLX_WHEEL_URL="https://files.pythonhosted.org/packages/f7/ab/ba1952908c5d2a5070cf1cfbfea0161c4751ea62299e2776819810917483/mlx_metal-${MLX_VERSION}-py3-none-macosx_14_0_arm64.whl"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
EXECUTABLE_SRC="$ROOT_DIR/.build/arm64-apple-macosx/release/$EXECUTABLE_NAME"
EXECUTABLE_DST="$MACOS_DIR/$EXECUTABLE_NAME"
ZIP_PATH="$DIST_DIR/${APP_NAME}-${VERSION}-macos-arm64.zip"
DMG_STAGING_DIR="$DIST_DIR/${APP_NAME}-dmg-staging"
DMG_PATH="$DIST_DIR/${APP_NAME}-${VERSION}-macos-arm64.dmg"

sign_app_bundle() {
  local path="$1"

  if [[ -z "$SIGNING_IDENTITY" ]]; then
    return 0
  fi

  codesign \
    --force \
    --sign "$SIGNING_IDENTITY" \
    --timestamp \
    --options runtime \
    --entitlements "$ENTITLEMENTS_PATH" \
    "$path"
}

sign_disk_image() {
  local path="$1"

  if [[ -z "$SIGNING_IDENTITY" ]]; then
    return 0
  fi

  codesign \
    --force \
    --sign "$SIGNING_IDENTITY" \
    --timestamp \
    "$path"
}

rm -rf "$APP_DIR" "$ZIP_PATH" "$DMG_STAGING_DIR" "$DMG_PATH"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# Ensure mlx.metallib is available (download from PyPI if not cached).
if [[ ! -f "$MLX_METALLIB" ]]; then
  echo "mlx.metallib not found at $MLX_METALLIB — downloading from PyPI (one-time, ~37 MB)…"
  mkdir -p "$(dirname "$MLX_METALLIB")"
  TMP_WHEEL="$(mktemp /tmp/mlx_metal_XXXXXX.whl)"
  curl -fsSL "$MLX_WHEEL_URL" -o "$TMP_WHEEL"
  unzip -p "$TMP_WHEEL" "mlx/lib/mlx.metallib" > "$MLX_METALLIB"
  rm -f "$TMP_WHEEL"
  echo "✓ mlx.metallib saved ($(du -sh "$MLX_METALLIB" | cut -f1))"
else
  echo "✓ mlx.metallib found at $MLX_METALLIB ($(du -sh "$MLX_METALLIB" | cut -f1))"
fi

cd "$ROOT_DIR"
swift build -c release

cp "$EXECUTABLE_SRC" "$EXECUTABLE_DST"
chmod +x "$EXECUTABLE_DST"

# Bundle the MLX Metal shaders so Qwen works without Xcode on end-user machines.
cp "$MLX_METALLIB" "$MACOS_DIR/mlx.metallib"
echo "✓ mlx.metallib bundled into app"

# Bundle the SwiftPM resource bundles, otherwise Bundle.module traps at runtime with
# "could not load resource bundle" (opening Settings crashes on the hotkey recorder).
# Where the generated accessor looks depends on the build system:
#   - swiftbuild backend: Contents/Resources (Bundle.main.resourceURL)
#   - native SwiftPM (CI today): the .app root (Bundle.main.bundleURL) + a hardcoded build path
BIN_PATH="$(swift build -c release --show-bin-path)"
RESOURCE_BUNDLES=("$BIN_PATH"/*.bundle(N))
if (( ${#RESOURCE_BUNDLES} == 0 )); then
  echo "error: no SwiftPM resource bundles found in $BIN_PATH" >&2
  exit 1
fi
BUNDLE_DST="$RESOURCES_DIR"
if strings "$EXECUTABLE_DST" | grep -q 'could not load resource bundle: from'; then
  # ponytail: root content can't be sealed by codesign; switch to swiftbuild before signing releases.
  if [[ -n "$SIGNING_IDENTITY" ]]; then
    echo "error: native SwiftPM accessor needs bundles in the .app root, which codesign rejects" >&2
    exit 1
  fi
  BUNDLE_DST="$APP_DIR"
fi
for bundle in "${RESOURCE_BUNDLES[@]}"; do
  cp -R "$bundle" "$BUNDLE_DST/"
  echo "✓ bundled $(basename "$bundle") into ${BUNDLE_DST#$DIST_DIR/}"
done

cat > "$CONTENTS_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>${EXECUTABLE_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${VERSION}</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.productivity</string>
  <key>LSMinimumSystemVersion</key>
  <string>${MIN_OS_VERSION}</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>QwenWhisper records microphone audio for local dictation.</string>
</dict>
</plist>
EOF

if [[ -n "$SIGNING_IDENTITY" ]]; then
  sign_app_bundle "$APP_DIR"
  codesign --verify --deep --strict --verbose=2 "$APP_DIR"
  spctl --assess --type execute --verbose=2 "$APP_DIR" || true
fi

ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

mkdir -p "$DMG_STAGING_DIR"
cp -R "$APP_DIR" "$DMG_STAGING_DIR/"
ln -s /Applications "$DMG_STAGING_DIR/Applications"

# Bundle the installer script so users can double-click to install without quarantine issues.
INSTALL_SCRIPT="$ROOT_DIR/scripts/install.command"
if [[ -f "$INSTALL_SCRIPT" ]]; then
  cp "$INSTALL_SCRIPT" "$DMG_STAGING_DIR/Install QwenWhisper.command"
  chmod +x "$DMG_STAGING_DIR/Install QwenWhisper.command"
fi

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

if [[ -n "$SIGNING_IDENTITY" ]]; then
  sign_disk_image "$DMG_PATH"
  codesign --verify --verbose=2 "$DMG_PATH"
fi

rm -rf "$DMG_STAGING_DIR"

echo "Created:"
echo "  $APP_DIR"
echo "  $ZIP_PATH"
echo "  $DMG_PATH"
if [[ -n "$SIGNING_IDENTITY" ]]; then
  echo "Signed with: $SIGNING_IDENTITY"
else
  echo "Signed with: none (unsigned build)"
fi
