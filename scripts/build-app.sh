#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REQUESTED_CONFIGURATION="${1:-debug}"

case "$REQUESTED_CONFIGURATION" in
  debug|Debug)
    SWIFT_CONFIGURATION="debug"
    BUNDLE_CONFIGURATION="Debug"
    ;;
  release|Release)
    SWIFT_CONFIGURATION="release"
    BUNDLE_CONFIGURATION="Release"
    ;;
  *)
    printf 'Usage: %s [debug|release]\n' "$0" >&2
    exit 2
    ;;
esac

APP_NAME="InstallModel"
BUILD_ROOT="$PROJECT_ROOT/build/$BUNDLE_CONFIGURATION"
APP_BUNDLE="$BUILD_ROOT/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
ICON_SOURCE="$PROJECT_ROOT/Assets/AppIcon-Master.png"
ICON_SET="$BUILD_ROOT/AppIcon.iconset"
INFO_PLIST="$PROJECT_ROOT/AppBundle/Info.plist"

[[ -f "$ICON_SOURCE" ]] || { printf 'Missing icon master: %s\n' "$ICON_SOURCE" >&2; exit 1; }
[[ -f "$INFO_PLIST" ]] || { printf 'Missing Info.plist: %s\n' "$INFO_PLIST" >&2; exit 1; }

printf 'Building Swift executable (%s)…\n' "$BUNDLE_CONFIGURATION"
swift build --package-path "$PROJECT_ROOT" --configuration "$SWIFT_CONFIGURATION"
BIN_DIRECTORY="$(swift build --package-path "$PROJECT_ROOT" --configuration "$SWIFT_CONFIGURATION" --show-bin-path)"
EXECUTABLE="$BIN_DIRECTORY/$APP_NAME"
RESOURCE_BUNDLE="$BIN_DIRECTORY/InstallModel_InstallModelApp.bundle"

[[ -x "$EXECUTABLE" ]] || { printf 'Missing executable: %s\n' "$EXECUTABLE" >&2; exit 1; }
[[ -d "$RESOURCE_BUNDLE" ]] || { printf 'Missing Swift resource bundle: %s\n' "$RESOURCE_BUNDLE" >&2; exit 1; }

mkdir -p "$BUILD_ROOT"
case "$APP_BUNDLE" in
  "$PROJECT_ROOT"/build/*/InstallModel.app) rm -rf "$APP_BUNDLE" ;;
  *) printf 'Refusing to replace unexpected path: %s\n' "$APP_BUNDLE" >&2; exit 1 ;;
esac
rm -rf "$ICON_SET"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$ICON_SET"

cp "$EXECUTABLE" "$CONTENTS/MacOS/$APP_NAME"
cp "$INFO_PLIST" "$CONTENTS/Info.plist"
cp -R "$RESOURCE_BUNDLE" "$CONTENTS/Resources/"
printf 'APPL????' > "$CONTENTS/PkgInfo"

make_icon() {
  local pixels="$1"
  local filename="$2"
  sips -s format png -z "$pixels" "$pixels" "$ICON_SOURCE" --out "$ICON_SET/$filename" >/dev/null
}

make_icon 16 icon_16x16.png
make_icon 32 icon_16x16@2x.png
make_icon 32 icon_32x32.png
make_icon 64 icon_32x32@2x.png
make_icon 128 icon_128x128.png
make_icon 256 icon_128x128@2x.png
make_icon 256 icon_256x256.png
make_icon 512 icon_256x256@2x.png
make_icon 512 icon_512x512.png
make_icon 1024 icon_512x512@2x.png
iconutil -c icns "$ICON_SET" -o "$CONTENTS/Resources/AppIcon.icns"
rm -rf "$ICON_SET"

plutil -lint "$CONTENTS/Info.plist" >/dev/null
codesign --force --sign - --timestamp=none "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

printf 'Built %s\n' "$APP_BUNDLE"
