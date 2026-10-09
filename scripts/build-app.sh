#!/bin/bash
# Builds Browser Picker, assembles the .app bundle, signs it ad hoc, and installs it to ~/Applications.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Browser Picker"
BUNDLE_ID="dev.evgenyivanov.BrowserPicker"
BUILD_APP="build/$APP_NAME.app"
INSTALL_DIR="$HOME/Applications"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$BUILD_APP"
mkdir -p "$BUILD_APP/Contents/MacOS" "$BUILD_APP/Contents/Resources"
cp "$BIN_DIR/BrowserPicker" "$BUILD_APP/Contents/MacOS/BrowserPicker"
cp Resources/Info.plist "$BUILD_APP/Contents/Info.plist"
plutil -lint "$BUILD_APP/Contents/Info.plist"

codesign --force --sign - "$BUILD_APP"

# Quit a running instance so the new build replaces it.
if pgrep -f "$INSTALL_DIR/$APP_NAME.app/Contents/MacOS/BrowserPicker" >/dev/null 2>&1; then
    osascript -e "quit app id \"$BUNDLE_ID\"" >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -f "$INSTALL_DIR/$APP_NAME.app/Contents/MacOS/BrowserPicker" >/dev/null 2>&1 || break
        sleep 0.3
    done
fi

mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/$APP_NAME.app"
cp -R "$BUILD_APP" "$INSTALL_DIR/$APP_NAME.app"
"$LSREGISTER" -f "$INSTALL_DIR/$APP_NAME.app"

echo "Installed $INSTALL_DIR/$APP_NAME.app"
