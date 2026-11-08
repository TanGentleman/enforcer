#!/bin/sh
# End-to-end check against a real Claude Code CLI, offline and logged out:
# the hook runs before the login check, so a blocked prompt never needs auth.
# Usage: test/claude-code.sh [path/to/enforcer]   (needs `claude` on PATH)
set -eu

enforcer=$(cd "$(dirname "${1:-zig-out/bin/enforcer}")" && pwd)/$(basename "${1:-zig-out/bin/enforcer}")
claude=$(command -v claude)
home=$(mktemp -d)
trap 'rm -rf "$home"' EXIT
mkdir "$home/.claude"

ask() {
    env -i PATH="$(dirname "$claude"):/usr/bin:/bin" HOME="$home" "$claude" -p "$1" 2>&1 || true
}

HOME="$home" "$enforcer" on

out=$(ask "deploy with ghp_e2etoken")
echo "$out" | grep -q "blocked by hook" || { echo "FAIL: token prompt not blocked:"; echo "$out"; exit 1; }
echo "$out" | grep -q "GitHub token" || { echo "FAIL: no reason:"; echo "$out"; exit 1; }
if echo "$out" | grep -q "ghp_e2etoken"; then echo "FAIL: token echoed:"; echo "$out"; exit 1; fi

out=$(ask "hello")
if echo "$out" | grep -q "blocked by hook"; then echo "FAIL: clean prompt blocked:"; echo "$out"; exit 1; fi

HOME="$home" "$enforcer" off
out=$(ask "deploy with ghp_e2etoken")
if echo "$out" | grep -q "blocked by hook"; then echo "FAIL: still blocked after off:"; echo "$out"; exit 1; fi

echo "ok: $("$claude" --version)"
