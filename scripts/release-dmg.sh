#!/bin/bash
# Produces a signed, notarized, stapled LUTzy-<version>.dmg for direct distribution.
#
# `Package.swift` has no app target, so this script does what an Xcode archive would: builds the
# universal release executable, wraps it in a LUTzy.app bundle with an Info.plist and the icon,
# signs it with a Developer ID identity and the hardened runtime, notarizes and staples the app,
# packages it into a DMG, then signs, notarizes and staples the DMG too (two round-trips, so the
# download is clean before it is even mounted — the same order as ~/rapple/release.sh).
#
# Requires: Xcode 27+, `create-dmg` (brew install create-dmg), a "Developer ID Application"
# identity in the login keychain, and a notarytool keychain profile
# (`xcrun notarytool store-credentials <name> --apple-id … --team-id …`).
#
#   DEVELOPER_ID_APP="Developer ID Application: Your Name (TEAMID)" \
#   NOTARY_PROFILE="your-profile" \
#   scripts/release-dmg.sh 0.1.1
#
# Output lands in build/release/.
#
# LUTZY_SKIP_NOTARIZE=1 builds and signs the app and the DMG but skips both notarization rounds and
# the stapling: for a local test of the update path, never for something you ship.
set -euo pipefail

VERSION="${1:?Usage: release-dmg.sh <version>, e.g. 0.1.1}"
: "${DEVELOPER_ID_APP:?Set DEVELOPER_ID_APP (see: security find-identity -v -p codesigning)}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to your notarytool keychain profile name}"
BUNDLE_ID="${BUNDLE_ID:-com.timvbs.LUTzy}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD)}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="$ROOT/build/release"
APP="$OUT/LUTzy.app"
DMG="$OUT/LUTzy-$VERSION.dmg"
rm -rf "$OUT"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> Building universal release executable"
swift build -c release --arch arm64 --arch x86_64 >/dev/null
BIN=".build/out/Products/Release/LUTzy"
[ -f "$BIN" ] || BIN=".build/apple/Products/Release/LUTzy"
lipo -info "$BIN"
cp "$BIN" "$APP/Contents/MacOS/LUTzy"

echo "==> Icon"
ICONSET="$OUT/LUTzy.iconset"; mkdir -p "$ICONSET"
cp Sources/LUTzy/Assets.xcassets/AppIcon.appiconset/icon_*.png "$ICONSET"/
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/LUTzy.icns"

echo "==> Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key><string>en</string>
	<key>CFBundleExecutable</key><string>LUTzy</string>
	<key>CFBundleIconFile</key><string>LUTzy</string>
	<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundleName</key><string>LUTzy</string>
	<key>CFBundleDisplayName</key><string>LUTzy</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>$VERSION</string>
	<key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
	<key>LSMinimumSystemVersion</key><string>26.0</string>
	<key>LSApplicationCategoryType</key><string>public.app-category.photography</string>
	<key>NSPrincipalClass</key><string>NSApplication</string>
	<key>NSHighResolutionCapable</key><true/>
	<key>NSHumanReadableCopyright</key><string>MIT License.</string>
	<key>NSPhotoLibraryUsageDescription</key><string>LUTzy imports photos you choose so a LUT can be applied to them.</string>
</dict>
</plist>
EOF

echo "==> Signing app"
# No sandbox: LUTzy.entitlements is not applied yet (see CLAUDE.md); the hardened runtime is what
# notarization requires.
codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APP" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

if [ "${LUTZY_SKIP_NOTARIZE:-0}" = "1" ]; then
  echo "==> Skipping notarization (LUTZY_SKIP_NOTARIZE=1)"
else
  echo "==> Notarizing app (round 1 of 2)"
  ditto -c -k --keepParent "$APP" "$OUT/LUTzy.zip"
  xcrun notarytool submit "$OUT/LUTzy.zip" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm "$OUT/LUTzy.zip"
fi

echo "==> Building DMG"
create-dmg --volname "LUTzy $VERSION" --window-size 540 360 --icon-size 128 \
  --icon "LUTzy.app" 140 160 --app-drop-link 400 160 --no-internet-enable \
  "$DMG" "$APP"
codesign --force --timestamp --sign "$DEVELOPER_ID_APP" "$DMG"

if [ "${LUTZY_SKIP_NOTARIZE:-0}" = "1" ]; then
  echo "==> Skipping DMG notarization and the Gatekeeper check (LUTZY_SKIP_NOTARIZE=1)"
else
  echo "==> Notarizing DMG (round 2 of 2)"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"

  echo "==> Gatekeeper"
  spctl -a -vv -t install "$APP"
  spctl --assess --type open --context context:primary-signature -vv "$DMG"
fi
echo "Done: $DMG"
