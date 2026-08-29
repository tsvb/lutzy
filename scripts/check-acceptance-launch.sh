#!/bin/zsh
set -euo pipefail

root=${0:a:h:h}
configuration=${1:-debug}

"$root/scripts/make-app.sh" "$configuration" >/dev/null

app="$root/build/LUTzy.app"
plist="$app/Contents/Info.plist"
expected_commit=$(git -C "$root" rev-parse --short=12 HEAD)
expected_branch=$(git -C "$root" branch --show-current)
[[ -n "$expected_branch" ]] || expected_branch="detached"
expected_dirty=false
[[ -n "$(git -C "$root" status --porcelain --untracked-files=normal)" ]] && expected_dirty=true

read_plist() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$plist" 2>/dev/null
}

[[ "$(read_plist LUTzyBuildCommit)" == "$expected_commit" ]]
[[ "$(read_plist LUTzyBuildBranch)" == "$expected_branch" ]]
[[ "$(read_plist LUTzyBuildRoot)" == "$root" ]]
[[ "$(read_plist LUTzyBuildConfiguration)" == "$configuration" ]]
[[ "$(read_plist LUTzyBuildDirty)" == "$expected_dirty" ]]
[[ -x "$root/scripts/launch-acceptance.sh" ]]

prepared=$("$root/scripts/launch-acceptance.sh" --prepare-only "$configuration")
[[ "$prepared" == *"$app"* ]]
expected_dirty_suffix=""
$expected_dirty && expected_dirty_suffix="+dirty"
[[ "$prepared" == *"$expected_branch@$expected_commit$expected_dirty_suffix"* ]]

echo "acceptance launcher identity -> PASS"
