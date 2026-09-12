#!/usr/bin/env bash
# Architecture lint: four checks, each encoding a constraint that would otherwise
# decay silently (implementation plan §3.4).
#
#   1. ItchyCore links no UI framework            D-2, NFR-4.3
#   2. Only the store touches disk                CON-4
#   3. One call site for Transform.apply          specification §12
#   4. Coverage exclusions pass the complexity cap D-11, specification §15.3
#
# The first three are greps. Their crudeness is acceptable: each is a rule with
# an obvious textual signature, and the alternative is noticing the violation a
# year later.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

FAILED=0
pass() { printf '  \033[32mok\033[0m   %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAILED=1; }

echo "Architecture lint"

# --- 1. ItchyCore links no UI framework (D-2, NFR-4.3) -----------------------
HITS=$(grep -rn --include='*.swift' -E '^\s*import\s+(AppKit|SwiftUI|UIKit|Cocoa)\b' \
  Packages/ItchyCore/Sources 2>/dev/null || true)
if [ -n "$HITS" ]; then
  fail "ItchyCore imports a UI framework (D-2)"
  echo "$HITS" | sed 's/^/       /'
else
  pass "ItchyCore imports no UI framework"
fi

# --- 2. Only the store touches disk (CON-4) ----------------------------------
# FileManager and file URLs are permitted in ItchyCore/Store and nowhere else.
HITS=$(grep -rn --include='*.swift' -E '\bFileManager\b|URL\(fileURLWithPath:' \
  Packages App Shim Harness 2>/dev/null \
  | grep -v '/Store/' \
  | grep -v '/\.build/' || true)
if [ -n "$HITS" ]; then
  fail "disk access outside ItchyCore/Store (CON-4)"
  echo "$HITS" | sed 's/^/       /'
else
  pass "disk access confined to the store"
fi

# --- 3. One call site for Transform.apply (specification §12) ----------------
# The single call site is TransformRunner, so that the menu path and the MCP path
# are subject to the same routing policy rather than two that are meant to agree.
COUNT=$(grep -rn --include='*.swift' -E '\.apply\(to:' Packages App 2>/dev/null \
  | grep -v '/\.build/' \
  | grep -vc 'protocol Transform' || true)
COUNT=${COUNT:-0}
if [ "$COUNT" -gt 1 ]; then
  fail "Transform.apply has $COUNT call sites, expected at most 1 (specification §12)"
  grep -rn --include='*.swift' -E '\.apply\(to:' Packages App 2>/dev/null | grep -v '/\.build/' | sed 's/^/       /'
else
  pass "Transform.apply has $COUNT call site(s)"
fi

# --- 4. Coverage exclusions pass the complexity cap (D-11, §15.3) ------------
# Exclusion from the coverage denominator is earned by triviality. Every path on
# the exclusion list is linted under a configuration that permits no branching.
EXCLUDED_FILES=()
SECTION=""
# The exclusion patterns are written against absolute-style paths, because that
# is what lcov reports and what Scripts/coverage.sh matches. Candidates are
# therefore tested with a leading slash so that both tools apply the same
# patterns to the same files; without this the two silently diverge, which is
# the exact failure this check exists to prevent.
ALL_SWIFT=$(find App Packages Shim Harness -name '*.swift' 2>/dev/null | grep -v '/\.build/' || true)
while IFS= read -r line; do
  case "$line" in
    '[capped]')     SECTION="capped"; continue ;;
    '[not-source]') SECTION="not-source"; continue ;;
    ''|'#'*)        continue ;;
  esac
  [ "$SECTION" = "capped" ] || continue
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    if printf '/%s\n' "$rel" | grep -qE "$line"; then
      EXCLUDED_FILES+=("$rel")
    fi
  done <<< "$ALL_SWIFT"
done < Scripts/coverage-exclusions.txt

if [ ${#EXCLUDED_FILES[@]} -eq 0 ]; then
  pass "complexity cap: no capped source files present yet"
elif ! command -v swiftlint >/dev/null 2>&1; then
  fail "swiftlint not installed; cannot verify the complexity cap"
else
  OUT=$(swiftlint lint --quiet --strict --config Scripts/swiftlint-excluded.yml \
          "${EXCLUDED_FILES[@]}" 2>&1)
  if [ -n "$OUT" ]; then
    fail "coverage-excluded files contain branching (D-11, §15.3)"
    echo "$OUT" | sed 's/^/       /'
  else
    pass "complexity cap holds over ${#EXCLUDED_FILES[@]} capped file(s): ${EXCLUDED_FILES[*]}"
  fi
fi

exit $FAILED
