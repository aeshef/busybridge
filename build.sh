#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="$PWD/build/BusyBridge.app"
mkdir -p "$APP/Contents/MacOS" /private/tmp/busybridge-swift-cache
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.busybridge.calendar</string>
<key>CFBundleName</key><string>BusyBridge</string>
<key>CFBundleExecutable</key><string>BusyBridge</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSUIElement</key><true/>
<key>NSCalendarsFullAccessUsageDescription</key><string>Создавать блоки «Занято» в выбранном календаре Google по времени встреч. Названия, описания и участники исходных встреч не копируются.</string>
</dict></plist>
PLIST
xcrun swiftc -module-cache-path /private/tmp/busybridge-swift-cache Planner.swift main.swift -o "$APP/Contents/MacOS/BusyBridge" -framework EventKit -framework AppKit
codesign --force --sign - "$APP"
"$APP/Contents/MacOS/BusyBridge" self-test
plutil -lint "$APP/Contents/Info.plist"
echo "Built BusyBridge.app"
