#!/usr/bin/env bash
# Runs the suite, and refuses to hang.
#
# By default the UI tests are skipped, because they are the only part that needs
# macOS automation permission — and a permission prompt blocks invisibly, which
# presents as a hang rather than as a question. `--ui` includes them, and CI runs
# them as a separate job so an environment that cannot grant automation does not
# block everything else.
#
# Everything here runs locally against a store of at most twenty small files.
# Nothing legitimately takes minutes, so every stage has a hard ceiling and a
# stage that exceeds it is reported as a failure rather than left running.
#
# Orphaned processes are killed first. An Itchy instance left behind by an
# interrupted run confuses XCUIApplication, which expects to own the process it
# launches, and the symptom is a test run that never finishes.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

PACKAGE_TIMEOUT="${ITCHY_PACKAGE_TIMEOUT:-120}"
BUILD_TIMEOUT="${ITCHY_BUILD_TIMEOUT:-420}"
# Generous, because `xcodebuild test` re-checks the build even after
# build-for-testing has succeeded, so this covers compiling as well as running.
# The sharp ten-second rule is enforced per test instead —
# executionTimeAllowance on the XCTest cases and bounded waits in the Swift
# Testing ones (Tests/ItchyTests/TestTiming.swift). This ceiling exists only so
# that a wedged run fails instead of continuing indefinitely.
APP_TIMEOUT="${ITCHY_APP_TIMEOUT:-420}"
DD="${ITCHY_DERIVED_DATA:-.build/DerivedData}"
# UI tests are opt-in: they need automation permission, and nothing else does.
RUN_UI="${ITCHY_RUN_UI:-0}"
[ "${1:-}" = "--ui" ] && RUN_UI=1
[ "${1:-}" = "--ui-only" ] && { RUN_UI=1; UI_ONLY=1; }
UI_ONLY="${UI_ONLY:-0}"
# Named explicitly: without it xcodebuild stops to resolve an ambiguous macOS
# destination and simply waits, which reads as a hung test run.
DESTINATION="platform=macOS,arch=$(uname -m)"

pass() { printf '  \033[32mok\033[0m   %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; }

reap() {
  pkill -9 -f "Itchy.app/Contents/MacOS/Itchy" 2>/dev/null
  pkill -9 -f "ItchyUITests-Runner" 2>/dev/null
  pkill -9 -f "ItchyCorePackageTests" 2>/dev/null
  pkill -9 -f "ItchyServicesPackageTests" 2>/dev/null
  return 0
}

# A timeout that works without coreutils.
run_with_timeout() {
  local seconds="$1"; shift
  "$@" &
  local pid=$!
  local waited=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge "$seconds" ]; then
      kill -9 "$pid" 2>/dev/null
      reap
      return 124
    fi
    sleep 1
    waited=$((waited + 1))
  done
  wait "$pid"
}

echo "Tests"
reap
trap reap EXIT

FAILED=0

for package in ItchyCore ItchyServices; do
  if run_with_timeout "$PACKAGE_TIMEOUT" \
      bash -c "cd Packages/$package && swift test" >/tmp/itchy-$package.log 2>&1; then
    pass "$package"
  else
    code=$?
    [ $code -eq 124 ] && fail "$package timed out after ${PACKAGE_TIMEOUT}s (a hung test is a failed test)" \
      || fail "$package"
    grep -E "✘|error:" "/tmp/itchy-$package.log" | head -5 | sed 's/^/       /'
    FAILED=1
  fi
done

if ! bash -c "cd Harness && swift build" >/dev/null 2>&1; then
  fail "itchyctl does not build"
  FAILED=1
else
  pass "itchyctl builds"
fi

# One step rather than build-for-testing plus test-without-building: the split
# would give the test phase its own ceiling, but test-without-building stalls
# after resolving the package graph on this toolchain and never starts. The
# ten-second rule is enforced inside the suites instead, where it belongs —
# executionTimeAllowance on the XCTest cases and bounded waits in the Swift
# Testing ones (Tests/ItchyTests/TestTiming.swift). This ceiling only catches a
# run that wedges as a whole.
# Built as its own step. `test-without-building` would be the obvious way to
# then run the tests alone, but it stalls after resolving the package graph on
# this toolchain and never starts — verified twice. So the test step is an
# ordinary `xcodebuild test` whose build phase is already satisfied.
if ! run_with_timeout "$BUILD_TIMEOUT" \
    xcodebuild build-for-testing -project Itchy.xcodeproj -scheme Itchy \
    -destination "$DESTINATION" -derivedDataPath "$DD" -quiet \
    >/tmp/itchy-build.log 2>&1; then
  fail "app target did not build"
  grep -E "error:" /tmp/itchy-build.log | head -6 | sed 's/^/       /'
  exit 1
fi
pass "app target builds"

SKIP_UI_FLAG="-skip-testing:ItchyUITests"
[ "$RUN_UI" = "1" ] && SKIP_UI_FLAG=""
[ "$UI_ONLY" = "1" ] && SKIP_UI_FLAG="-only-testing:ItchyUITests"

if run_with_timeout "$APP_TIMEOUT" \
    xcodebuild test -project Itchy.xcodeproj -scheme Itchy \
    -destination "$DESTINATION" -derivedDataPath "$DD" $SKIP_UI_FLAG \
    >/tmp/itchy-app.log 2>&1; then
  pass "app target$([ "$RUN_UI" = "1" ] && echo " (including UI)" || echo " (UI skipped)")"
else
  code=$?
  if [ $code -eq 124 ]; then
    fail "app tests exceeded ${APP_TIMEOUT}s — a hung run is a failed run"
    if [ "$RUN_UI" = "1" ]; then
      echo "       UI tests need macOS automation permission. If a prompt is" >&2
      echo "       waiting on screen, answering it once is enough — provided" >&2
      echo "       'make sign-setup' has been run, or it returns every build." >&2
    fi
    grep -E "Test Case.*started" /tmp/itchy-app.log | grep -v linkd | tail -1 \
      | sed 's/^/       last started: /'
  else
    fail "app target"
  fi
  grep -E "✘.*recorded|Test Case.*failed|error:" /tmp/itchy-app.log \
    | grep -v linkd | head -6 | sed 's/^/       /'
  FAILED=1
fi

exit $FAILED
