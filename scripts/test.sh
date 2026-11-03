#!/bin/sh
# Corre los tests de Swift Testing del núcleo del switcher.
set -eu
cd "$(dirname "$0")/.."

# El núcleo es Swift puro: falla si algún archivo importa frameworks de UI o
# del sistema de ventanas (también `@testable import`, `import struct X.Y`, etc.).
FORBIDDEN='AppKit|Cocoa|ApplicationServices|CoreGraphics|Carbon'
if grep -rnE "^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*import[[:space:]]+([a-z]+[[:space:]]+)?($FORBIDDEN)([.[:space:]]|$)" \
  --include='*.swift' Sources/SwitchaleCore; then
  echo "error: Sources/SwitchaleCore no puede importar $FORBIDDEN" >&2
  exit 1
fi

xcodegen generate --quiet
xcodebuild test \
  -project Switchale.xcodeproj \
  -scheme SwitchaleCore \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  -quiet
