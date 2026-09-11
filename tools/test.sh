#!/usr/bin/env bash
# Headless unit tests. Optional arg filters test files by substring.
GODOT="${GODOT:-/c/Users/ryans/OneDrive/Desktop/Godot_v4.7.2-stable_win64.exe}"
cd "$(dirname "$0")/.." || exit 2
# The class_name cache goes stale whenever a script is added outside the
# editor. Importing rebuilds it and costs about two seconds. Always do it.
"$GODOT" --headless --path . --import >/dev/null 2>&1
"$GODOT" --headless --path . -s tests/run.gd -- "$@"
