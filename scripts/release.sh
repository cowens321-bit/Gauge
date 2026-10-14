#!/bin/bash
# Usage: scripts/release.sh <version> ["release notes"]
#   e.g. scripts/release.sh 1.1.0 "Fixes the menu bar graph spacing"
#
# Builds Gauge, packages dist/Gauge-<version>.dmg, signs it for Sparkle (EdDSA key in your login Keychain),
# publishes a GitHub release with the DMG, then updates appcast.xml on main. Installed copies of Gauge
# check that appcast and update themselves, so DMGs never need to be re-downloaded by hand.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/release.sh <version> [notes]}"
NOTES="${2:-Gauge $VERSION}"
REPO="cowens321-bit/Gauge"
TAG="v$VERSION"
TOOLS=".tools/bin"
[ -x "$TOOLS/sign_update" ] || { echo "Missing $TOOLS/sign_update (download Sparkle 2.10.0 tools into .tools/bin)"; exit 1; }

# Build number must strictly increase for Sparkle; derive it from the current one.
CUR_BUILD=$(grep -E 'CURRENT_PROJECT_VERSION: "' project.yml | head -1 | sed -E 's/.*"([0-9]+)".*/\1/')
BUILD=$((CUR_BUILD + 1))
[ "$VERSION" = "$(grep -E 'MARKETING_VERSION: "' project.yml | head -1 | sed -E 's/.*"([^"]+)".*/\1/')" ] && BUILD=$CUR_BUILD  # re-release of same version keeps its build
sed -i '' -E "s/(MARKETING_VERSION: )\"[^\"]+\"/\1\"$VERSION\"/; s/(CURRENT_PROJECT_VERSION: )\"[0-9]+\"/\1\"$BUILD\"/" project.yml

# gh: use the personal account for this repo, restore whatever was active afterwards.
PREV=$(gh api user --jq .login 2>/dev/null || true)
trap '[ -n "$PREV" ] && [ "$PREV" != "cowens321-bit" ] && gh auth switch -u "$PREV" >/dev/null 2>&1 || true' EXIT
gh auth switch -u cowens321-bit >/dev/null

echo "▸ Building $VERSION ($BUILD)…"
xcodegen generate >/dev/null
xcodebuild -project Gauge.xcodeproj -scheme Gauge -configuration Release -derivedDataPath build build | tail -1
APP="build/Build/Products/Release/Gauge.app"

echo "▸ Running tests…"
TEST_OUT=$(scripts/test.sh 2>&1) || true
SUMMARY=$(echo "$TEST_OUT" | grep -E "Executed [0-9]+ tests" | tail -1)   # the final line is the overall total
echo "$SUMMARY"
echo "$SUMMARY" | grep -qE "with 0 failures" || { echo "Tests failed – aborting release"; echo "$TEST_OUT" | grep -E "error:" | head; exit 1; }

echo "▸ Packaging DMG…"
mkdir -p dist; STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/Gauge.app"; ln -s /Applications "$STAGE/Applications"
DMG="dist/Gauge-$VERSION.dmg"; rm -f "$DMG"
hdiutil create -quiet -volname "Gauge $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 "$DMG"
rm -rf "$STAGE"; rm -rf dist/Gauge.app; cp -R "$APP" dist/Gauge.app

echo "▸ Signing for Sparkle…"
SIG_LINE=$("$TOOLS/sign_update" "$DMG")            # sparkle:edSignature="…" length="…"

echo "▸ Committing and tagging…"
git add -A
git commit -q -m "Release $VERSION" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>" || true
git tag -f "$TAG" >/dev/null
git push -q origin main
git push -q -f origin "$TAG"

echo "▸ Publishing GitHub release…"
gh release delete "$TAG" -y --repo "$REPO" >/dev/null 2>&1 || true
gh release create "$TAG" "$DMG" --repo "$REPO" --title "Gauge $VERSION" --notes "$NOTES" >/dev/null

echo "▸ Updating appcast…"
URL="https://github.com/$REPO/releases/download/$TAG/Gauge-$VERSION.dmg"
DATE=$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")
cat > appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Gauge</title>
    <item>
      <title>Version $VERSION</title>
      <pubDate>$DATE</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <description><![CDATA[$NOTES]]></description>
      <enclosure url="$URL" type="application/octet-stream" $SIG_LINE />
    </item>
  </channel>
</rss>
XML
git add appcast.xml
git commit -q -m "Appcast for $VERSION" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
git push -q origin main
echo "✓ Released $VERSION → https://github.com/$REPO/releases/tag/$TAG"
echo "  DMG: $DMG"
