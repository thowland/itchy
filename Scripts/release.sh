#!/usr/bin/env bash
# Producing a distributable build (NFR-4.2, specification §15).
#
# Developer ID signing with the hardened runtime, notarised, stapled,
# distributed directly as a DMG. Not the App Store: the sandbox would complicate
# the loopback server, the Keychain-held token and any future local process
# invocation, and buys nothing given that distribution is direct (CON-6).
#
# Every step states what it needs rather than failing obscurely, because the
# thing most likely to be missing is a credential rather than a line of code.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

APP_NAME="Itchy"
BUNDLE_ID="com.wdogsystems.itchy"
DD=".build/DerivedData"
EXPORT_DIR=".build/release"
# Where a person is expected to look, rather than inside a dot-directory.
OUT_DIR="build"
NOTARY_PROFILE="${ITCHY_NOTARY_PROFILE:-notarytool}"

pass() { printf '  \033[32mok\033[0m   %s\n' "$1"; }
warn() { printf '  \033[33m--\033[0m   %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; }

identity() {
  security find-identity -v -p codesigning 2>/dev/null \
    | grep "Developer ID Application" | head -1 \
    | sed -E 's/.*"(.*)"/\1/'
}

# The team identifier, taken from the Developer ID certificate's own name.
#
# Worth deriving rather than leaving to the reader. A machine with more than one
# Apple account has several parenthesised identifiers in `find-identity` output
# and only one of them is the team that owns the Developer ID — the instruction
# "use the one in parentheses" is ambiguous exactly when it matters.
team_id() {
  identity | sed -nE 's/.*\(([A-Z0-9]+)\)$/\1/p'
}

# Bounded, without depending on GNU coreutils. `timeout` is not on a clean macOS
# and must not be on the path this check needs. Same shape as Scripts/test.sh.
run_bounded() {
  local seconds="$1"; shift
  "$@" &
  local pid=$!
  local waited=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge "$seconds" ]; then
      kill -9 "$pid" 2>/dev/null
      return 124
    fi
    sleep 1
    waited=$((waited + 1))
  done
  wait "$pid"
}

# Whether the notary credentials are usable, and if not, which kind of not.
#
# `notarytool history` answers locally and instantly when there is no profile,
# and calls Apple when there is one. Those two failures need opposite advice:
# one means "create a profile", the other means "your profile is there and
# something else is wrong". Reporting the first for both is how somebody ends up
# overwriting working credentials to fix a network outage.
notary_status() {
  local output status
  output=$(run_bounded 45 xcrun notarytool history \
    --keychain-profile "$NOTARY_PROFILE" 2>&1)
  status=$?
  if [ $status -eq 0 ]; then
    echo "ok"
    return 0
  fi
  if [ $status -eq 124 ]; then
    echo "unreachable"
    return 1
  fi
  if printf '%s' "$output" | grep -q "No Keychain password item found"; then
    echo "absent"
    return 1
  fi
  printf 'refused\n%s\n' "$output"
  return 1
}

check() {
  echo "Release readiness"
  local ready=0

  local id
  id=$(identity)
  if [ -n "$id" ]; then
    pass "Developer ID certificate: $id"
  else
    fail "no Developer ID Application certificate in the keychain"
    warn "  needed by NFR-4.2. Create one at developer.apple.com under"
    warn "  Certificates, then download and double-click it."
    ready=1
  fi

  local notary team
  notary=$(notary_status)
  case "$(printf '%s' "$notary" | head -1)" in
    ok)
      pass "notarytool credential profile '$NOTARY_PROFILE'"
      ;;
    absent)
      fail "no notarytool credential profile named '$NOTARY_PROFILE'"
      team=$(team_id)
      warn "  xcrun notarytool store-credentials $NOTARY_PROFILE \\"
      warn "    --apple-id <your-apple-id> --team-id ${team:-<team>}"
      warn "  Leave --password off: notarytool prompts for the app-specific"
      warn "  password, so it does not land in your shell history."
      ready=1
      ;;
    unreachable)
      fail "the notary service did not answer within 45s"
      warn "  the profile may be fine — this check needs the network."
      ready=1
      ;;
    *)
      fail "the profile '$NOTARY_PROFILE' exists but was refused"
      printf '%s\n' "$notary" | tail -n +2 | head -3 | sed 's/^/       /'
      warn "  an app-specific password can be revoked at appleid.apple.com."
      ready=1
      ;;
  esac

  if [ -f "App/Itchy.entitlements" ]; then
    pass "entitlements present (no sandbox, hardened runtime)"
  else
    fail "App/Itchy.entitlements is missing"
    ready=1
  fi

  [ $ready -eq 0 ] && echo "" && echo "Ready to ship." \
    || { echo ""; echo "Not ready: the items above need a person, not a build."; }
  return $ready
}

