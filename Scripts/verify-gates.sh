#!/usr/bin/env bash
# Proves the gates work, in both directions.
#
# Sprint 0's stated evidence is not that the gates report a pass — at this size
# they would pass over almost nothing. The evidence is that they fail when they
# should. A gate nobody has watched fail is a gate nobody knows works.
#
# Covers the coverage floor (G3) and the complexity cap that governs which files
# may be excluded from it (D-11, specification §15.3).

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

FAILED=0
pass() { printf '  \033[32mok\033[0m   %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAILED=1; }

echo "Gate verification"

# --- 1. An under-covered package must fail the gate --------------------------
OUT=$(COVERAGE_PKG_DIR=Tests/Fixtures \
      COVERAGE_PACKAGES=UnderCovered \
      COVERAGE_EXCLUSIONS=Tests/Fixtures/coverage-exclusions-fixture.txt \
      ./Scripts/coverage.sh 2>&1)
CODE=$?
if [ "$CODE" -eq 0 ]; then
  fail "under-covered fixture passed the gate (the gate is broken)"
  echo "$OUT" | sed 's/^/       /'
elif echo "$OUT" | grep -q "below the .* floor"; then
  pass "under-covered fixture fails the gate, for the right reason"
else
  fail "under-covered fixture failed, but not because of the floor"
  echo "$OUT" | sed 's/^/       /'
fi

# --- 2. The same fixture must pass when the floor is lowered below its figure -
# Distinguishes a working threshold from a script that always fails.
OUT=$(COVERAGE_MIN=10 \
      COVERAGE_PKG_DIR=Tests/Fixtures \
      COVERAGE_PACKAGES=UnderCovered \
      COVERAGE_EXCLUSIONS=Tests/Fixtures/coverage-exclusions-fixture.txt \
      ./Scripts/coverage.sh 2>&1)
if [ $? -eq 0 ]; then
  pass "the threshold is a threshold, not an unconditional failure"
else
  fail "fixture failed even below its own coverage figure"
  echo "$OUT" | sed 's/^/       /'
fi

# --- 3. Refuses to report a pass when nothing was measured -------------------
OUT=$(COVERAGE_PKG_DIR=Tests/Fixtures \
      COVERAGE_PACKAGES=UnderCovered \
      COVERAGE_EXCLUSIONS=Scripts/coverage-exclusions.txt \
      ./Scripts/coverage.sh 2>&1)
if [ $? -ne 0 ] && echo "$OUT" | grep -q "nothing measured"; then
  pass "an empty denominator is a failure, not a 100% pass"
else
  fail "an empty denominator did not fail"
  echo "$OUT" | sed 's/^/       /'
fi

# --- 4. The complexity cap must reject a branching file ----------------------
OUT=$(swiftlint lint --quiet --strict --config Scripts/swiftlint-excluded.yml \
        Tests/Fixtures/CapProbe/Branching.swift 2>&1)
if [ -n "$OUT" ]; then
  pass "complexity cap rejects a branching file"
else
  fail "complexity cap accepted a file containing a branch (D-11 is unenforced)"
fi

# --- 5. The complexity cap must accept genuine boilerplate -------------------
# Optional unwrapping is permitted; a cap that rejected everything would simply
# push every file off the exclusion list rather than discipline what goes on it.
OUT=$(swiftlint lint --quiet --strict --config Scripts/swiftlint-excluded.yml \
        Tests/Fixtures/CapProbe/Trivial.swift 2>&1)
if [ -z "$OUT" ]; then
  pass "complexity cap accepts boilerplate, including optional unwrapping"
else
  fail "complexity cap rejected a file that is genuinely trivial"
  echo "$OUT" | sed 's/^/       /'
fi

exit $FAILED
