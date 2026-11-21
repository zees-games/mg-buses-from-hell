#!/usr/bin/env bash
# Records one filmstrip clip on a box with a display (gpu.sh runs only tools/*.sh). Logic: gs-game.
exec bash "$(dirname "$0")/../addons/gs_game/tools/gs_game_filmstrip_run.sh" "$@"
