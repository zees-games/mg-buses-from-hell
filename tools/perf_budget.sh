#!/usr/bin/env bash
# Thin wrapper: the script is shared (dot-game/tools), the game-specific part is tools/qa.conf.
cd "$(dirname "$0")/.." && exec ../dot-game/tools/perf_budget.sh "$@"
