#!/usr/bin/env bash
# Buses from Hell visual QA, one capture run (tools/visual_qa.gd); the driver is gs-game's gs_game_visual_qa.sh.
exec bash "$(dirname "$0")/../addons/gs_game/tools/gs_game_visual_qa_shot.sh" --script tools/visual_qa.gd -- "$@"
