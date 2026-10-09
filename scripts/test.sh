#!/bin/bash
# Builds the (unhosted) test bundle and runs it with xctest. `xcodebuild test` is avoided because a
# failing assertion inside an app-hosted bundle can hang the runner.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate >/dev/null
xcodebuild -project Gauge.xcodeproj -scheme Gauge -derivedDataPath build build-for-testing | tail -1
xcrun xctest build/Build/Products/Debug/GaugeTests.xctest
