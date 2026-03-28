#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <output-icns-path>" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_IMAGE="${ROOT_DIR}/packaging/Openbird.icon/Assets/dither.png"
OUTPUT_PATH="$1"
TMP_DIR="$(mktemp -d)"
ICONSET_DIR="${TMP_DIR}/Openbird.iconset"

trap 'rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${ICONSET_DIR}" "$(dirname "${OUTPUT_PATH}")"

for size in 16 32 128 256 512; do
  sips -z "${size}" "${size}" "${SOURCE_IMAGE}" --out "${ICONSET_DIR}/icon_${size}x${size}.png" >/dev/null
  scale2=$((size * 2))
  sips -z "${scale2}" "${scale2}" "${SOURCE_IMAGE}" --out "${ICONSET_DIR}/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "${ICONSET_DIR}" -o "${OUTPUT_PATH}"
