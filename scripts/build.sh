#!/bin/sh
# Compila switchale.app firmada con Apple Development.
# Uso: scripts/build.sh [Debug|Release]   (por defecto Debug)
# Resultado: build/DerivedData/Build/Products/<config>/switchale.app
set -eu
cd "$(dirname "$0")/.."

CONFIG="${1:-Debug}"

xcodegen generate --quiet
xcodebuild build \
  -project Switchale.xcodeproj \
  -scheme Switchale \
  -configuration "$CONFIG" \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  -quiet

echo "build/DerivedData/Build/Products/$CONFIG/switchale.app"
