#!/usr/bin/env bash
# Runs the real game windowed in smoke mode. Screenshots and state JSON land
# in .smoke/ at the project root. Exit code is the game's.
GODOT="${GODOT:-/c/Users/ryans/OneDrive/Desktop/Godot_v4.7.2-stable_win64.exe}"
cd "$(dirname "$0")/.." || exit 2
OUT="$(pwd -W 2>/dev/null || pwd)/.smoke"
rm -rf .smoke
"$GODOT" --headless --path . --import >/dev/null 2>&1
"$GODOT" --path . --resolution 1280x720 -- --smoke "--smoke-out=$OUT" "$@"
