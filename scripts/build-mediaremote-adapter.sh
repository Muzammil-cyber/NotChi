#!/usr/bin/env bash
# NotChi — https://github.com/Muzammil-cyber/NotChi
# Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Required Notice: keep this header in copies and derivatives (see LICENSE.md).
#
# Builds the vendored mediaremote-adapter (BSD-3, Vendor/mediaremote-adapter) into
# build/MediaRemoteAdapter.framework (universal) plus build/mediaremote-adapter.pl.
# Now Playing runs the script with /usr/bin/perl, which loads the framework; the app
# never links against it. Skips the compile when the framework is newer than its sources.
set -euo pipefail

cd "$(dirname "$0")/.."
SRC="Vendor/mediaremote-adapter"
OUT="build"
FW="$OUT/MediaRemoteAdapter.framework"
BIN="$FW/Versions/A/MediaRemoteAdapter"

mkdir -p "$OUT"
cp "$SRC/bin/mediaremote-adapter.pl" "$OUT/mediaremote-adapter.pl"

if [[ -f "$BIN" && -z "$(find "$SRC" -newer "$BIN" -type f -print -quit)" ]]; then
  echo "==> MediaRemoteAdapter.framework is up to date"
  exit 0
fi

echo "==> Building MediaRemoteAdapter.framework"
rm -rf "$FW"
mkdir -p "$FW/Versions/A/Resources" "$FW/Versions/A/Headers"
SOURCES=(
  "$SRC"/src/adapter/*.m
  "$SRC"/src/private/MediaRemote.m
  "$SRC"/src/utility/Debounce.m
  "$SRC"/src/utility/helpers.m
)
clang -dynamiclib -fobjc-arc -fvisibility=default -O2 \
  -arch arm64 -arch x86_64 -mmacosx-version-min=14.0 \
  -I "$SRC/include" -I "$SRC/src" \
  -framework Foundation -framework AppKit -framework UniformTypeIdentifiers -framework MediaPlayer \
  -install_name "@rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter" \
  "${SOURCES[@]}" -o "$BIN"
cp "$SRC/include/MediaRemoteAdapter.h" "$FW/Versions/A/Headers/"
cat > "$FW/Versions/A/Resources/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>MediaRemoteAdapter</string>
    <key>CFBundleIdentifier</key><string>com.notchi.app.MediaRemoteAdapter</string>
    <key>CFBundleName</key><string>MediaRemoteAdapter</string>
    <key>CFBundlePackageType</key><string>FMWK</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>0.1.0</string>
</dict>
</plist>
PLIST
ln -s A "$FW/Versions/Current"
ln -s Versions/Current/MediaRemoteAdapter "$FW/MediaRemoteAdapter"
ln -s Versions/Current/Resources "$FW/Resources"
ln -s Versions/Current/Headers "$FW/Headers"
# perl only loads signed code on Apple silicon; build-app.sh re-signs it with the app.
codesign --force --sign - "$FW" >/dev/null
echo "==> $FW"
