#!/bin/sh
# Every check before a commit: app tests, studio tests, and the repository rules
# (no private files tracked, no attribution trailers in tracked text or commit messages).
# Usage: tools/check.sh [--fast]   (--fast skips the app and UI test runs)
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

python3 -I tools/build_tokens.py --check 2>/dev/null \
  && note "ok   tokens match design/tokens.json" \
  || { note "FAIL tokens: GymApp/App/Tokens.swift or studio/web/tokens.css differ from design/tokens.json (edit the JSON, run tools/build_tokens.py)"; fail=1; }

python3 -I tools/check_literals.py 2>/tmp/gymapp-literals.log \
  && note "ok   no literal colours, paddings, radii or font sizes in the app" \
  || { note "FAIL literal design values (see /tmp/gymapp-literals.log)"; fail=1; }

(cd studio && .venv/bin/python -m unittest discover -s tests -t . >/tmp/gymapp-studio-tests.log 2>&1) \
  && note "ok   studio tests" || { note "FAIL studio tests (see /tmp/gymapp-studio-tests.log)"; fail=1; }

# Rulebook §13 cross-check: the studio's answers for the newest local backup, which the app's
# NextSetCrossCheckTests compares against NextSet (skipped when data/ has no backup).
newest=$(ls -t data/backups/*.sqlite 2>/dev/null | head -1)
if [ -n "$newest" ]; then
  studio/.venv/bin/python -I tools/cross_check_next.py "$newest" 2>/dev/null \
    && note "ok   studio answers written for the §13 cross-check ($(basename "$newest"))" \
    || { note "FAIL could not write the §13 cross-check"; fail=1; }
fi

if [ "${1:-}" != "--fast" ]; then
  xcodebuild test -project GymApp.xcodeproj -scheme GymApp \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' >/tmp/gymapp-tests.log 2>&1 \
    && note "ok   app tests ($(grep -oE 'with [0-9]+ tests' /tmp/gymapp-tests.log | tail -1))" \
    || { note "FAIL app tests (see /tmp/gymapp-tests.log)"; grep -E '✘|error:' /tmp/gymapp-tests.log | head -20; fail=1; }
  xcodebuild test -project GymApp.xcodeproj -scheme GymAppUITests \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' >/tmp/gymapp-uitests.log 2>&1 \
    && note "ok   UI tests ($(grep -E "^Test Case .*' passed" /tmp/gymapp-uitests.log | sort -u | wc -l | tr -d ' ') passed)" \
    || { note "FAIL UI tests (see /tmp/gymapp-uitests.log)"; grep -E "failed|error:" /tmp/gymapp-uitests.log | head -20; fail=1; }
fi
exit $fail
