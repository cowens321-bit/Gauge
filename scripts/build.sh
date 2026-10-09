#!/bin/bash
# Regenerates the Xcode project, builds a Release Gauge.app and copies it to ./dist
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate
xcodebuild -project Gauge.xcodeproj -scheme Gauge -configuration Release -derivedDataPath build build
mkdir -p dist && rm -rf dist/Gauge.app && cp -R build/Build/Products/Release/Gauge.app dist/Gauge.app
echo "Built dist/Gauge.app"
