#!/bin/zsh
# Builds "Эфирометр.app" next to this script and signs it ad-hoc.
# --install: also copies it to /Applications (needed for a stable launch-at-login item).
set -euo pipefail
cd "$(dirname "$0")"

NAME="Эфирометр"
EXEC="Efirometr"
BUNDLE_ID="local.efirometr"
VERSION="${VERSION:-1.0.0}"   # CI passes the tag, e.g. VERSION=1.2.0

# Universal binary: Apple Silicon + Intel.
ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}"
BIN=$(swift build -c release "${ARCHS[@]}" --show-bin-path)/$EXEC
APP="build/$NAME.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$EXEC"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$NAME</string>
    <key>CFBundleDisplayName</key><string>$NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$EXEC</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSLocationUsageDescription</key><string>macOS показывает имена Wi‑Fi сетей (SSID/BSSID) только приложениям с доступом к геолокации. Координаты не используются.</string>
    <key>NSLocationWhenInUseUsageDescription</key><string>macOS показывает имена Wi‑Fi сетей (SSID/BSSID) только приложениям с доступом к геолокации. Координаты не используются.</string>
</dict>
</plist>
PLIST

# Ad-hoc signature with a stable designated requirement (bundle id instead of cdhash),
# so macOS keeps Location/Notification permissions across rebuilds.
codesign --force --deep --sign - -r="designated => identifier \"$BUNDLE_ID\"" "$APP"
echo "Built: $PWD/$APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x "$EXEC" 2>/dev/null || true
    pkill -x WiFiDoctor 2>/dev/null || true          # app's previous name
    rm -rf "/Applications/Wi-Fi Doctor.app"
    rm -rf "/Applications/$NAME.app"
    ditto "$APP" "/Applications/$NAME.app"
    echo "Installed: /Applications/$NAME.app"
fi
