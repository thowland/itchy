#!/usr/bin/env bash
# Points Debug builds at a signing identity from this machine's keychain.
#
# Without one, every rebuild produces a new code hash, TCC treats each build as
# a different application, and the automation prompt comes back every time —
# which presents as UI tests hanging rather than as a permission problem.
#
# Writes Config/Signing.local.xcconfig, which is not committed. Safe to re-run.
#
#   ./Scripts/sign-setup.sh                 pick automatically
#   ./Scripts/sign-setup.sh --list          show what is available
#   ./Scripts/sign-setup.sh ABCDE12345      pick by team, name fragment or hash

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

TARGET="Config/Signing.local.xcconfig"

# `security find-identity -v` already lists only identities that are valid and
# have a private key. An earlier version of this script filtered those again by
# reading the certificate's expiry — and `find-certificate -c` returns only the
# FIRST certificate with a given common name, so an identity renewed annually
# was judged by its oldest, long-expired certificate and silently discarded.
# Trust the tool that already knows.
identities() {
  security find-identity -v -p codesigning 2>/dev/null \
    | sed -nE 's/^[[:space:]]*[0-9]+\)[[:space:]]+([0-9A-F]+)[[:space:]]+"(.*)"$/\1\t\2/p' \
    | sort -u -t$'\t' -k1,1
}

# The latest expiry among every certificate sharing this name, which is the one
# that actually governs.
latest_expiry() {
  security find-certificate -a -c "$1" -p 2>/dev/null | python3 -c '
import sys, subprocess, tempfile, os, datetime
blocks, cur = [], []
for line in sys.stdin:
    cur.append(line)
    if "END CERTIFICATE" in line:
        blocks.append("".join(cur)); cur = []
best = None
for block in blocks:
    with tempfile.NamedTemporaryFile("w", suffix=".pem", delete=False) as handle:
        handle.write(block); path = handle.name
    out = subprocess.run(["openssl", "x509", "-in", path, "-noout", "-enddate"],
                         capture_output=True, text=True).stdout.strip()
    os.unlink(path)
    if "=" not in out:
        continue
    try:
        when = datetime.datetime.strptime(out.split("=", 1)[1], "%b %d %H:%M:%S %Y %Z")
    except ValueError:
        continue
    if best is None or when > best:
        best = when
print(best.strftime("%d %B %Y") if best else "unknown")
'
}

team_of() {
  security find-certificate -c "$1" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null \
    | tr ',' '\n' | sed -nE 's/.*OU=([A-Z0-9]+).*/\1/p' | head -1
}

if [ "${1:-}" = "--list" ]; then
  echo "Signing identities on this machine:"
  while IFS=$'\t' read -r hash name; do
    [ -z "$name" ] && continue
    printf '  %s\n     team %s, valid to %s\n     %s\n' \
      "$name" "$(team_of "$name")" "$(latest_expiry "$name")" "$hash"
  done < <(identities)
  exit 0
fi

WANTED="${1:-${ITCHY_SIGN_IDENTITY:-}}"
CHOSEN_HASH=""
CHOSEN_NAME=""

if [ -n "$WANTED" ]; then
  while IFS=$'\t' read -r hash name; do
    case "$hash$name" in
      *"$WANTED"*) CHOSEN_HASH="$hash"; CHOSEN_NAME="$name"; break ;;
    esac
  done < <(identities)
  if [ -z "$CHOSEN_HASH" ]; then
    echo "No signing identity matches '$WANTED'."
    echo "Run './Scripts/sign-setup.sh --list' to see what is available."
    exit 1
  fi
else
  # Developer ID first: it is the only kind that can sign for distribution.
  while IFS=$'\t' read -r hash name; do
    case "$name" in
      *"Developer ID Application"*) CHOSEN_HASH="$hash"; CHOSEN_NAME="$name"; break ;;
    esac
  done < <(identities)
  if [ -z "$CHOSEN_HASH" ]; then
    while IFS=$'\t' read -r hash name; do
      case "$name" in
        *"Apple Development"*) CHOSEN_HASH="$hash"; CHOSEN_NAME="$name"; break ;;
      esac
    done < <(identities)
  fi
fi

if [ -z "$CHOSEN_HASH" ]; then
  echo "No signing identity found."
  echo "Builds stay ad-hoc signed, which works — but macOS will ask for"
  echo "automation permission again after every rebuild, and UI tests will"
  echo "hang waiting for an answer. See docs/development.md, 'Permission prompts'."
  exit 1
fi

TEAM=$(team_of "$CHOSEN_NAME")
EXPIRY=$(latest_expiry "$CHOSEN_NAME")

# The hash rather than the name: several certificates can share a common name —
# this machine has seven for one of them — and codesign given an ambiguous name
# is free to pick any of them.
cat > "$TARGET" <<EOF
// Written by Scripts/sign-setup.sh. Not committed — it names an identity that
// exists only in this machine's keychain.
//
// $CHOSEN_NAME
// team $TEAM, valid to $EXPIRY
//
// Identified by certificate hash rather than by name: several certificates can
// share one common name, and codesign given an ambiguous name may pick any.
ITCHY_SIGN_IDENTITY = $CHOSEN_HASH
ITCHY_DEVELOPMENT_TEAM = $TEAM
EOF

echo "Debug builds will be signed as:"
echo "  $CHOSEN_NAME"
echo "  team $TEAM, valid to $EXPIRY"
echo "  certificate $CHOSEN_HASH"
echo ""
echo "Wrote $TARGET. Run 'make regenerate' if the project is already generated."
