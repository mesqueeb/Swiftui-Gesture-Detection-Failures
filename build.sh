#!/bin/bash
# Builds GestureReproApp.swift into a minimal double-clickable .app bundle.
# Usage: ./build.sh   then:   open GestureRepro.app   (or just: ./build.sh run)
set -euo pipefail
cd "$(dirname "$0")"

APP="GestureRepro.app"
BIN="$APP/Contents/MacOS/GestureRepro"
SDK="$(xcrun --sdk macosx --show-sdk-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>GestureRepro</string>
    <key>CFBundleIdentifier</key><string>studio.craftingtable.GestureRepro</string>
    <key>CFBundleName</key><string>GestureRepro</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

xcrun swiftc -parse-as-library -O \
    -sdk "$SDK" -target arm64-apple-macos26.0 \
    -o "$BIN" GestureReproApp.swift

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"

if [ "${1:-}" = "run" ]; then
    open "$APP"
fi
