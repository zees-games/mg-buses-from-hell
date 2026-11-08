#!/usr/bin/env bash
# Network chaos rig: the shared script lives in dot-game (tools/netchaos.sh); this game supplies tools/netchaos_{server,client}.tscn.
cd "$(dirname "$0")/.." || exit 2
exec "$(dirname "$0")/../../dot-game/tools/netchaos.sh" "$@"
