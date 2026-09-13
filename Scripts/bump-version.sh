#!/usr/bin/env bash
# Raise the version in Config/Version.xcconfig (D-22).
#
#   make bump              0.1.1 -> 0.1.2   the default, and the usual answer
#   make bump PART=minor   0.1.2 -> 0.2.0
#   make bump PART=major   0.2.0 -> 1.0.0

set -euo pipefail
cd "$(dirname "$0")/.." || exit 1

FILE=Config/Version.xcconfig
PART="${1:-patch}"

CURRENT=$(sed -n 's/^MARKETING_VERSION = \([0-9]*\.[0-9]*\.[0-9]*\)$/\1/p' "$FILE")
if [ -z "$CURRENT" ]; then
  echo "bump: no MAJOR.MINOR.PATCH MARKETING_VERSION in $FILE"
  exit 1
fi

IFS=. read -r MAJOR MINOR PATCH <<< "$CURRENT"
case "$PART" in
  patch) PATCH=$((PATCH + 1)) ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  *) echo "bump: PART must be patch, minor or major, not '$PART'"; exit 1 ;;
esac

NEXT="$MAJOR.$MINOR.$PATCH"
sed -i '' "s/^MARKETING_VERSION = .*/MARKETING_VERSION = $NEXT/" "$FILE"
echo "version: $CURRENT -> $NEXT"
