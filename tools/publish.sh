#!/bin/bash
# Publishes this game's pack (id mg-buses-from-hell). Host addons come from the server (--host-addons); the README art and the
# gitignored web build are not runtime content.
#   tools/publish.sh [--version V | --bump patch] [--site URL --token-file F --dry-run ...]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$HERE/../dot-cloud/tools/publish_pack.sh" publish --source "$HERE" --id mg-buses-from-hell \
    --host-addons "$HERE/../dot-server-deploy/addons.lock" --exclude-dir web --exclude-dir screenshots --exclude-dir images \
    --lock "$HERE/content.lock.json" "$@"
