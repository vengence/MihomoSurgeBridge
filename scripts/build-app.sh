#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
MODULE_CACHE="${PROJECT_DIR}/.build/ModuleCache"
DIST_DIR="${PROJECT_DIR}/dist"
APP_NAME="MihomoSurgeBridge"
APP_PATH="${DIST_DIR}/${APP_NAME}.app"
ZIP_PATH="${DIST_DIR}/${APP_NAME}.app.zip"

mkdir -p "${MODULE_CACHE}" "${DIST_DIR}"
export CLANG_MODULE_CACHE_PATH="${MODULE_CACHE}"
export SWIFTPM_MODULECACHE_OVERRIDE="${MODULE_CACHE}"

cd "${PROJECT_DIR}"
swift build -c release --arch arm64 --product "${APP_NAME}"
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"

STAGING_DIR="$(mktemp -d "/private/tmp/MihomoSurgeBridge-build.XXXXXX")"
trap 'rm -rf "${STAGING_DIR}"' EXIT
STAGED_APP="${STAGING_DIR}/${APP_NAME}.app"

mkdir -p "${STAGED_APP}/Contents/MacOS" "${STAGED_APP}/Contents/Resources"
cp -X "${BIN_DIR}/${APP_NAME}" "${STAGED_APP}/Contents/MacOS/${APP_NAME}"
cp -X "${PROJECT_DIR}/Resources/Info.plist" "${STAGED_APP}/Contents/Info.plist"
cp -X "${PROJECT_DIR}/Resources/AppIcon.icns" "${STAGED_APP}/Contents/Resources/AppIcon.icns"
chmod 755 "${STAGED_APP}/Contents/MacOS/${APP_NAME}"
xattr -cr "${STAGED_APP}"

plutil -lint "${STAGED_APP}/Contents/Info.plist"
codesign --force --deep --sign - "${STAGED_APP}"
codesign --verify --deep --strict "${STAGED_APP}"

rm -rf "${APP_PATH}" "${ZIP_PATH}"
ditto -c -k --sequesterRsrc --keepParent "${STAGED_APP}" "${ZIP_PATH}"
mv "${STAGED_APP}" "${APP_PATH}"
xattr -cr "${APP_PATH}"
codesign --force --deep --sign - "${APP_PATH}"
codesign --verify --deep --strict "${APP_PATH}"

VERIFY_DIR="$(mktemp -d "/private/tmp/MihomoSurgeBridge-verify.XXXXXX")"
ditto -x -k "${ZIP_PATH}" "${VERIFY_DIR}"
codesign --verify --deep --strict "${VERIFY_DIR}/${APP_NAME}.app"
rm -rf "${VERIFY_DIR}"

ARCHS="$(lipo -archs "${APP_PATH}/Contents/MacOS/${APP_NAME}")"
if [[ "${ARCHS}" != "arm64" ]]; then
    print -u2 "错误：产物架构为 ${ARCHS}，期望 arm64"
    exit 1
fi

print "构建完成：${APP_PATH}"
print "压缩包：${ZIP_PATH}"
