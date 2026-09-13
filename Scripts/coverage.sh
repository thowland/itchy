#!/usr/bin/env bash
# Line coverage over the denominator defined in implementation plan §3.3.
#
# The number is meaningless without its denominator, so the denominator is
# computed from Scripts/coverage-exclusions.txt rather than left to the tool's
# default. Exits non-zero below the threshold (G3).
#
#   COVERAGE_MIN=80         override the floor
#   COVERAGE_REPORT=1       print per-file lines as well as the total
#   COVERAGE_PKG_DIR=...    directory holding the packages
#   COVERAGE_PACKAGES=...   space-separated package names
#   COVERAGE_EXCLUSIONS=... path to the exclusions file
#
# The last three exist so that Scripts/verify-coverage-gate.sh can point the
# same code at a deliberately under-covered fixture and prove the gate fails.
# A coverage gate nobody has watched fail is a coverage gate nobody knows works.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

MIN="${COVERAGE_MIN:-80}"
PKG_DIR="${COVERAGE_PKG_DIR:-Packages}"
PACKAGES="${COVERAGE_PACKAGES:-ItchyCore ItchyServices}"
EXCLUSIONS="${COVERAGE_EXCLUSIONS:-Scripts/coverage-exclusions.txt}"
LCOV_DIR=$(mktemp -d)
# Launching a built app registers it with LaunchServices, and deleting the
# directory does not unregister it. Every coverage run used to leave a dead
# record behind for com.wdogsystems.itchy — thirty-seven of them by the time
# anyone looked — beside the installed copy that Spotlight should be showing.
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
unregister_built_apps() {
  [ -x "$LSREGISTER" ] || return 0
  find "$LCOV_DIR" -name '*.app' -type d -prune 2>/dev/null | while IFS= read -r app; do
    "$LSREGISTER" -u "$app" >/dev/null 2>&1
  done
}
trap 'unregister_built_apps; rm -rf "$LCOV_DIR"' EXIT

for PKG in $PACKAGES; do
  DIR="$PKG_DIR/$PKG"
  [ -d "$DIR" ] || continue
  ( cd "$DIR" && swift test --enable-code-coverage >/dev/null 2>&1 ) || {
    echo "coverage: tests failed in $PKG" >&2
    exit 1
  }
  BIN=$( cd "$DIR" && swift build --show-bin-path 2>/dev/null )
  PROF="$BIN/codecov/default.profdata"
  BUNDLE="$BIN/${PKG}PackageTests.xctest/Contents/MacOS/${PKG}PackageTests"
  if [ -f "$PROF" ] && [ -f "$BUNDLE" ]; then
    xcrun llvm-cov export -format=lcov -instr-profile "$PROF" "$BUNDLE" \
      > "$LCOV_DIR/$PKG.lcov" 2>/dev/null
  fi
done

# The app target is measured through xcodebuild and read with xccov.
#
# Not llvm-cov: exporting lcov against the built application binary returns an
# empty profile for an Xcode app target, which silently reports the whole app as
# unmeasured rather than failing. xccov reads the same run's result bundle and
# gives per-file covered/executable counts, which is what the denominator needs.
if [ "$PKG_DIR" = "Packages" ]; then
  # Only when project.yml is newer: regenerating rewrites the project file and
  # forces a full rebuild, which would be most of what a coverage run spends.
  if [ ! -d "Itchy.xcodeproj" ] || [ project.yml -nt Itchy.xcodeproj ]; then
    command -v xcodegen >/dev/null 2>&1 || {
      echo "coverage: xcodegen not installed, cannot measure the app target" >&2
      exit 1
    }
    xcodegen generate --quiet >/dev/null 2>&1 && touch Itchy.xcodeproj
  fi
  # The UI suite is skipped here for the same reason Scripts/test.sh skips it:
  # it needs automation permission, and a coverage run that stops for a
  # permission prompt reads as a hang. The UI tests contribute almost nothing to
  # the measured denominator — by design, since D-11 keeps decisions out of the
  # views they drive.
  xcodebuild test -project Itchy.xcodeproj -scheme Itchy \
    -destination "platform=macOS,arch=$(uname -m)" -skip-testing:ItchyUITests \
    -enableCodeCoverage YES -derivedDataPath "$LCOV_DIR/dd" >/dev/null 2>&1 || {
      echo "coverage: app target tests failed" >&2
      exit 1
    }
  RESULT=$(find "$LCOV_DIR/dd/Logs/Test" -name '*.xcresult' -maxdepth 1 2>/dev/null | head -1)
  if [ -z "$RESULT" ]; then
    echo "coverage: no test result bundle; cannot measure the app target" >&2
    exit 1
  fi
  xcrun xccov view --report --json "$RESULT" > "$LCOV_DIR/app.json" 2>/dev/null || {
    echo "coverage: could not read app coverage from the result bundle" >&2
    exit 1
  }
