#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/swift-environment.sh"

DIGITONE_RELEASE_FLAGS=(--configuration release -debug-info-format none)
swift build "${DIGITONE_SWIFT_FLAGS[@]}" "${DIGITONE_RELEASE_FLAGS[@]}" --product DigitoneStudio
swift build "${DIGITONE_SWIFT_FLAGS[@]}" "${DIGITONE_RELEASE_FLAGS[@]}" --product digitone-mcp
DIGITONE_BIN_DIR="$(swift build "${DIGITONE_SWIFT_FLAGS[@]}" "${DIGITONE_RELEASE_FLAGS[@]}" --show-bin-path)"
DIGITONE_APP="$DIGITONE_ROOT/build/Digitone Studio.app"

/usr/bin/install -d "$DIGITONE_APP/Contents/MacOS"
/usr/bin/install -m 755 "$DIGITONE_BIN_DIR/DigitoneStudio" "$DIGITONE_APP/Contents/MacOS/DigitoneStudio"
/usr/bin/install -m 755 "$DIGITONE_BIN_DIR/digitone-mcp" "$DIGITONE_APP/Contents/MacOS/digitone-mcp"
cat > "$DIGITONE_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>ru</string>
    <key>CFBundleExecutable</key><string>DigitoneStudio</string>
    <key>CFBundleIdentifier</key><string>dev.digitone.studio</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>Digitone Studio</string>
    <key>CFBundleDisplayName</key><string>Digitone Studio</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.2.0</string>
    <key>CFBundleVersion</key><string>2</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSMicrophoneUsageDescription</key><string>Digitone Studio слушает Digitone II по USB, чтобы показывать волну и спектр, записывать дубли и сэмплировать звук.</string>
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key><string>studio.digitone.sysex</string>
            <key>UTTypeDescription</key><string>Elektron SysEx</string>
            <key>UTTypeConformsTo</key><array><string>public.data</string></array>
            <key>UTTypeTagSpecification</key>
            <dict><key>public.filename-extension</key><array><string>syx</string></array></dict>
        </dict>
    </array>
</dict>
</plist>
PLIST

/usr/bin/plutil -lint "$DIGITONE_APP/Contents/Info.plist"
/usr/bin/codesign --force --sign - --timestamp=none "$DIGITONE_APP/Contents/MacOS/digitone-mcp"
/usr/bin/codesign --force --sign - --timestamp=none "$DIGITONE_APP"
/usr/bin/codesign --verify --strict "$DIGITONE_APP"
printf '\nГотово: %s\n' "$DIGITONE_APP"
