#!/usr/bin/env bash
#
# game.sh -- play, host and test this game with one command each.
#
#   ./game.sh                      play it offline, in a window
#   ./game.sh play [-- ARGS]       the same; ARGS go to the game
#   ./game.sh online               run a local server plus the browser client, print the link
#   ./game.sh online down          stop it again
#   ./game.sh server               run a local dedicated server only (Ctrl+C stops it)
#   ./game.sh server check         start the server, load the game, stop; exit 0 if it worked
#   ./game.sh server -- ARGS       ARGS go to dot-server-deploy's ./server (e.g. -- --port 7000)
#   ./game.sh test                 parse every script, then run every test suite
#   ./game.sh test NAME...         run only these suites (e.g. ./game.sh test headless_net)
#   ./game.sh suites               list the test suites
#   ./game.sh shot [ARGS]          save a screenshot to screenshots/ (tools/shot.sh or tools/screenshot.sh)
#   ./game.sh soak [BOWL] [MIN]    bot soak on tools/soak.tscn (report in .godot/test-logs/soak-BOWL.json)
#
# Options (before the command):
#   --godot PATH     the Godot 4.7 binary to use (default: $GODOT, then godot on PATH)
#   --timeout SEC    the longest one test suite may run (default 900; headless_run has 1800 unless this is given)
#   --no-parse       skip the parse pass in `test`
#
# `online` and `server` use dot-server-deploy, found next to this repository (or at
# $DOT_SERVER_DEPLOY). dot-bootstrap puts it there. Both rebuild this game's pack first, so
# what you play is what is on disk now.
#
# The same script is in every game repository; only the settings below differ.

# --- This game ------------------------------------------------------------------
# PACK is the game's id in dot-server-deploy (empty if it has no server), EXTRA_PACKS
# are other packs it needs as id:repository pairs, and SUITES are the scenes in
# examples/ that test it.
GAME_NAME="Buses From Hell"
PACK="buses"
EXTRA_PACKS=""
SUITES="headless_mapcfg headless_run headless_net headless_workshop dedicated"
# --------------------------------------------------------------------------------

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT" || exit 1

GODOT="${GODOT:-godot}"
TIMEOUT=900
TIMEOUT_GIVEN=0
# A suite that legitimately runs longer than the default, as name=seconds; headless_run took 849 s
# of 900 on a laptop GPU box. An explicit --timeout still wins for every suite.
SUITE_TIMEOUTS="headless_run=1800"
PARSE=1
RED=$'\033[31m'; GRN=$'\033[32m'; YLW=$'\033[33m'; OFF=$'\033[0m'
CR=$'\r\033[K'
[ -t 1 ] || { RED=""; GRN=""; YLW=""; OFF=""; CR=""; }

die() { printf '%s%s%s\n' "$RED" "$1" "$OFF" >&2; exit "${2:-1}"; }
usage() { sed -n '3,24p' "$ROOT/$(basename "${BASH_SOURCE[0]}")" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
    case "$1" in
        --godot) GODOT="${2:?--godot needs a path}"; shift 2 ;;
        --godot=*) GODOT="${1#*=}"; shift ;;
        --timeout) TIMEOUT="${2:?--timeout needs seconds}"; TIMEOUT_GIVEN=1; shift 2 ;;
        --timeout=*) TIMEOUT="${1#*=}"; TIMEOUT_GIVEN=1; shift ;;
        --no-parse) PARSE=0; shift ;;
        -h|--help|help) usage; exit 0 ;;
        *) break ;;
    esac
done

command -v "$GODOT" >/dev/null 2>&1 || die "Godot not found: '$GODOT'. Install Godot 4.7 or pass --godot PATH." 2

