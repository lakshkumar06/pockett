#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
if ! xcodebuild -version >/dev/null 2>&1; then
  echo 'Full Xcode is required. Finish its App Store installation, open Xcode, and install the iOS Simulator component.' >&2
  exit 1
fi
DEVICE_ID="${1:-$(xcrun simctl list devices available -j | python3 -c 'import sys,json; ds=[d for group in json.load(sys.stdin)["devices"].values() for d in group if d.get("isAvailable") and "iPhone" in d["name"]]; ds.sort(key=lambda d:d["state"]!="Booted"); print(ds[0]["udid"] if ds else "")')}"
if [[ -z "$DEVICE_ID" ]]; then
  echo 'No iPhone simulator is installed. In Xcode Settings > Components, install iOS, then create an iPhone simulator if needed.' >&2
  exit 1
fi
xcodebuild -project Pocket.xcodeproj -scheme Pocket -configuration Debug -destination "platform=iOS Simulator,id=$DEVICE_ID" -derivedDataPath .build CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES build
if ! xcrun simctl list devices booted | grep -q "$DEVICE_ID"; then
  xcrun simctl boot "$DEVICE_ID"
fi
xcrun simctl bootstatus "$DEVICE_ID" -b
if [[ -d "$DEVELOPER_DIR/../Applications/DeviceHub.app" ]]; then
  open -a "$DEVELOPER_DIR/../Applications/DeviceHub.app"
else
  open -a Simulator
fi
xcrun simctl install "$DEVICE_ID" .build/Build/Products/Debug-iphonesimulator/Pocket.app
xcrun simctl launch "$DEVICE_ID" dev.local.pocket
printf '\nLaunched Pocket on simulator %s\n' "$DEVICE_ID"
