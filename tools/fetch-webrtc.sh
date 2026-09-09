#!/usr/bin/env bash
# Puts the native WebRTC implementation into the project. Godot ships the
# WebRTC *API* but not the implementation: without this, room codes are
# switched off and the HOST page says so. Run once per checkout; the
# binaries are gitignored (addons/webrtc/) rather than committed.
#
#   tools/fetch-webrtc.sh [zip-url]
#
# The default URL is the release this was written against. If it 404s, open
# https://github.com/godotengine/webrtc-native/releases and pass the URL of
# the "godot-extension" zip for the newest release that lists Godot 4.x.
set -e
cd "$(dirname "$0")/.."
URL="${1:-https://github.com/godotengine/webrtc-native/releases/latest/download/godot-extension-webrtc-native.zip}"
TMP="$(mktemp -d)"
echo "fetching $URL"
curl -fSL -o "$TMP/webrtc.zip" "$URL"
rm -rf addons/webrtc
mkdir -p addons
unzip -q "$TMP/webrtc.zip" -d "$TMP/out"
# The zip holds a single top-level folder (webrtc/) with the .gdextension in it.
SRC="$(find "$TMP/out" -name '*.gdextension' -printf '%h\n' | head -1)"
[ -n "$SRC" ] || { echo "no .gdextension in the zip"; exit 1; }
mv "$SRC" addons/webrtc
rm -rf "$TMP"
echo "installed addons/webrtc — restart the editor once so it registers, then set Config.NET.broker"
ls addons/webrtc
