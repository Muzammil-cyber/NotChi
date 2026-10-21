#!/usr/bin/env bash
# Builds NotChi.app (universal) and NotChi.dmg into ./build.
#
#   scripts/build-app.sh             # signs with your "Apple Development" identity if present
#                                    # (free Apple ID works), otherwise ad-hoc
#   SIGN_ID="NotChi Dev" scripts/build-app.sh   # sign with a specific identity
#   SIGN_ID=- scripts/build-app.sh   # force ad-hoc (what CI does)
#
# A stable identity matters: with ad-hoc signing every build is a "new app" to macOS
# and the Accessibility grant stops applying after each rebuild.
#   SKIP_DMG=1 scripts/build-app.sh  # app bundle only
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
OUT="$ROOT/build"
APP="$OUT/NotChi.app"
if [[ -z "${SIGN_ID:-}" ]]; then
  SIGN_ID="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/ {print $2; exit}')"
  SIGN_ID="${SIGN_ID:--}"
fi
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)}"

echo "==> Building release binary"
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/NotChi"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NotChi"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" 2>/dev/null || true
fi

echo "==> Signing (identity: $SIGN_ID)"
codesign --force --deep --options runtime --sign "$SIGN_ID" "$APP"
codesign --verify --verbose=1 "$APP"

if [[ -z "${SKIP_DMG:-}" ]]; then
  echo "==> Creating DMG"
  STAGE="$(mktemp -d)"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  cp Resources/DMG/*.txt "$STAGE/" 2>/dev/null || true
  rm -f "$OUT/NotChi.dmg"
  hdiutil create -volname "NotChi" -srcfolder "$STAGE" -ov -format UDZO "$OUT/NotChi.dmg" >/dev/null
  rm -rf "$STAGE"
  echo "==> $OUT/NotChi.dmg"
fi
echo "==> Done: $APP"
