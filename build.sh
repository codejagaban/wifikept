#!/bin/zsh
# Builds WiFiKept.app into ./build. Usage: ./build.sh [--run | --install]
#   --run      launch the freshly built app from ./build
#   --install  copy it to /Applications and launch from there
set -e
cd "$(dirname "$0")"

swift build -c release

APP=build/WiFiKept.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/WiFiKept "$APP/Contents/MacOS/WiFiKept"
cp Support/Info.plist "$APP/Contents/Info.plist"
[ -f Support/AppIcon.icns ] && cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
[ -d Support/Fonts ] && cp -R Support/Fonts "$APP/Contents/Resources/Fonts"

codesign --force --sign - "$APP"

echo "Built $APP"
if [[ "$1" == "--run" ]]; then
    open "$APP"
elif [[ "$1" == "--dmg" ]]; then
    VERSION=$(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString)
    STAGE=$(mktemp -d)
    cp -R "$APP" "$STAGE/WiFiKept.app"
    ln -s /Applications "$STAGE/Applications"
    rm -f "build/WiFiKept-$VERSION.dmg"
    hdiutil create -volname "WiFiKept" -srcfolder "$STAGE" -ov -format UDZO \
        "build/WiFiKept-$VERSION.dmg"
    rm -rf "$STAGE"
    echo "Created build/WiFiKept-$VERSION.dmg"
elif [[ "$1" == "--install" ]]; then
    osascript -e 'quit app "WiFiKept"' 2>/dev/null
    sleep 1
    rm -rf /Applications/WiFiKept.app
    cp -R "$APP" /Applications/WiFiKept.app
    echo "Installed /Applications/WiFiKept.app"
    open /Applications/WiFiKept.app
fi
