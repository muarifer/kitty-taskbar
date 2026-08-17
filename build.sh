#!/bin/zsh
# Builds KittyTaskbar.app.
#   ./build.sh              native build
#   ./build.sh --universal  arm64 + x86_64 fat binary (requires Xcode)
#   ./build.sh --release    universal build + zip for GitHub release
set -e
cd "$(dirname "$0")"

VERSION="${VERSION:-1.0.0}"
MODE="${1:-}"

if [[ "$MODE" == "--universal" || "$MODE" == "--release" ]]; then
    swift build -c release --arch arm64 --arch x86_64
    BIN=".build/apple/Products/Release/KittyTaskbar"
else
    swift build -c release
    BIN=".build/release/KittyTaskbar"
fi

APP="KittyTaskbar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cp "$BIN" "$APP/Contents/MacOS/KittyTaskbar"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>KittyTaskbar</string>
    <key>CFBundleIdentifier</key><string>com.muarifer.kitty-taskbar</string>
    <key>CFBundleName</key><string>KittyTaskbar</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key><string>com.muarifer.kitty-taskbar.tab</string>
            <key>UTTypeDescription</key><string>Kitty Tab Reference</string>
            <key>UTTypeConformsTo</key><array><string>public.data</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"

if [[ "$MODE" == "--release" ]]; then
    ZIP="KittyTaskbar-${VERSION}.zip"
    rm -f "$ZIP"
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
    echo "Release artifact: $PWD/$ZIP"
    shasum -a 256 "$ZIP"
else
    echo "Ready: $PWD/$APP  (run with: open $APP)"
fi
