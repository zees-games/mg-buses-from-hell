#!/usr/bin/env bash
# Thin wrapper: the script is shared (gs-game/tools), the game-specific part is tools/qa.conf.
cd "$(dirname "$0")/.." && exec ../gs-game/tools/perf_budget.sh "$@"
