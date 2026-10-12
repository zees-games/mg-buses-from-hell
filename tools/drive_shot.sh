#!/usr/bin/env bash
# A person driving a bus, from straight above, as a contact sheet (tools/drive_shot.gd).
#
#   tools/drive_shot.sh stop        # S from 15 m/s: brake, stop, reverse
#   tools/drive_shot.sh handbrake   # D and Ctrl from 12 m/s: the slide
#   tools/drive_shot.sh turn        # D alone from 12 m/s, to compare
#
# xvfb-run, never --headless: headless renders nothing and saves a frame of it.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p screenshots
how="${1:-stop}"
exec timeout 120 xvfb-run -a "${GODOT:-godot}" --path . --resolution 1280x720 \
    res://tools/drive_shot.tscn -- "--drive=$how" "--out=res://screenshots/drive_$how.png"
