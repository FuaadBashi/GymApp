#!/bin/sh
# Every check before a commit: app tests, studio tests, and the repository rules
# (no private files tracked, no attribution trailers in tracked text or commit messages).
# Usage: tools/check.sh [--fast]   (--fast skips the app test run)
set -u
cd "$(dirname "$0")/.."
fail=0
note() { printf '%s\n' "$*"; }

tracked=$(git ls-files | grep -E '^(data/|docs/jefit-reference/|\.claude/)|(^|/)CLAUDE\.md$' || true)
[ -n "$tracked" ] && { note "FAIL private files are tracked:"; note "$tracked"; fail=1; } || note "ok   no private files tracked"

# The studio's Ask feature names the Claude API on purpose; only attribution patterns fail.
words=$(git grep -n -I -i -E 'co-authored-by|claude-session|claude code|generated (with|by) (claude|an ai|ai)|written by (claude|an ai)' -- . ':!tools/check.sh' || true)
[ -n "$words" ] && { note "FAIL attribution or assistant mentions:"; note "$words"; fail=1; } || note "ok   no attribution in tracked text"

trailers=$(git log -50 --format=%B | grep -i -E 'co-authored-by|claude-session|generated with' || true)
[ -n "$trailers" ] && { note "FAIL attribution in recent commit messages"; fail=1; } || note "ok   recent commit messages clean"

(cd studio && .venv/bin/python -m unittest discover -s tests -t . >/tmp/gymapp-studio-tests.log 2>&1) \
  && note "ok   studio tests" || { note "FAIL studio tests (see /tmp/gymapp-studio-tests.log)"; fail=1; }

if [ "${1:-}" != "--fast" ]; then
  xcodebuild test -project GymApp.xcodeproj -scheme GymApp \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' >/tmp/gymapp-tests.log 2>&1 \
    && note "ok   app tests ($(grep -oE 'with [0-9]+ tests' /tmp/gymapp-tests.log | tail -1))" \
    || { note "FAIL app tests (see /tmp/gymapp-tests.log)"; grep -E '✘|error:' /tmp/gymapp-tests.log | head -20; fail=1; }
fi
exit $fail
