#!/usr/bin/env bash
# Regenerates the screenshots in docs/images from the running application.
#
# Runs ScreenshotCapture from the UI suite in two phases against a throwaway
# store that this script owns. The test runner is sandboxed and can write no
# files, so it only passes the store's path to the application and attaches its
# screenshots to the result bundle; this script damages the store between the
# phases and exports the attachments afterwards. XCUITest captures the windows,
# so no Screen Recording permission is needed. Automation Mode is, and is
# switched for the run exactly as `make test-ui` does (Scripts/automation-mode.sh).
#
#   make screenshots
#   ITCHY_SCREENSHOT_DIR=/tmp/shots make screenshots   # somewhere else

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

# shellcheck source=Scripts/automation-mode.sh
source Scripts/automation-mode.sh

DD="${ITCHY_DERIVED_DATA:-.build/DerivedData}"
OUT="${ITCHY_SCREENSHOT_DIR:-$PWD/docs/images}"
DESTINATION="platform=macOS,arch=$(uname -m)"
WORK=$(mktemp -d /tmp/itchy-screenshots.XXXXXX)
STORE="$WORK/store"
LOG="$WORK/xcodebuild.log"
NAMES="pad-panel welcome pad-faulted"

reap() {
  pkill -9 -f "/Build/Products/.*Itchy.app/Contents/MacOS/Itchy" 2>/dev/null
  pkill -9 -f "ItchyUITests-Runner" 2>/dev/null
  return 0
}

reap
trap 'automation_restore; reap; rm -rf "$WORK"' EXIT
trap 'exit 130' INT TERM

automation_prepare
case $? in
  0) ;;
  2)
    if [ "${ITCHY_UI_ALLOW_PROMPT:-0}" != "1" ]; then
      echo "screenshots: Automation Mode needs authentication, and there is no terminal to ask in"
      exit 1
    fi
    ;;
  *)
    echo "screenshots: could not switch Automation Mode"
    exit 1
    ;;
esac

mkdir -p "$STORE" "$OUT"

# The runner receives TEST_RUNNER_-prefixed variables with the prefix removed.
run_phase() {
  local test="$1"
  local bundle="$WORK/$test.xcresult"
  if ! TEST_RUNNER_ITCHY_UI_TEST_ROOT="$STORE" xcodebuild test \
      -project Itchy.xcodeproj -scheme Itchy -destination "$DESTINATION" \
      -derivedDataPath "$DD" -resultBundlePath "$bundle" \
      -only-testing:"ItchyUITests/ScreenshotCapture/$test" >"$LOG" 2>&1; then
    echo "screenshots: $test failed"
    "$(dirname "$0")/xcnoise.sh" <"$LOG" \
      | grep -E "error:|failed" | grep -v linkd | head -6 | sed 's/^/  /'
    exit 1
  fi
  if grep -q "Skipped" "$LOG" && ! grep -q "Test Case .*passed" "$LOG"; then
    echo "screenshots: $test was skipped; the store path did not reach the runner"
    exit 1
  fi
  xcrun xcresulttool export attachments --path "$bundle" --output-path "$WORK/attachments" \
    >/dev/null 2>&1 || { echo "screenshots: could not export attachments from $test"; exit 1; }
}

echo "screenshots: capturing a pad and About"
run_phase testCapturePadAndAbout

# Damage the store the way itchyctl's `fault content` does: the pad's content
# goes, its metadata stays.
content=$(find "$STORE/pads.noindex" -maxdepth 2 -name content.rtfd -type d | head -1)
if [ -z "$content" ]; then
  echo "screenshots: phase one left no pad in the store"
  exit 1
fi
rm -rf "$content"

echo "screenshots: capturing the faulted pad"
run_phase testCaptureFaultedPad

# Attachments are exported under generated names; the manifest maps each back
# to the name the test gave it.
python3 - "$WORK/attachments" "$OUT" $NAMES <<'PY' || exit 1
import json, pathlib, shutil, sys
source, destination, names = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3:]
found = {}
for test in json.loads((source / "manifest.json").read_text()):
    for attachment in test.get("attachments", []):
        readable = attachment.get("suggestedHumanReadableName", "")
        for name in names:
            if readable == name or readable.startswith(name + "_") or readable.startswith(name + "."):
                found[name] = source / attachment["exportedFileName"]
missing = [name for name in names if name not in found]
if missing:
    print("screenshots: no attachment for " + ", ".join(missing))
    sys.exit(1)
for name, path in found.items():
    shutil.copyfile(path, destination / f"{name}.png")
PY

echo "screenshots: written to $OUT"
