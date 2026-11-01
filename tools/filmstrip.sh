#!/usr/bin/env bash
# Scripted clips of tools/filmstrip_scenarios.json on a GPU box: sheets and mp4 in screenshots/filmstrip/. Shared driver: dot-game.
exec "$(dirname "$0")/../addons/dot_game/tools/dot_game_filmstrip.sh" "$@"
