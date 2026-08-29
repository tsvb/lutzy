#!/bin/zsh
# Build and launch exactly this checkout's LUTzy for visual acceptance.
#
# LaunchServices identifies applications primarily by bundle ID.  Opening a
# name such as `open -a LUTzy` can therefore activate an already-running copy
# from a different worktree.  This launcher closes every stale LUTzy process,
# opens the freshly-built bundle by absolute path, and verifies that the
# resulting process is executing that exact bundle binary.
set -euo pipefail

root=${0:a:h:h}
prepare_only=false
configuration=debug

if [[ ${1:-} == "--prepare-only" ]]; then
    prepare_only=true
    shift
fi
if [[ $# -gt 0 ]]; then
    configuration=$1
    shift
fi
if [[ $# -ne 0 || ( "$configuration" != "debug" && "$configuration" != "release" ) ]]; then
    echo "usage: $0 [--prepare-only] [debug|release]" >&2
    exit 64
fi

"$root/scripts/make-app.sh" "$configuration" >/dev/null

app="$root/build/LUTzy.app"
binary="$app/Contents/MacOS/LUTzy"
plist="$app/Contents/Info.plist"
commit=$(/usr/libexec/PlistBuddy -c 'Print :LUTzyBuildCommit' "$plist")
branch=$(/usr/libexec/PlistBuddy -c 'Print :LUTzyBuildBranch' "$plist")
dirty=$(/usr/libexec/PlistBuddy -c 'Print :LUTzyBuildDirty' "$plist")
dirty_suffix=""
[[ "$dirty" == "true" ]] && dirty_suffix="+dirty"
identity="$branch@$commit$dirty_suffix"

if $prepare_only; then
    echo "ready $app ($identity, $configuration)"
    exit 0
fi

# Do not let LaunchServices redirect acceptance to an older already-running
# copy.  TERM is intentional here: LUTzy persists user mutations when they
# happen, and the launcher refuses to continue if a process will not exit.
if /usr/bin/pgrep -x LUTzy >/dev/null 2>&1; then
    /usr/bin/pkill -TERM -x LUTzy
    for _attempt in {1..50}; do
        /usr/bin/pgrep -x LUTzy >/dev/null 2>&1 || break
        /bin/sleep 0.1
    done
fi

if /usr/bin/pgrep -x LUTzy >/dev/null 2>&1; then
    echo "error: an older LUTzy process would not quit; no acceptance build was opened" >&2
    exit 70
fi

/usr/bin/open -n "$app"

launched_pid=""
for _attempt in {1..100}; do
    while IFS= read -r candidate_pid; do
        [[ -n "$candidate_pid" ]] || continue
        process_command=$(/bin/ps -p "$candidate_pid" -o command= 2>/dev/null || true)
        if [[ "$process_command" == "$binary" || "$process_command" == "$binary "* ]]; then
            launched_pid=$candidate_pid
            break
        fi
    done < <(/usr/bin/pgrep -x LUTzy 2>/dev/null || true)
    [[ -n "$launched_pid" ]] && break
    /bin/sleep 0.1
done

if [[ -z "$launched_pid" ]]; then
    echo "error: LUTzy opened, but not from the expected binary: $binary" >&2
    exit 70
fi

# A process is not yet an acceptance surface.  A main-thread regression can
# leave the freshly built binary burning CPU without a window while an older
# app remains visible, which looks exactly like LaunchServices opened the
# wrong build.  Wait for the self-identifying window and verify its title too.
window_title=""
for _attempt in {1..300}; do
    window_title=$(/usr/bin/osascript \
        -e 'tell application "System Events" to tell process "LUTzy" to if (count windows) > 0 then return name of window 1' \
        2>/dev/null || true)
    [[ -n "$window_title" ]] && break
    /bin/sleep 0.1
done

short_commit=${commit[1,8]}
expected_title="LUTzy — $branch @ $short_commit$dirty_suffix · $configuration"
if [[ "$window_title" != "$expected_title" ]]; then
    echo "error: current LUTzy process did not expose its verified acceptance window" >&2
    echo "expected: $expected_title" >&2
    echo "actual:   ${window_title:-<no window after 30 seconds>}" >&2
    exit 70
fi

echo "launched $app ($identity, $configuration, pid $launched_pid, window ready)"
