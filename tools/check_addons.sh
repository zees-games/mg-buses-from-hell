#!/usr/bin/env bash
# Warns when this checkout's addons/ differ from what .gitignore declares (the dependency manifest):
# a missing or dangling link, or a native library older than its `# bootstrap-natives: <repo> <tag>` pin.
#   tools/check_addons.sh [--strict] [checkout]   warnings only (exit 0); --strict exits 1 on any;
#                                                 [checkout] defaults to this repo, e.g. a main checkout to audit
# Entries after a `# bootstrap-optional` line are not required. A bare git worktree has no links: tools/link_worktree.sh.
# A stale main checkout shows up as phantom failures; fix with dot-bootstrap, never by editing the checkout.
strict=0; [ "${1:-}" = "--strict" ] && { strict=1; shift; }
cd "${1:-$(dirname "${BASH_SOURCE[0]}")/..}" || exit 2
GI="$(dirname "${BASH_SOURCE[0]}")/../.gitignore"; [ -n "${1:-}" ] || GI=.gitignore
bad=0; warn() { echo "check_addons: $*" >&2; bad=1; }
while read -r name; do
    if [ ! -e "addons/$name" ]; then
        if [ -L "addons/$name" ]; then warn "addons/$name is a dangling link"; else warn "addons/$name is missing"; fi
    fi
done < <(awk '/^# bootstrap-optional/{o=1; next} /^\/addons\/[^\/*]+\/?$/{ if(!o){sub(/^\/addons\//,""); sub(/\/$/,""); print} } !/^\/addons/ && !/^#/{o=0}' "$GI" 2>/dev/null)
plat="$(uname -s | tr A-Z a-z)-$(uname -m)"
while read -r repo tag dir; do
    dir="${dir:-bin}"; f="addons/${repo//-/_}/$dir/.natives-$plat"
    [ "$dir" = bin ] || [ -e "$f" ] || continue   # no marker for a custom dir: cannot tell
    [ -e "addons/${repo//-/_}" ] || continue
    have="$(awk 'NR==1{print $1}' "$f" 2>/dev/null)"
    if [ -z "$have" ]; then warn "$repo native for $plat not fetched (pin $tag)"
    elif [ "$(printf '%s\n%s\n' "$have" "$tag" | sort -V | head -1)" != "$tag" ]; then warn "$repo native is $have, pin is $tag"; fi
done < <(sed -n 's|^# bootstrap-natives: \([^ ]*\) \(v[^ ]*\) *\([^ ]*\).*|\1 \2 \3|p' "$GI" 2>/dev/null)
[ "$bad" = 0 ] && echo "check_addons: addons match .gitignore"
[ "$strict" = 1 ] && exit "$bad"; exit 0
