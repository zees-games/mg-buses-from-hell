#!/usr/bin/env bash
# Records one filmstrip clip on a box with a display (gpu.sh runs only tools/*.sh). Logic: dot-game.
exec bash "$(dirname "$0")/../addons/dot_game/tools/dot_game_filmstrip_run.sh" "$@"
