#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/swift-environment.sh"

swift test "${DIGITONE_SWIFT_FLAGS[@]}"
swift build "${DIGITONE_SWIFT_FLAGS[@]}" --product DigitoneStudio
swift build "${DIGITONE_SWIFT_FLAGS[@]}" --product digitone-tool
DIGITONE_BIN_DIR="$(swift build "${DIGITONE_SWIFT_FLAGS[@]}" --show-bin-path)"
/usr/bin/install -d "$DIGITONE_ROOT/build/bin"
/usr/bin/install -m 755 "$DIGITONE_BIN_DIR/digitone-tool" "$DIGITONE_ROOT/build/bin/digitone-tool"
