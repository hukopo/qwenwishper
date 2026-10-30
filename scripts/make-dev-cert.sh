#!/bin/zsh
# One-time: create a self-signed code-signing identity so macOS keeps
# Accessibility/Microphone grants across dev rebuilds (ad-hoc signatures change every build).
set -euo pipefail

NAME="QwenWhisper Dev"
if security find-certificate -c "$NAME" >/dev/null 2>&1; then
  echo "✓ '$NAME' already in login keychain"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -subj "/CN=$NAME" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null

# -legacy: `security import` can't read OpenSSL 3 default PKCS#12 encryption.
LEGACY=""; openssl pkcs12 -help 2>&1 | grep -q -- -legacy && LEGACY="-legacy"
openssl pkcs12 -export $LEGACY -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -name "$NAME" -passout pass:qw -out "$TMP/id.p12"

security import "$TMP/id.p12" -k ~/Library/Keychains/login.keychain-db -P qw -T /usr/bin/codesign
echo "✓ '$NAME' created. Sign with: codesign --force --sign \"$NAME\" <app>"
