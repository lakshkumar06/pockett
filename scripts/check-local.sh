#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(node -p 'Number(process.versions.node.split(".")[0])')" -lt 24 ]]; then
  echo 'Node 24+ is required for the creator TypeScript checks. Activate Node 24 and rerun.' >&2
  exit 1
fi
mkdir -p .build/runtime-v2-module-cache
swiftc -module-cache-path .build/runtime-v2-module-cache Pocket/Models.swift Tests/main.swift -o .build/model-tests
.build/model-tests
swiftc -target "$(uname -m)-apple-macosx14.0" -module-cache-path .build/runtime-v2-module-cache Pocket/WebPolicy.swift Pocket/Store.swift Tests/StoreChecks.swift -o .build/store-tests
.build/store-tests
swiftc -module-cache-path .build/runtime-v2-module-cache Shared/WidgetSnapshot.swift Pocket/Models.swift Tests/WidgetChecks.swift -o .build/widget-tests
.build/widget-tests
npm --prefix Developer test
python3 Tests/test_manifest.py
swiftc -module-cache-path .build/runtime-v2-module-cache Pocket/RetiredNative/Experience.swift Tests/ExperienceChecks.swift -o .build/experience-tests
.build/experience-tests
swiftc -module-cache-path .build/runtime-v2-module-cache Pocket/RetiredNative/Experience.swift Pocket/RetiredNative/ExperienceData.swift Tests/ExperienceDataChecks.swift -o .build/data-tests
.build/data-tests
swiftc -module-cache-path .build/runtime-v2-module-cache Pocket/RetiredNative/RouteStorage.swift Tests/RouteStorageChecks.swift -o .build/route-tests
.build/route-tests
python3 Tests/test_backend.py
python3 Tests/test_web_backend.py
node Tests/check_viewport.cjs
node Tests/check_native_bridge.cjs
swiftc -module-cache-path .build/runtime-v2-module-cache Pocket/Models.swift Pocket/WebPolicy.swift Pocket/NotificationModels.swift Tests/WebChecks.swift -o .build/web-tests
.build/web-tests
plutil -lint Pocket/Info.plist Pocket.xcodeproj/project.pbxproj PocketWidgets/Info.plist Pocket/Pocket.entitlements Pocket/PocketPush.entitlements PocketWidgets/PocketWidgets.entitlements
swiftc -frontend -parse Pocket/*.swift Shared/*.swift
swiftc -frontend -parse PocketWidgets/*.swift Shared/*.swift