fi

python3 - "$LCOV_DIR" "$MIN" "$EXCLUSIONS" <<'PY'
import os, re, sys

lcov_dir, minimum, exclusions = sys.argv[1], float(sys.argv[2]), sys.argv[3]

patterns = []
section = None
with open(exclusions) as fh:
    for line in fh:
        line = line.strip()
        if line in ("[capped]", "[not-source]"):
            section = line
            continue
        if not line or line.startswith("#"):
            continue
        patterns.append(re.compile(line))

# Build products and generated code are never part of the denominator.
always = [re.compile(r"/\.build/"), re.compile(r"\.derived/"),
          re.compile(r"/DerivedData/"), re.compile(r"^/Applications/"),
          re.compile(r"/\.swiftpm/")]

def excluded(path):
    return any(p.search(path) for p in patterns + always)

# path -> (covered, executable). Package data arrives per line from lcov; app
# data arrives pre-aggregated from xccov. Both end up in the same denominator.
counts = {}

app_report = os.path.join(lcov_dir, "app.json")
if os.path.exists(app_report):
    import json
    with open(app_report) as fh:
        report = json.load(fh)
    for target in report.get("targets", []):
        for entry in target.get("files", []):
            path = entry.get("path", "")
            executable = entry.get("executableLines", 0)
            covered = entry.get("coveredLines", 0)
            if not path or executable == 0:
                continue
            previous = counts.get(path, (0, 0))
            counts[path] = (previous[0] + covered, previous[1] + executable)

files, current = {}, None
for name in sorted(os.listdir(lcov_dir)):
    if not name.endswith(".lcov"):
        continue
    with open(os.path.join(lcov_dir, name)) as fh:
        for line in fh:
            line = line.strip()
            if line.startswith("SF:"):
                current = line[3:]
            elif line.startswith("DA:") and current:
                lineno, hits = line[3:].split(",")[:2]
                files.setdefault(current, {})[int(lineno)] = \
                    files.get(current, {}).get(int(lineno), 0) + int(hits)
            elif line == "end_of_record":
                current = None

for path, lines in files.items():
    executable = len(lines)
    hit = sum(1 for count in lines.values() if count > 0)
    previous = counts.get(path, (0, 0))
    counts[path] = (previous[0] + hit, previous[1] + executable)

measured = {f: d for f, d in counts.items() if not excluded(f)}
skipped = len(counts) - len(measured)

total = covered = 0
rows = []
for path, (c, t) in sorted(measured.items()):
    total += t
    covered += c
    rows.append((100.0 * c / t if t else 100.0, c, t, path))

if os.environ.get("COVERAGE_REPORT"):
    for pct, c, t, path in sorted(rows):
        rel = path.replace(os.getcwd() + "/", "")
        print(f"  {pct:6.2f}%  {c:5d}/{t:<5d}  {rel}")

pct = 100.0 * covered / total if total else 100.0
print(f"\ncoverage: {pct:.2f}%  ({covered}/{total} lines, "
      f"{len(measured)} files measured, {skipped} excluded)")
print(f"threshold: {minimum:.0f}%")

if total == 0:
    print("coverage: nothing measured — refusing to report a pass")
    sys.exit(1)
if pct + 1e-9 < minimum:
    print(f"coverage: FAIL — {pct:.2f}% is below the {minimum:.0f}% floor (G3)")
    sys.exit(1)
print("coverage: ok")
PY
