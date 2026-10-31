#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
SDKROOT="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
export SDKROOT
swift build --disable-sandbox --sdk "$SDKROOT" --target LabelCore
BIN_PATH="$(swift build --disable-sandbox --sdk "$SDKROOT" --show-bin-path)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/label-helper-render-tests.XXXXXX")"
trap 'rm -f "$TEST_DIR/PrintLayoutTests"; rmdir "$TEST_DIR"' EXIT

# SwiftBuild emits a combined object; older SwiftPM emits one object per file.
if [[ -f "$BIN_PATH/LabelCore.o" ]]; then
  CORE_OBJECTS=("$BIN_PATH/LabelCore.o")
else
  shopt -s nullglob
  CORE_OBJECTS=("$BIN_PATH"/LabelCore.build/*.swift.o)
  if [[ ${#CORE_OBJECTS[@]} -eq 0 ]]; then
    echo "LabelCore build objects not found in $BIN_PATH" >&2
    exit 1
  fi
fi

swiftc -parse-as-library -sdk "$SDKROOT" \
  -I "$BIN_PATH" -I "$BIN_PATH/Modules" \
  Sources/LabelHelper/Services/EtsyAddressLabelWriter.swift \
  Sources/LabelHelper/Services/LabelRenderer.swift \
  Tests/PrintLayoutTests.swift "${CORE_OBJECTS[@]}" \
  -o "$TEST_DIR/PrintLayoutTests"
codesign --force --sign - "$TEST_DIR/PrintLayoutTests"
"$TEST_DIR/PrintLayoutTests"