# What the notary service checks that codesign does not.
#
# `codesign --verify` is happy with a build the notary service will refuse, and
# the refusal arrives minutes later on the far side of an upload. These are the
# two conditions that have actually bitten: a debug entitlement injected into a
# Release build by a setting whose default is wrong for distribution, and a
# signature with no secure timestamp.
notarisable() {
  local app="$1" ok=0 entitlements description

  # Captured, not piped. `grep -q` exits at the first match, the write end of
  # the pipe gets SIGPIPE, and under `pipefail` a *successful* match becomes a
  # non-zero pipeline — so the check reports the opposite of what it found. It
  # cost twenty minutes here, having been written the obvious way first.
  entitlements=$(codesign -d --entitlements - --xml "$app" 2>/dev/null)
  description=$(codesign -dv --verbose=4 "$app" 2>&1)

  case "$entitlements" in
    *com.apple.security.get-task-allow*)
      fail "the build carries com.apple.security.get-task-allow"
      warn "  the notary service refuses any binary with it — it is what lets a"
      warn "  debugger attach. Set CODE_SIGN_INJECT_BASE_ENTITLEMENTS to NO for"
      warn "  Release; Xcode injects it by default."
      ok=1
      ;;
  esac

  case "$description" in
    *"Timestamp="*) ;;
    *)
      fail "the signature has no secure timestamp"
      warn "  notarisation requires one. Sign with --timestamp."
      ok=1
      ;;
  esac

  case "$description" in
    *flags=*runtime*) ;;
    *)
      fail "the hardened runtime is not enabled"
      warn "  notarisation requires it (NFR-4.2)."
      ok=1
      ;;
  esac

  case "$description" in
    *"Authority=Developer ID Application"*) ;;
    *)
      fail "not signed by a Developer ID Application certificate"
      ok=1
      ;;
  esac

  return $ok
}

build() {
  local id
  id=$(identity)
  if [ -z "$id" ]; then
    fail "no Developer ID Application certificate; run 'make ship-check'"
    exit 1
  fi
  xcodegen generate --quiet || exit 1
  rm -rf "$EXPORT_DIR"
  mkdir -p "$EXPORT_DIR"
  set -o pipefail
  xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" \
    -configuration Release -destination "platform=macOS,arch=$(uname -m)" \
    -derivedDataPath "$DD" \
    CODE_SIGN_IDENTITY="$id" CODE_SIGN_STYLE=Manual \
    OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime" \
    build -quiet 2>&1 | "$(dirname "$0")/xcnoise.sh" || exit 1
  cp -R "$DD/Build/Products/Release/$APP_NAME.app" "$EXPORT_DIR/" || exit 1
  codesign --verify --deep --strict --verbose=2 "$EXPORT_DIR/$APP_NAME.app" || exit 1
  notarisable "$EXPORT_DIR/$APP_NAME.app" || exit 1
  pass "signed and verified at $EXPORT_DIR/$APP_NAME.app"
}

# Submits one file and waits. Shared by the application and the disk image,
# because both need it and for the same reason.
submit() {
  xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
}

# Whether a ticket is attached to something, which is what lets Gatekeeper
# approve it without asking Apple — on a machine that is offline, or after the
# submission has aged out of the service's cache.
stapled() {
  xcrun stapler validate "$1" >/dev/null 2>&1
}

notarise() {
  local app="$EXPORT_DIR/$APP_NAME.app"
  [ -d "$app" ] || { fail "no release build; run 'make release' first"; exit 1; }
  local zip="$EXPORT_DIR/$APP_NAME.zip"
  ditto -c -k --keepParent "$app" "$zip" || exit 1
  submit "$zip" || exit 1
  xcrun stapler staple "$app" || exit 1
  pass "notarised and stapled"
}

