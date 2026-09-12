#!/usr/bin/env bash
# Points Debug builds at a signing identity from this machine's keychain.
#
# Without one, every rebuild produces a new code hash, TCC treats each build as
# a different application, and the automation prompt comes back every time —
# which presents as UI tests hanging rather than as a permission problem.
#
# Writes Config/Signing.local.xcconfig, which is not committed. Safe to re-run.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

TARGET="Config/Signing.local.xcconfig"

# Only identities that have not expired. `security` lists expired ones too, and
# signing with one fails in a way that reads as a project problem.
valid_identities() {
  security find-identity -v -p codesigning 2>/dev/null \
    | grep -oE '"[^"]+"' | tr -d '"' | while read -r name; do
      local_end=$(security find-certificate -c "$name" -p 2>/dev/null \
        | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
      [ -z "$local_end" ] && continue
      end_epoch=$(date -j -f "%b %d %T %Y %Z" "$local_end" "+%s" 2>/dev/null)
      [ -z "$end_epoch" ] && continue
      [ "$end_epoch" -gt "$(date +%s)" ] && echo "$name|$end_epoch"
    done
}

CHOSEN="${ITCHY_SIGN_IDENTITY:-}"
if [ -z "$CHOSEN" ]; then
  # Prefer Developer ID, then Apple Development; both give a stable requirement.
  CHOSEN=$(valid_identities | grep "Developer ID Application" | head -1 | cut -d'|' -f1)
  [ -z "$CHOSEN" ] && CHOSEN=$(valid_identities | grep "Apple Development" | head -1 | cut -d'|' -f1)
fi

if [ -z "$CHOSEN" ]; then
  echo "No unexpired signing identity found."
  echo "Builds stay ad-hoc signed, which works — but macOS will ask for"
  echo "automation permission again after every rebuild, and UI tests will"
  echo "hang waiting for an answer. See README, 'Repeated permission prompts'."
  exit 1
fi

# The team identifier is the certificate's OU, not the parenthetical in its
# common name — those differ, and using the wrong one produces a build that
# signs but cannot be provisioned.
TEAM=$(security find-certificate -c "$CHOSEN" -p 2>/dev/null \
  | openssl x509 -noout -subject 2>/dev/null \
  | tr ',' '\n' | sed -nE 's/.*OU=([A-Z0-9]+).*/\1/p' | head -1)
EXPIRY=$(security find-certificate -c "$CHOSEN" -p 2>/dev/null \
  | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)

cat > "$TARGET" <<EOF
// Written by Scripts/sign-setup.sh. Not committed — it names an identity that
// exists only in this machine's keychain.
ITCHY_SIGN_IDENTITY = $CHOSEN
ITCHY_DEVELOPMENT_TEAM = $TEAM
EOF

echo "Debug builds will be signed as:"
echo "  $CHOSEN"
echo "  team $TEAM, expires $EXPIRY"
echo ""
echo "Wrote $TARGET. Run 'make regenerate' if the project is already generated."
