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

case "$configuration" in
    debug|release) ;;
    *)
        echo "usage: $0 [debug|release]" >&2
        exit 64
        ;;
esac

commit=$(git rev-parse --short=12 HEAD)
branch=$(git branch --show-current)
[[ -n "$branch" ]] || branch="detached"
built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
dirty=false
[[ -n "$(git status --porcelain --untracked-files=normal)" ]] && dirty=true

swift build -c "$configuration" --product LUTzy
bin_dir=$(swift build -c "$configuration" --show-bin-path)

app="$root/build/LUTzy.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/LUTzy" "$app/Contents/MacOS/LUTzy"

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

# These keys make an acceptance build self-identifying without changing the
# production preferences domain.  Keeping the bundle identifier stable means
# Starred LUTs, Collections, and other persisted state remain representative.
plutil -insert LUTzyBuildCommit -string "$commit" "$app/Contents/Info.plist"
plutil -insert LUTzyBuildBranch -string "$branch" "$app/Contents/Info.plist"
plutil -insert LUTzyBuildRoot -string "$root" "$app/Contents/Info.plist"
plutil -insert LUTzyBuildConfiguration -string "$configuration" "$app/Contents/Info.plist"
plutil -insert LUTzyBuildTimestamp -string "$built_at" "$app/Contents/Info.plist"
plutil -insert LUTzyBuildDirty -bool "$dirty" "$app/Contents/Info.plist"

# Ad-hoc signature: unsigned bundles are refused outright on Apple silicon.
codesign --force --deep --sign - "$app" >/dev/null 2>&1 || true
dirty_suffix=""
$dirty && dirty_suffix="+dirty"
echo "built $app ($branch@$commit$dirty_suffix, $configuration)"
