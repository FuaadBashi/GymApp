#!/bin/zsh
# Builds "GymApp Studio.app" into ~/Applications, pointing at this studio folder.
set -e
STUDIO="$(cd "$(dirname "$0")/.." && pwd)"
APP="$HOME/Applications/GymApp Studio.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O "$STUDIO/launcher/main.swift" -o "$APP/Contents/MacOS/GymApp Studio"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>GymApp Studio</string>
  <key>CFBundleIdentifier</key><string>local.gymapp.studio</string>
  <key>CFBundleExecutable</key><string>GymApp Studio</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
  <key>StudioRoot</key><string>$STUDIO</string>
</dict></plist>
PLIST
[ -f "$STUDIO/launcher/AppIcon.icns" ] && cp "$STUDIO/launcher/AppIcon.icns" "$APP/Contents/Resources/"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"
