#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="QuartzFocus"
CONFIG="release"
BUILD_DIR=".build/${CONFIG}"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS="${APP_DIR}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"

echo "==> Building ${CONFIG} binary"
swift build -c "${CONFIG}" --product "${APP_NAME}"

echo "==> Assembling ${APP_NAME}.app"
rm -rf "${APP_DIR}"
mkdir -p "${MACOS}" "${RESOURCES}"

cp "${BUILD_DIR}/${APP_NAME}" "${MACOS}/${APP_NAME}"
cp "App/Info.plist" "${CONTENTS}/Info.plist"
if [[ ! -f "App/AppIcon.icns" ]]; then
  echo "==> Generating App/AppIcon.icns from SF Symbol"
  swift scripts/generate-icon.swift
fi
cp "App/AppIcon.icns" "${RESOURCES}/AppIcon.icns"
printf 'APPL????' > "${CONTENTS}/PkgInfo"

echo "==> Ad-hoc signing"
codesign --force --deep --sign - "${APP_DIR}"

echo ""
echo "Built: ${APP_DIR}"
echo "Run:   open ${APP_DIR}"
