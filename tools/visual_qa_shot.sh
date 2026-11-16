#!/usr/bin/env bash
# Buses from Hell visual QA, one capture run (tools/visual_qa.gd); the driver is dot-game's dot_game_visual_qa.sh.
exec bash "$(dirname "$0")/../addons/dot_game/tools/dot_game_visual_qa_shot.sh" --script tools/visual_qa.gd -- "$@"
