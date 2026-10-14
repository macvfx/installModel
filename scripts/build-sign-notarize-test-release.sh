#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="InstallModel"
NOTARY_PROFILE="${MAC_APP_NOTARY_PROFILE:-notary-profile}"
SIGNING_IDENTITY="${MAC_APP_SIGN_IDENTITY:-}"
OUTPUT_DIR=""
OVERWRITE=0

usage() {
  cat <<'EOF'
Build, Developer ID sign, notarize, staple, and validate an Apple Silicon
InstallModel test DMG.

Usage:
  ./scripts/build-sign-notarize-test-release.sh --output-dir /absolute/path [--overwrite]

Environment:
  MAC_APP_SIGN_IDENTITY  Exact Developer ID Application identity. When omitted,
                         the script requires exactly one matching identity.
  MAC_APP_NOTARY_PROFILE notarytool Keychain profile (default: notary-profile).

The script never accepts Apple credentials on the command line.
EOF
}

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
log() { printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir) [[ $# -ge 2 ]] || die "--output-dir requires a path"; OUTPUT_DIR="$2"; shift 2 ;;
    --overwrite) OVERWRITE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

[[ "$OUTPUT_DIR" == /* ]] || die "--output-dir must be an absolute path"
mkdir -p "$OUTPUT_DIR"

for command_name in swift security codesign xcrun ditto hdiutil plutil lipo shasum spctl; do
  command -v "$command_name" >/dev/null 2>&1 || die "required command not found: $command_name"
done

if [[ -z "$SIGNING_IDENTITY" ]]; then
  IDENTITY_LINES="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p')"
  IDENTITY_COUNT="$(printf '%s\n' "$IDENTITY_LINES" | awk 'NF { count++ } END { print count + 0 }')"
  [[ "$IDENTITY_COUNT" -eq 1 ]] || die "expected exactly one Developer ID Application identity; found $IDENTITY_COUNT (set MAC_APP_SIGN_IDENTITY)"
  SIGNING_IDENTITY="$IDENTITY_LINES"
fi
security find-identity -v -p codesigning 2>/dev/null | grep -F "$SIGNING_IDENTITY" >/dev/null ||
  die "the selected Developer ID Application identity is unavailable"

log "Checking notarization Keychain profile"
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null

VERSION="$(plutil -extract CFBundleShortVersionString raw "$PROJECT_ROOT/AppBundle/Info.plist")"
BUILD="$(plutil -extract CFBundleVersion raw "$PROJECT_ROOT/AppBundle/Info.plist")"
ARTIFACT_BASE="$APP_NAME-$VERSION-build$BUILD"
FINAL_DMG="$OUTPUT_DIR/$ARTIFACT_BASE.dmg"
CHECKSUM_FILE="$OUTPUT_DIR/$ARTIFACT_BASE.sha256.txt"
RECEIPT_FILE="$OUTPUT_DIR/$ARTIFACT_BASE.release.txt"

for output_path in "$FINAL_DMG" "$CHECKSUM_FILE" "$RECEIPT_FILE"; do
  if [[ -e "$output_path" && "$OVERWRITE" -ne 1 ]]; then
    die "output already exists; use --overwrite only after reviewing it: $output_path"
  fi
done

WORK_DIR="$(mktemp -d "/private/tmp/installmodel-release.XXXXXX")"
MOUNT_DIR="$WORK_DIR/mount"
MOUNTED=0
SUCCEEDED=0

cleanup() {
  if [[ "$MOUNTED" -eq 1 ]]; then hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || true; fi
  if [[ "$SUCCEEDED" -eq 1 ]]; then
    rm -rf "$WORK_DIR"
  else
    printf 'Release work directory retained for diagnosis: %s\n' "$WORK_DIR" >&2
  fi
}
trap cleanup EXIT

log "Running Swift tests"
swift test --package-path "$PROJECT_ROOT"

log "Building Release app bundle"
"$PROJECT_ROOT/scripts/build-app.sh" release
SOURCE_APP="$PROJECT_ROOT/build/Release/$APP_NAME.app"
SIGNED_APP="$WORK_DIR/$APP_NAME.app"
[[ -d "$SOURCE_APP" ]] || die "Release app was not created: $SOURCE_APP"
ditto "$SOURCE_APP" "$SIGNED_APP"

log "Applying Developer ID signature and hardened runtime"
codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$SIGNED_APP"
codesign --verify --deep --strict --verbose=2 "$SIGNED_APP"
ARCHITECTURES="$(lipo -archs "$SIGNED_APP/Contents/MacOS/$APP_NAME")"
[[ " $ARCHITECTURES " == *" arm64 "* ]] || die "Release binary is missing arm64: $ARCHITECTURES"

log "Submitting app to Apple notarization"
APP_ZIP="$WORK_DIR/$APP_NAME-for-notarization.zip"
APP_NOTARY_OUTPUT="$WORK_DIR/notarytool-app.txt"
ditto -c -k --keepParent "$SIGNED_APP" "$APP_ZIP"
xcrun notarytool submit "$APP_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait | tee "$APP_NOTARY_OUTPUT"
grep -q 'status: Accepted' "$APP_NOTARY_OUTPUT" || die "Apple did not accept the app notarization"
APP_SUBMISSION_ID="$(awk '/^[[:space:]]*id:/ { print $2; exit }' "$APP_NOTARY_OUTPUT")"
rm -f "$APP_ZIP"

log "Stapling and validating app ticket"
xcrun stapler staple "$SIGNED_APP"
xcrun stapler validate "$SIGNED_APP"

log "Creating test DMG"
STAGE_DIR="$WORK_DIR/stage"
UNSIGNED_DMG="$WORK_DIR/$ARTIFACT_BASE.dmg"
mkdir -p "$STAGE_DIR"
ditto "$SIGNED_APP" "$STAGE_DIR/$APP_NAME.app"
ln -s /Applications "$STAGE_DIR/Applications"
hdiutil create -volname "$APP_NAME $VERSION Test" -srcfolder "$STAGE_DIR" -format UDZO -ov "$UNSIGNED_DMG"

log "Applying Developer ID signature to DMG"
codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$UNSIGNED_DMG"
codesign --verify --verbose=2 "$UNSIGNED_DMG"

log "Submitting DMG to Apple notarization"
DMG_NOTARY_OUTPUT="$WORK_DIR/notarytool-dmg.txt"
xcrun notarytool submit "$UNSIGNED_DMG" --keychain-profile "$NOTARY_PROFILE" --wait | tee "$DMG_NOTARY_OUTPUT"
grep -q 'status: Accepted' "$DMG_NOTARY_OUTPUT" || die "Apple did not accept the DMG notarization"
DMG_SUBMISSION_ID="$(awk '/^[[:space:]]*id:/ { print $2; exit }' "$DMG_NOTARY_OUTPUT")"

log "Stapling and validating DMG ticket"
xcrun stapler staple "$UNSIGNED_DMG"
xcrun stapler validate "$UNSIGNED_DMG"
codesign --verify --verbose=2 "$UNSIGNED_DMG"
spctl -a -vv -t open --context context:primary-signature "$UNSIGNED_DMG"

log "Mounting DMG for exact-artifact validation"
mkdir -p "$MOUNT_DIR"
hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT_DIR" "$UNSIGNED_DMG" >/dev/null
MOUNTED=1
MOUNTED_APP="$MOUNT_DIR/$APP_NAME.app"
[[ -d "$MOUNTED_APP" ]] || die "mounted DMG does not contain $APP_NAME.app"
[[ -L "$MOUNT_DIR/Applications" ]] || die "mounted DMG is missing the Applications shortcut"
[[ "$(plutil -extract CFBundleShortVersionString raw "$MOUNTED_APP/Contents/Info.plist")" == "$VERSION" ]] || die "mounted app version mismatch"
[[ "$(plutil -extract CFBundleVersion raw "$MOUNTED_APP/Contents/Info.plist")" == "$BUILD" ]] || die "mounted app build mismatch"
xcrun stapler validate "$MOUNTED_APP"
codesign --verify --deep --strict --verbose=2 "$MOUNTED_APP"
spctl -a -vv -t exec "$MOUNTED_APP"
hdiutil detach "$MOUNT_DIR" >/dev/null
MOUNTED=0

log "Saving local release artifacts"
if [[ "$OVERWRITE" -eq 1 ]]; then
  for output_path in "$FINAL_DMG" "$CHECKSUM_FILE" "$RECEIPT_FILE"; do
    [[ ! -e "$output_path" ]] || rm -f "$output_path"
  done
fi
ditto "$UNSIGNED_DMG" "$FINAL_DMG"
CHECKSUM="$(shasum -a 256 "$FINAL_DMG" | awk '{ print $1 }')"
printf '%s  %s\n' "$CHECKSUM" "$(basename "$FINAL_DMG")" > "$CHECKSUM_FILE"

COMMIT="$(git -C "$PROJECT_ROOT" rev-parse HEAD)"
{
  printf 'Product: %s\n' "$APP_NAME"
  printf 'Version: %s\n' "$VERSION"
  printf 'Build: %s\n' "$BUILD"
  printf 'Architecture: %s\n' "$ARCHITECTURES"
  printf 'Minimum macOS: %s\n' "$(plutil -extract LSMinimumSystemVersion raw "$SIGNED_APP/Contents/Info.plist")"
  printf 'Source commit: %s\n' "$COMMIT"
  printf 'Distribution: private test build; not published\n'
  printf 'Signature: Developer ID Application with hardened runtime and secure timestamp\n'
  printf 'App notarization: Accepted (%s)\n' "$APP_SUBMISSION_ID"
  printf 'DMG notarization: Accepted (%s)\n' "$DMG_SUBMISSION_ID"
  printf 'App ticket: stapled and validated\n'
  printf 'DMG ticket: stapled and validated\n'
  printf 'Mounted Gatekeeper check: accepted\n'
  printf 'SHA-256: %s\n' "$CHECKSUM"
  printf 'Artifact: %s\n' "$(basename "$FINAL_DMG")"
} > "$RECEIPT_FILE"

shasum -a 256 -c "$CHECKSUM_FILE"
SUCCEEDED=1
printf '\nPrivate test release completed:\n  %s\n  %s\n  %s\n' "$FINAL_DMG" "$CHECKSUM_FILE" "$RECEIPT_FILE"
