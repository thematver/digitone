#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/swift-environment.sh"
DIGITONE_SNAPSHOT_DIR="$DIGITONE_ROOT/build/snapshots"
if [[ "${1:-}" == "--output" ]]; then
    if [[ $# -lt 2 ]]; then
        printf 'Usage: %s [--output DIRECTORY] [NAME_FILTER]\n' "$0" >&2
        exit 2
    fi
    DIGITONE_SNAPSHOT_DIR="$2"
    shift 2
fi
swift run "${DIGITONE_SWIFT_FLAGS[@]}" DigitoneSnapshots "$DIGITONE_SNAPSHOT_DIR" "$@"
