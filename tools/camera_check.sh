#!/usr/bin/env bash
# The third-person and chase cameras round the course (armed), and a stand-in run into a
# player's back with mp_solidplayers on and off. --render adds both views and the walk-in.
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "${1:-}" = "--render" ]; then
  exec timeout 300 xvfb-run -a "${GODOT:-godot}" --path . --resolution 1280x720 res://tools/camera_check.tscn -- --render
fi
exec timeout 300 "${GODOT:-godot}" --headless --path . res://tools/camera_check.tscn
