#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
MODULE_CACHE="${PROJECT_DIR}/.build/ModuleCache"
MASTER_PNG="${PROJECT_DIR}/Resources/AppIcon-1024.png"
OUTPUT_ICNS="${PROJECT_DIR}/Resources/AppIcon.icns"
ICONSET_DIR="$(mktemp -d '/private/tmp/MihomoSurgeBridge-iconset.XXXXXX')/AppIcon.iconset"
trap 'rm -rf "${ICONSET_DIR:h}"' EXIT

mkdir -p "${ICONSET_DIR}" "${MODULE_CACHE}"
export CLANG_MODULE_CACHE_PATH="${MODULE_CACHE}"
export SWIFTPM_MODULECACHE_OVERRIDE="${MODULE_CACHE}"
swift -target arm64-apple-macosx13.0 \
    "${SCRIPT_DIR}/generate-app-icon.swift" \
    "${MASTER_PNG}" \
    "${ICONSET_DIR}"

iconutil -c icns "${ICONSET_DIR}" -o "${OUTPUT_ICNS}"
print "已生成：${MASTER_PNG}"
print "已生成：${OUTPUT_ICNS}"