cmd="${1:-play}"
[ $# -gt 0 ] && shift

# The addons are links that dot-bootstrap makes. Without them nothing parses, and the
# errors read like a broken game rather than a missing step.
check_addons() {
    local missing=""
    while read -r name; do
        [ -e "addons/$name/plugin.cfg" ] || [ -d "addons/$name" ] || missing="$missing $name"
    done < <(sed -n 's|^/addons/\([^/]*\)/\{0,1\}$|\1|p' .gitignore 2>/dev/null)
    [ -z "$missing" ] || die "Missing addons:$missing
Run dot-bootstrap first: https://github.com/modcommunity/dot-bootstrap" 2
}

deploy_dir() {
    local dir="${DOT_SERVER_DEPLOY:-$ROOT/../dot-server-deploy}"
    [ -x "$dir/server" ] || die "dot-server-deploy not found at $dir (run its ./setup.sh, or set DOT_SERVER_DEPLOY)." 2
    (cd "$dir" && pwd)
}

# Rebuild this game's pack, and the packs it needs, from the checkouts on disk.
pack_all() {
    [ -n "$PACK" ] || die "$GAME_NAME has no server pack." 2
    local deploy repo id pair
    deploy="$(deploy_dir)"
    for pair in $EXTRA_PACKS; do
        id="${pair%%:*}"; repo="${pair#*:}"
        echo "packing $id"
        (cd "$deploy" && ./server pack "$id" --source "$ROOT/../$repo") >/dev/null || die "could not pack $id"
    done
    "$GODOT" --headless --path . --import >/dev/null 2>&1
    echo "packing $PACK"
    (cd "$deploy" && ./server pack "$PACK" --source "$ROOT") >/dev/null || die "could not pack $PACK"
}

run_suite() {
    local scene="$1" log out status summary kv TIMEOUT="$TIMEOUT"
    if [ "$TIMEOUT_GIVEN" -eq 0 ]; then
        for kv in $SUITE_TIMEOUTS; do [ "${kv%%=*}" = "$scene" ] && TIMEOUT="${kv#*=}"; done
    fi
    [ -f "examples/$scene.tscn" ] || { printf '  %s??%s   %s: no examples/%s.tscn\n' "$YLW" "$OFF" "$scene" "$scene"; return 1; }
    mkdir -p .godot/test-logs
    log=".godot/test-logs/$scene.log"
    [ -t 1 ] && printf '  ..   %s' "$scene"
    timeout "$TIMEOUT" "$GODOT" --headless --path . "res://examples/$scene.tscn" >"$log" 2>&1
    status=$?
    summary="$(grep -Eo '[0-9]+ (passed|checks), [0-9]+ failed' "$log" | tail -1)"
    if [ "$status" -eq 124 ]; then
        out="did not finish within ${TIMEOUT}s"
    elif [ "$status" -ne 0 ]; then
        out="exited $status"
    elif grep -qE 'SCRIPT ERROR|Parse Error' "$log"; then
        # A script error aborts one test, not the run, so the suite can still exit 0.
        out="script error in the output"
    elif grep -qE 'resources still in use at exit|ObjectDB instances? ((were|was) )?leaked|RID allocations? of type .* (were|was) leaked' "$log"; then
        # Exit 0 and "0 failed" with objects left alive: a suite that does not free what it built.
        out="leaked objects at exit (run the scene with --verbose to name them)"
    else
        printf '%s  %sok%s   %s  %s\n' "$CR" "$GRN" "$OFF" "$scene" "$summary"
        return 0
    fi
    printf '%s  %sFAIL%s %s: %s  %s\n' "$CR" "$RED" "$OFF" "$scene" "$out" "$summary"
    grep -E 'FAIL|SCRIPT ERROR|Parse Error|ERROR' "$log" | head -15 | sed 's/^/       /'
    printf '       full log: %s\n' "$log"
    return 1
}

PARSE_NOISE='ObjectDB instances?( were| was)? leaked|resources still in use|Pages in use exist at exit|at: (cleanup|clear|~PagedAllocator)|Text-based project'

# Prints each script that does not parse and returns how many. ANY output for a script,
# past the noise above, is a failure: a warning-as-error reads as nothing else.
parse_all() {
    local fails=0 f out tool=addons/dot_core/tools/dot_parse_all.gd
    local scripts
    scripts="$(git ls-files '*.gd' 2>/dev/null || find . -name '*.gd' -not -path './.godot/*' -not -path './addons/*' | sed 's|^\./||')"
    if [ -f "$tool" ] && [ -z "${PARSE_PER_FILE:-}" ]; then
        # One process loads every script: about ten times faster than a start-up per
        # file (66 scripts: 40 s against 4 s), with the same verdicts. The tool prints a
        # "PARSE> res://path" marker before each script, so output still belongs to a
        # file; what comes before the first marker or after PARSE_END belongs to none.
        local list log line cur="" curout="" finished=0
        list="$(mktemp)"; log="$(mktemp)"
        printf '%s\n' "$scripts" > "$list"
        PARSE_LIST="$list" timeout 900 "$GODOT" --headless --path . --script "res://$tool" >"$log" 2>&1
        while IFS= read -r line; do
            case "$line" in
                'PARSE> '*|'PARSE_END')
                    if [ -n "$cur" ] && [ -n "$curout" ]; then
                        printf '  %sFAIL%s %s\n%s\n' "$RED" "$OFF" "$cur" "$curout"
                        fails=$((fails + 1))
                    fi
                    cur=""; curout=""
                    [ "$line" = PARSE_END ] || cur="${line#PARSE> res://}" ;;
                'PARSED '*) finished=1 ;;
                'PARSE_FAIL '*) [ -n "$cur" ] && [ -z "$curout" ] && curout="$line" ;;
                *)  [ -n "$cur" ] || continue
                    printf '%s\n' "$line" | grep -Ev '^(Godot Engine v|$)' | grep -Eivq "$PARSE_NOISE" || continue
                    curout="${curout:+$curout$'\n'}$line" ;;
            esac
        done < "$log"
        # No PARSED line: the tool itself died or timed out, which is a failure, not a pass.
        if [ "$finished" -eq 0 ]; then
            printf '  %sFAIL%s the parse tool did not finish\n' "$RED" "$OFF"
            tail -n 20 "$log"
            fails=$((fails + 1))
        fi
        rm -f "$list" "$log"
        return "$fails"
    fi
    # An older dot-core without the tool: one process per script.
    while read -r f; do
        [ -n "$f" ] || continue
        out="$(timeout 120 "$GODOT" --headless --path . --check-only --script "res://$f" 2>&1 \
            | grep -Ev '^(Godot Engine v|$)' | grep -Eiv "$PARSE_NOISE")"
        if [ -n "$out" ]; then
            printf '  %sFAIL%s %s\n%s\n' "$RED" "$OFF" "$f" "$out"
            fails=$((fails + 1))
        fi
    done <<< "$scripts"
    return "$fails"
}

