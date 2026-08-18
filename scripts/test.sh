#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
MODULE_CACHE="${PROJECT_DIR}/.build/ModuleCache"

mkdir -p "${MODULE_CACHE}"
export CLANG_MODULE_CACHE_PATH="${MODULE_CACHE}"
export SWIFTPM_MODULECACHE_OVERRIDE="${MODULE_CACHE}"

cd "${PROJECT_DIR}"
swift run MihomoSurgeBridgeSelfTest
swiftc \
    -parse-as-library \
    -target arm64-apple-macosx13.0 \
    -module-cache-path "${MODULE_CACHE}" \
    Sources/MihomoSurgeBridge/MihomoManager.swift \
    Tests/MihomoManagerSelfTest/main.swift \
    -o "${PROJECT_DIR}/.build/MihomoManagerSelfTest"
"${PROJECT_DIR}/.build/MihomoManagerSelfTest"
swiftc \
    -parse-as-library \
    -target arm64-apple-macosx13.0 \
    -module-cache-path "${MODULE_CACHE}" \
    Sources/MihomoSurgeBridge/BridgeStatusIcon.swift \
    Tests/MenuIconSelfTest/main.swift \
    -o "${PROJECT_DIR}/.build/MenuIconSelfTest"
"${PROJECT_DIR}/.build/MenuIconSelfTest"
swiftc \
    -parse-as-library \
    -target arm64-apple-macosx13.0 \
    -module-cache-path "${MODULE_CACHE}" \
    Sources/MihomoSurgeBridge/LogTimestampFormatter.swift \
    Tests/LogTimestampSelfTest/main.swift \
    -o "${PROJECT_DIR}/.build/LogTimestampSelfTest"
"${PROJECT_DIR}/.build/LogTimestampSelfTest"
swiftc \
    -parse-as-library \
    -target arm64-apple-macosx13.0 \
    -module-cache-path "${MODULE_CACHE}" \
    Tests/AppSceneSelfTest/main.swift \
    -o "${PROJECT_DIR}/.build/AppSceneSelfTest"
"${PROJECT_DIR}/.build/AppSceneSelfTest" \
    "${PROJECT_DIR}/Sources/MihomoSurgeBridge/MihomoSurgeBridgeApp.swift"
swift build --product MihomoSurgeBridge
