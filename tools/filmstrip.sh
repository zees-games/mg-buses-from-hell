#!/usr/bin/env bash
# Scripted clips of tools/filmstrip_scenarios.json on a GPU box: sheets and mp4 in screenshots/filmstrip/. Shared driver: gs-game.
exec "$(dirname "$0")/../addons/gs_game/tools/gs_game_filmstrip.sh" "$@"