do_test() {
    check_addons
    local fails=0 f out
    echo "importing"
    timeout 600 "$GODOT" --headless --path . --import >/dev/null 2>&1

    if [ "$PARSE" = 1 ] && [ $# -eq 0 ]; then
        echo "parsing every script"
        parse_all
        fails=$?
        [ "$fails" -eq 0 ] && printf '  %sok%s   every script parses\n' "$GRN" "$OFF"
    fi

    echo "running the suites"
    local scene
    for scene in ${*:-$SUITES}; do
        run_suite "${scene%.tscn}" || fails=$((fails + 1))
    done

    echo
    [ "$fails" -eq 0 ] && { printf '%sall passed%s\n' "$GRN" "$OFF"; return 0; }
    printf '%s%d failed%s\n' "$RED" "$fails" "$OFF"
    return 1
}

case "$cmd" in
    play)
        check_addons
        [ "${1:-}" = "--" ] && shift
        exec "$GODOT" --path . -- "$@"
        ;;
    online)
        if [ "${1:-}" = "down" ]; then
            exec "$(deploy_dir)/play.sh" down
        fi
        case "${1:-}" in ""|-*) ;; *) PACK="$1"; shift ;; esac
        check_addons
        pack_all
        exec "$(deploy_dir)/play.sh" "$PACK"
        ;;
    server)
        sub="run"
        case "${1:-}" in run|check|config) sub="$1"; shift ;; esac
        check_addons
        pack_all
        [ "${1:-}" = "--" ] && shift
        cd "$(deploy_dir)" || exit 1
        exec ./server "$sub" --game "$PACK" "$@"
        ;;
    test)
        do_test "$@"
        ;;
    soak)
        [ -f tools/soak.tscn ] || die "$GAME_NAME has no bot soak (tools/soak.tscn)." 2
        check_addons
        soak_args=()
        [ -n "${1:-}" ] && { soak_args+=(--map "$1"); shift; }
        [ -n "${1:-}" ] && { soak_args+=(--minutes "$1"); shift; }
        mkdir -p .godot/test-logs
        timeout "$TIMEOUT" "$GODOT" --headless --path . res://tools/soak.tscn -- "${soak_args[@]}" "$@" \
            2>&1 | tee .godot/test-logs/soak.log | grep -E '^SOAK|^soak|SCRIPT ERROR|Parse Error|ERROR|FAIL'
        exit "${PIPESTATUS[0]}"
        ;;
    suites)
        printf '%s\n' $SUITES
        ;;
    shot)
        for tool in tools/shot.sh tools/screenshot.sh; do
            [ -x "$tool" ] || continue
            if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
                # The tool's own header comment is its usage.
                sed -n '2,/^[^#]/p' "$tool" | sed '$d' | sed 's/^# \{0,1\}//'
                exit 0
            fi
            exec "$tool" "$@"
        done
        die "$GAME_NAME has no screenshot tool." 2
        ;;
    *)
        usage
        exit 2
        ;;
esac
