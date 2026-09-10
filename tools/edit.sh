#!/usr/bin/env bash
# Local content editor for data/*.json. Opens a browser on
# http://127.0.0.1:8765 and runs until Ctrl+C. Nothing is hosted anywhere.
#   tools/edit.sh              this machine only
#   tools/edit.sh --lan        also a phone on the same wifi (never public)
#   tools/edit.sh --port=9000 --no-open
GODOT="${GODOT:-/c/Users/ryans/OneDrive/Desktop/Godot_v4.7.2-stable_win64.exe}"
cd "$(dirname "$0")/.." || exit 2
"$GODOT" --headless --path . --import >/dev/null 2>&1
"$GODOT" --headless --path . -s tools/edit_server.gd -- "$@"
