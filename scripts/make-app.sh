#!/bin/zsh
# Assemble LUTzy.app from the SwiftPM build.
#
# A bare `swift run` binary is not an application as far as macOS is concerned:
# it has no bundle identifier, so it cannot be launched from Finder, does not
# keep its own preferences domain reliably, and is invisible to anything that
# works by application identity — permissions, automation, the Dock.
set -euo pipefail

configuration=${1:-release}
root=${0:a:h:h}
cd "$root"

swift build -c "$configuration" --product LUTzy

app="$root/build/LUTzy.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp ".build/$configuration/LUTzy" "$app/Contents/MacOS/LUTzy"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>LUTzy</string>
    <key>CFBundleDisplayName</key><string>LUT Studio</string>
    <key>CFBundleExecutable</key><string>LUTzy</string>
    <key>CFBundleIdentifier</key><string>com.lutstudio.LUTzy</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPhotoLibraryUsageDescription</key>
    <string>Import photos to preview LUTs against.</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Cube LUT</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSItemContentTypes</key>
            <array><string>public.data</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

# Ad-hoc signature: unsigned bundles are refused outright on Apple silicon.
codesign --force --deep --sign - "$app" >/dev/null 2>&1 || true
echo "built $app"
