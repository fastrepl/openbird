#!/usr/bin/env bash

set -euo pipefail

if [[ $# -gt 1 ]]; then
  echo "usage: $0 [app-path]" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="${1:-${ROOT_DIR}/.build/Openbird Dev.app}"
APP_DIR="${APP_DIR%/}"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
(
  cd "${ROOT_DIR}"
  swift build
)
BUILD_DIR="$(cd "${ROOT_DIR}" && swift build --show-bin-path)"
PLIST_TEMPLATE="${ROOT_DIR}/packaging/Openbird-Info.plist.template"
ENTITLEMENTS="${ROOT_DIR}/packaging/Openbird.entitlements"
SIGNING_IDENTITY="${OPENBIRD_SIGNING_IDENTITY:--}"
PLIST_PATH="${CONTENTS_DIR}/Info.plist"
TMP_PLIST="$(mktemp)"

trap 'rm -f "${TMP_PLIST}"' EXIT

mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

install -m 755 "${BUILD_DIR}/OpenbirdApp" "${MACOS_DIR}/OpenbirdApp"
"${ROOT_DIR}/scripts/build-app-icon.sh" "${RESOURCES_DIR}/Openbird.icns"
install -m 644 "${ROOT_DIR}/Sources/OpenbirdApp/Resources/tray.png" "${RESOURCES_DIR}/tray.png"

sed \
  -e "s/__APP_NAME__/Openbird Dev/g" \
  -e "s/__BUNDLE_IDENTIFIER__/com.computelesscomputer.openbird.dev/g" \
  -e "s/__VERSION__/0.0.0/g" \
  "${PLIST_TEMPLATE}" > "${TMP_PLIST}"

install -m 644 "${TMP_PLIST}" "${PLIST_PATH}"

codesign --force --deep --sign "${SIGNING_IDENTITY}" --entitlements "${ENTITLEMENTS}" "${APP_DIR}"
open "${APP_DIR}"
