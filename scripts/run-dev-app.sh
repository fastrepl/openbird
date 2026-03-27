#!/usr/bin/env bash

set -euo pipefail

if [[ $# -gt 1 ]]; then
  echo "usage: $0 [app-path]" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="${1:-${ROOT_DIR}/.build/Openbird.app}"
APP_DIR="${APP_DIR%/}"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
(
  cd "${ROOT_DIR}"
  swift build
)
BUILD_DIR="$(cd "${ROOT_DIR}" && swift build --show-bin-path)"
PLIST_TEMPLATE="${ROOT_DIR}/packaging/Openbird-Info.plist.template"
ENTITLEMENTS="${ROOT_DIR}/packaging/Openbird.entitlements"

rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}"

cp "${BUILD_DIR}/OpenbirdApp" "${MACOS_DIR}/OpenbirdApp"
cp "${BUILD_DIR}/OpenbirdCollector" "${MACOS_DIR}/OpenbirdCollector"
chmod +x "${MACOS_DIR}/OpenbirdApp" "${MACOS_DIR}/OpenbirdCollector"

sed \
  -e "s/__BUNDLE_IDENTIFIER__/com.computelesscomputer.openbird.dev/g" \
  -e "s/__VERSION__/0.0.0/g" \
  "${PLIST_TEMPLATE}" > "${CONTENTS_DIR}/Info.plist"

codesign --force --deep --sign - --entitlements "${ENTITLEMENTS}" "${APP_DIR}"
open "${APP_DIR}"
