#!/bin/zsh
# Builds WiFiKept.app into ./build. Usage: ./build.sh [--run]
set -e
cd "$(dirname "$0")"

swift build -c release

APP=build/WiFiKept.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/WiFiKept "$APP/Contents/MacOS/WiFiKept"
cp Support/Info.plist "$APP/Contents/Info.plist"
[ -f Support/AppIcon.icns ] && cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP"

echo "Built $APP"
if [[ "$1" == "--run" ]]; then
    open "$APP"
fi
