#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/QwenWhisper.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
EXECUTABLE_NAME="QwenWhisperApp"
BUNDLE_ID="com.hukopo.qwenwhisper"

# MLX Metal shader library – required for Qwen (GPU inference).
# Cached in .build/ so it survives swift build cleans but not git cleans.
MLX_METALLIB_CACHE="$ROOT_DIR/.build/mlx.metallib"
# Version must match mlx-swift in Package.resolved.
MLX_VERSION="0.30.6"
MLX_WHEEL_URL="https://files.pythonhosted.org/packages/f3/85/44406b521f920248fad621334d4dc15e77660a494edf890e7cbee33bf38d/mlx_metal-${MLX_VERSION}-py3-none-macosx_14_0_arm64.whl"

ensure_mlx_metallib() {
  if [[ -f "$MLX_METALLIB_CACHE" ]]; then
    echo "✓ mlx.metallib cached at .build/mlx.metallib"
    return
  fi

  # Check if full Xcode is available – it can compile shaders natively.
  if xcrun -sdk macosx metal --version &>/dev/null; then
    echo "Xcode metal compiler found – skipping PyPI download."
    return
  fi

  echo "Downloading mlx.metallib v${MLX_VERSION} from PyPI (one-time, ~37 MB)…"
  local TMP_WHEEL
  TMP_WHEEL="$(mktemp /tmp/mlx_metal_XXXXXX.whl)"
  curl -fsSL "$MLX_WHEEL_URL" -o "$TMP_WHEEL"
  unzip -p "$TMP_WHEEL" "mlx/lib/mlx.metallib" > "$MLX_METALLIB_CACHE"
  rm -f "$TMP_WHEEL"
  echo "✓ mlx.metallib saved to .build/mlx.metallib ($(du -sh "$MLX_METALLIB_CACHE" | cut -f1))"
}

# Kill any running instance
pkill -x "$EXECUTABLE_NAME" 2>/dev/null && sleep 0.5 || true

# Ensure MLX Metal shaders are available before building the bundle.
ensure_mlx_metallib

# Build (debug by default; pass --release for optimised build)
cd "$ROOT_DIR"
if [[ "${1:-}" == "--release" ]]; then
  swift build -c release
  SRC="$ROOT_DIR/.build/arm64-apple-macosx/release/$EXECUTABLE_NAME"
else
  swift build
  SRC="$ROOT_DIR/.build/arm64-apple-macosx/debug/$EXECUTABLE_NAME"
fi

# Assemble a minimal app bundle in dist/
mkdir -p "$MACOS_DIR" "$CONTENTS_DIR/Resources"
cp "$SRC" "$MACOS_DIR/$EXECUTABLE_NAME"
chmod +x "$MACOS_DIR/$EXECUTABLE_NAME"

# Copy MLX Metal shaders next to the executable so MLX can load them.
if [[ -f "$MLX_METALLIB_CACHE" ]]; then
  cp "$MLX_METALLIB_CACHE" "$MACOS_DIR/mlx.metallib"
fi

cat > "$CONTENTS_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>        <string>$EXECUTABLE_NAME</string>
  <key>CFBundleIdentifier</key>        <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>              <string>QwenWhisper</string>
  <key>CFBundlePackageType</key>       <string>APPL</string>
  <key>CFBundleShortVersionString</key><string>dev</string>
  <key>LSMinimumSystemVersion</key>    <string>14.0</string>
  <key>LSUIElement</key>               <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>QwenWhisper records microphone audio for local dictation.</string>
</dict>
</plist>
EOF

echo "Launching $APP_DIR …"
open "$APP_DIR"
