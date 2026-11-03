#!/bin/sh
# Corre los tests de Swift Testing del núcleo del switcher.
set -eu
cd "$(dirname "$0")/.."

xcodegen generate --quiet
xcodebuild test \
  -project Switchale.xcodeproj \
  -scheme SwitchaleCore \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  -quiet
