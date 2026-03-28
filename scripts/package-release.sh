#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "usage: $0 <tag> <output-dir> [bundle-id]" >&2
  exit 1
fi

TAG="$1"
OUTPUT_DIR="$2"
BUNDLE_ID="${3:-com.computelesscomputer.openbird}"
VERSION="${TAG#v}"
BUILD_DIR="$(swift build -c release --show-bin-path)"
APP_DIR="${OUTPUT_DIR}/Openbird.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
PLIST_TEMPLATE="packaging/Openbird-Info.plist.template"
ICON_PATH="packaging/Openbird.icns"

mkdir -p "$OUTPUT_DIR"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BUILD_DIR/OpenbirdApp" "${MACOS_DIR}/OpenbirdApp"
chmod +x "${MACOS_DIR}/OpenbirdApp"
install -m 644 "$ICON_PATH" "${RESOURCES_DIR}/Openbird.icns"

sed \
  -e "s/__BUNDLE_IDENTIFIER__/${BUNDLE_ID}/g" \
  -e "s/__VERSION__/${VERSION}/g" \
  "$PLIST_TEMPLATE" > "${CONTENTS_DIR}/Info.plist"
