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
trap 'rm -rf "$LCOV_DIR"' EXIT

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

# The app target is measured through xcodebuild. project.yml is the source of
# truth and Itchy.xcodeproj is generated (D-12), so generate it if absent rather
# than silently skipping the app target and reporting a partial figure as whole.
if [ "$PKG_DIR" = "Packages" ]; then
  if [ ! -d "Itchy.xcodeproj" ]; then
    command -v xcodegen >/dev/null 2>&1 || {
      echo "coverage: xcodegen not installed, cannot measure the app target" >&2
      exit 1
    }
    xcodegen generate --quiet >/dev/null 2>&1
  fi
  xcodebuild test -project Itchy.xcodeproj -scheme Itchy \
    -enableCodeCoverage YES -derivedDataPath "$LCOV_DIR/dd" >/dev/null 2>&1 || {
      echo "coverage: app target tests failed" >&2
      exit 1
    }
  PROF=$(find "$LCOV_DIR/dd" -name 'Coverage.profdata' 2>/dev/null | head -1)
  APP=$(find "$LCOV_DIR/dd" -path '*Itchy.app/Contents/MacOS/Itchy' -type f 2>/dev/null | head -1)
  if [ -n "$PROF" ] && [ -n "$APP" ]; then
    xcrun llvm-cov export -format=lcov -instr-profile "$PROF" "$APP" \
      > "$LCOV_DIR/App.lcov" 2>/dev/null
  else
    echo "coverage: could not locate app coverage data" >&2
    exit 1
  fi
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

measured = {f: d for f, d in files.items() if not excluded(f)}
skipped = len(files) - len(measured)

total = covered = 0
rows = []
for path, lines in sorted(measured.items()):
    t = len(lines)
    c = sum(1 for h in lines.values() if h > 0)
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
