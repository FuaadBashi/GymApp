#!/bin/sh
# Builds the app and installs it on the connected iPhone: the weekly re-sign in one command.
# The signing team comes from this clone's git config, so it never enters the repository:
#   git config bashi.team <TEAM_ID>
# Usage: tools/reinstall.sh            (first connected iPhone)
#        tools/reinstall.sh <device-id>
set -eu
cd "$(dirname "$0")/.."
TEAM=$(git config --get bashi.team || true)
[ -n "$TEAM" ] || { echo "Set the signing team first: git config bashi.team <TEAM_ID>"; exit 1; }
DEVICE=${1:-$(xcrun devicectl list devices 2>/dev/null | awk '/available \(paired\)/ && /iPhone/ {for (i=1;i<=NF;i++) if ($i ~ /^[0-9A-F]{8}-/) {print $i; exit}}')}
[ -n "$DEVICE" ] || { echo "No paired iPhone found. Connect it, unlock it, and try again."; exit 1; }
DD=${TMPDIR:-/tmp}/bashi-gym-build
echo "Building for $DEVICE..."
xcodebuild -project GymApp.xcodeproj -scheme GymApp -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath "$DD" DEVELOPMENT_TEAM="$TEAM" -allowProvisioningUpdates build -quiet
xcrun devicectl device install app --device "$DEVICE" "$DD/Build/Products/Debug-iphoneos/GymApp.app" >/dev/null
echo "Installed. The new signing lasts 7 days; the app warns before it runs out."
