#!/bin/bash
# "Did any *code* in these files change?" — a ship gate that can tell a comment from a statement.
#
# Every step plan in `docs/superpowers/plans/` ends with a gate of roughly this shape:
#
#     git diff --stat main -- <four load-bearing files>
#     Expected: no output. If any of these moved, the design was wrong somewhere.
#
# That gate is right in intent and wrong in mechanism, and Step 10b proved it: re-run against its own
# merge base, `AdjustmentNode.swift` and `RenderPipeline.swift` both showed up. Every changed line was
# a doc comment — the §8.7 closures — so the design intent had held perfectly and the gate would still
# have failed the merge. A gate nobody can pass gets ignored, which is worse than no gate.
#
# This asks the question the plans meant to ask. Comment-only edits pass; a single moved statement
# fails, and prints the diff that failed it.
#
# Usage:
#   scripts/code-diff-gate.sh <base-ref> <file>...
#   scripts/code-diff-gate.sh main Sources/LUTzyKit/Models/AdjustmentNode.swift ...
#
# Compares each file at <base-ref> against the working tree. Exits 1 if any executable line differs.
#
# Scope, stated rather than implied: this strips whole-line `//` and `///` comments and blank lines.
# It does **not** strip trailing comments or `/* */` blocks, and it is not a parser — a `//` inside a
# string literal is code and stays. That is deliberate: over-stripping would let a real change hide,
# which is the failure this exists to prevent. Under-stripping only costs a false alarm you can read.
set -uo pipefail
cd "$(dirname "$0")/.."

if [[ $# -lt 2 ]]; then
    echo "usage: $0 <base-ref> <file>..." >&2
    exit 2
fi

BASE="$1"; shift

if ! git rev-parse --verify --quiet "$BASE" >/dev/null; then
    echo "not a ref: $BASE" >&2
    exit 2
fi

strip_comments() { grep -vE '^[[:space:]]*(///|//)' | grep -vE '^[[:space:]]*$'; }

CHANGED=0
COMMENT_ONLY=0

for file in "$@"; do
    if [[ ! -f "$file" ]]; then
        echo "MISSING   $file — deleted or renamed, which is itself a change"
        CHANGED=$((CHANGED + 1))
        continue
    fi

    old="$(git show "$BASE:$file" 2>/dev/null | strip_comments)"
    new="$(strip_comments < "$file")"

    if [[ "$old" == "$new" ]]; then
        if git diff --quiet "$BASE" -- "$file"; then
            echo "unchanged $file"
        else
            echo "comments  $file — doc comments only, no code moved"
            COMMENT_ONLY=$((COMMENT_ONLY + 1))
        fi
    else
        echo "CODE      $file — executable lines differ:"
        diff <(printf '%s\n' "$old") <(printf '%s\n' "$new") | sed 's/^/            /'
        CHANGED=$((CHANGED + 1))
    fi
done

echo
echo "================ gate ================"
echo "files with code changes:    $CHANGED"
echo "files with comments only:   $COMMENT_ONLY   (these pass)"

if [[ $CHANGED -ne 0 ]]; then
    echo "FAIL — $CHANGED file(s) changed code that was supposed to be untouched."
    exit 1
fi

echo "PASS — no executable line moved in any of the $# file(s)."