# Assembles the disk image contents: the application, somewhere to drag it, and
# something to read. Shared by `package` and `dmg`; they differ only in which
# build they start from and whether the result is signed.
stage_dmg() {
  local app="$1"
  local staging="$2"
  rm -rf "$staging"
  mkdir -p "$staging"
  cp -R "$app" "$staging/" || return 1
  # The conventional drag-to-install target.
  ln -s /Applications "$staging/Applications"
  cp README.md "$staging/README.md" || return 1
  # The README's images are relative paths, so they travel with it or its links
  # resolve to nothing.
  mkdir -p "$staging/docs"
  cp -R docs/images "$staging/docs/images" 2>/dev/null
  return 0
}

build_dmg() {
  local staging="$1"
  local output="$2"
  rm -f "$output"
  hdiutil create -volname "$APP_NAME" -srcfolder "$staging" -ov -format UDZO \
    "$output" >/dev/null
}

# A disk image from whatever build is to hand, signed only if an identity
# exists. For handing a build to someone who already trusts where it came from;
# `dmg` is the notarised article that opens on a machine that does not.
package() {
  local app="$OUT_DIR/$APP_NAME.app"
  if [ ! -d "$app" ]; then
    fail "no application at $app — run 'make app' first"
    exit 1
  fi

  local staging="$EXPORT_DIR/package"
  mkdir -p "$EXPORT_DIR"
  stage_dmg "$app" "$staging" || { fail "could not assemble the disk image"; exit 1; }

  local output="$OUT_DIR/$APP_NAME.dmg"
  build_dmg "$staging" "$output" || { fail "hdiutil failed"; exit 1; }
  rm -rf "$staging"

  local id
  id=$(identity)
  if [ -n "$id" ]; then
    codesign --sign "$id" "$output" >/dev/null 2>&1 \
      && pass "signed with $id" \
      || warn "could not sign the disk image; it is still usable"
  else
    warn "unsigned: no Developer ID on this machine, so Gatekeeper will warn"
    warn "  anyone who opens it. 'make ship-check' explains what is missing."
  fi

  pass "packaged $(cd "$(dirname "$output")" && pwd)/$(basename "$output")"
  echo "     contains: $APP_NAME.app, a link to Applications, README.md"
}

# The disk image people actually download, which has to clear Gatekeeper in its
# own right.
#
# A stapled application inside a merely-signed image is not enough. The image is
# what carries the quarantine attribute, and it is the image Gatekeeper assesses
# when somebody opens their download — so an unnotarised one is refused before
# anyone reaches the application inside, and the message macOS shows says the
# file is damaged rather than that it is unnotarised. Both have to be notarised
# and both have to be stapled.
dmg() {
  local app="$EXPORT_DIR/$APP_NAME.app"
  local image="$EXPORT_DIR/$APP_NAME.dmg"
  [ -d "$app" ] || { fail "no release build; run 'make release' first"; exit 1; }
  if ! stapled "$app"; then
    fail "the application has no notarisation ticket"
    warn "  run 'make notarise' first. Notarising the image alone would leave"
    warn "  the application unstapled once it is dragged out of it."
    exit 1
  fi

  local staging="$EXPORT_DIR/dmg"
  stage_dmg "$app" "$staging" || { fail "could not assemble the disk image"; exit 1; }
  build_dmg "$staging" "$image" || exit 1
  rm -rf "$staging"
  # --timestamp for the same reason the application needs one: the notary
  # service requires a secure timestamp on what it is asked to notarise.
  codesign --sign "$(identity)" --timestamp "$image" || exit 1
  submit "$image" || exit 1
  xcrun stapler staple "$image" || exit 1

  if spctl -a -t open --context context:primary-signature "$image" >/dev/null 2>&1; then
    pass "packaged, notarised and stapled $image"
    pass "Gatekeeper accepts it — it will open on a machine that has never seen it"
  else
    fail "the image was notarised but Gatekeeper still refuses it"
    spctl -a -vvv -t open --context context:primary-signature "$image" 2>&1 \
      | head -3 | sed 's/^/       /'
    exit 1
  fi
}

case "${1:-check}" in
  check) check ;;
  build) build ;;
  notarise) notarise ;;
  package) package ;;
  dmg) dmg ;;
  *) echo "usage: release.sh [check|build|notarise|package|dmg]"; exit 2 ;;
esac
