#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/swift-environment.sh"

# Compile and link for a physical-device architecture without simulator services,
# provisioning, installation, or running the application. These dylibs are check artifacts.
DIGITONE_IOS_OUT="$DIGITONE_ROOT/.build/ios-check"
/usr/bin/install -d "$DIGITONE_IOS_OUT/modules" "$DIGITONE_IOS_OUT/cache"
DIGITONE_IOS_SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
DIGITONE_IOS_SWIFTC=(
    xcrun --sdk iphoneos swiftc
    -disable-sandbox
    -swift-version 6
    -target arm64-apple-ios17.0
    -sdk "$DIGITONE_IOS_SDK"
    -module-cache-path "$DIGITONE_IOS_OUT/cache"
    -parse-as-library
)

"${DIGITONE_IOS_SWIFTC[@]}" -emit-library -emit-module -module-name DigitoneCore \
    -emit-module-path "$DIGITONE_IOS_OUT/modules/DigitoneCore.swiftmodule" \
    Sources/DigitoneCore/*.swift -o "$DIGITONE_IOS_OUT/libDigitoneCore.dylib"

"${DIGITONE_IOS_SWIFTC[@]}" -emit-library -emit-module -module-name DigitoneMIDI \
    -emit-module-path "$DIGITONE_IOS_OUT/modules/DigitoneMIDI.swiftmodule" \
    -I "$DIGITONE_IOS_OUT/modules" -L "$DIGITONE_IOS_OUT" -lDigitoneCore \
    Sources/DigitoneMIDI/*.swift -o "$DIGITONE_IOS_OUT/libDigitoneMIDI.dylib"

"${DIGITONE_IOS_SWIFTC[@]}" -emit-library -emit-module -module-name DigitoneUI \
    -emit-module-path "$DIGITONE_IOS_OUT/modules/DigitoneUI.swiftmodule" \
    -I "$DIGITONE_IOS_OUT/modules" -L "$DIGITONE_IOS_OUT" -lDigitoneCore -lDigitoneMIDI \
    Sources/DigitoneUI/*.swift -o "$DIGITONE_IOS_OUT/libDigitoneUI.dylib"

"${DIGITONE_IOS_SWIFTC[@]}" -I "$DIGITONE_IOS_OUT/modules" -L "$DIGITONE_IOS_OUT" \
    -lDigitoneCore -lDigitoneMIDI -lDigitoneUI \
    App/DigitoneStudioApp.swift -o "$DIGITONE_IOS_OUT/DigitoneStudio"

printf '\nКомпиляция и связывание для arm64 iOS 17 завершены. Установка и работа на устройстве требуют отдельной проверки.\n'
