#!/usr/bin/env bash
# Shared by the build and check entry points. All compiler caches stay in the project.
set -euo pipefail

DIGITONE_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DIGITONE_ROOT="$(cd -- "$DIGITONE_SCRIPT_DIR/.." && pwd)"
cd -- "$DIGITONE_ROOT"

export CLANG_MODULE_CACHE_PATH="$DIGITONE_ROOT/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$DIGITONE_ROOT/.build/module-cache"
mkdir -p -- "$CLANG_MODULE_CACHE_PATH" .build/cache .build/config .build/security

DIGITONE_SWIFT_FLAGS=(
    --disable-sandbox
    --cache-path "$DIGITONE_ROOT/.build/cache"
    --config-path "$DIGITONE_ROOT/.build/config"
    --security-path "$DIGITONE_ROOT/.build/security"
)
