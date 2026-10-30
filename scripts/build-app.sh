#!/bin/bash
# Builds Browser Picker, assembles the .app bundle, signs it ad hoc, and installs it to /Applications.
# Set INSTALL_DIR to install elsewhere, e.g. INSTALL_DIR=~/Applications for a user without admin rights.
# With --zip it packages build/Browser-Picker-<version>.zip for a GitHub release instead of installing.
# Set VERSION to override the version in Resources/Info.plist, e.g. VERSION=1.2.0 for a release tag.
set -euo pipefail

case "${1:-}" in
    "") ZIP_ONLY=0 ;;
    --zip) ZIP_ONLY=1 ;;
    *) echo "Usage: $0 [--zip]" >&2; exit 2 ;;
esac

cd "$(dirname "$0")/.."

APP_NAME="Browser Picker"
BUNDLE_ID="dev.evgenyivanov.BrowserPicker"
BUILD_APP="build/$APP_NAME.app"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
LEGACY_DIR="$HOME/Applications"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$BUILD_APP"
mkdir -p "$BUILD_APP/Contents/MacOS" "$BUILD_APP/Contents/Resources"
cp "$BIN_DIR/BrowserPicker" "$BUILD_APP/Contents/MacOS/BrowserPicker"
cp Resources/Info.plist "$BUILD_APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$BUILD_APP/Contents/Resources/AppIcon.icns"
if [ -n "${VERSION:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $VERSION" \
        "$BUILD_APP/Contents/Info.plist"
fi
plutil -lint "$BUILD_APP/Contents/Info.plist"

codesign --force --sign - "$BUILD_APP"

if [ "$ZIP_ONLY" = 1 ]; then
    APP_VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$BUILD_APP/Contents/Info.plist")"
    ZIP="build/Browser-Picker-$APP_VERSION.zip"
    rm -f "$ZIP"
    # No resource forks or extended attributes: unzip tools other than Finder's would extract them as ._ files,
    # which break the code signature.
    ditto -c -k --norsrc --noextattr --keepParent "$BUILD_APP" "$ZIP"
    "$LSREGISTER" -u "$BUILD_APP" 2>/dev/null || true
    rm -rf "$BUILD_APP"
    echo "Packaged $ZIP"
    exit 0
fi

if [ ! -w "$INSTALL_DIR" ] && [ -d "$INSTALL_DIR" ]; then
    echo "Cannot write to $INSTALL_DIR. Run as an admin user, or set INSTALL_DIR=~/Applications." >&2
    exit 1
fi

# Quit a running instance, wherever it is installed, so the new build replaces it.
if pgrep -f "$APP_NAME.app/Contents/MacOS/BrowserPicker" >/dev/null 2>&1; then
    osascript -e "quit app id \"$BUNDLE_ID\"" >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -f "$APP_NAME.app/Contents/MacOS/BrowserPicker" >/dev/null 2>&1 || break
        sleep 0.3
    done
fi

# Earlier builds installed to ~/Applications. Remove that copy so macOS lists only one Browser Picker.
if [ "$INSTALL_DIR" != "$LEGACY_DIR" ] && [ -d "$LEGACY_DIR/$APP_NAME.app" ]; then
    "$LSREGISTER" -u "$LEGACY_DIR/$APP_NAME.app" || true
    rm -rf "$LEGACY_DIR/$APP_NAME.app"
    echo "Removed old copy at $LEGACY_DIR/$APP_NAME.app"
fi

mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/$APP_NAME.app"
cp -R "$BUILD_APP" "$INSTALL_DIR/$APP_NAME.app"
"$LSREGISTER" -f "$INSTALL_DIR/$APP_NAME.app"
# Remove the staging copy so Spotlight and LaunchServices know only the installed one.
"$LSREGISTER" -u "$BUILD_APP" 2>/dev/null || true
rm -rf "$BUILD_APP"

echo "Installed $INSTALL_DIR/$APP_NAME.app"
