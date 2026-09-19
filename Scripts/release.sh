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

  if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    pass "notarytool credential profile '$NOTARY_PROFILE'"
  else
    fail "no notarytool credential profile named '$NOTARY_PROFILE'"
    warn "  xcrun notarytool store-credentials $NOTARY_PROFILE \\"
    warn "    --apple-id <id> --team-id <team> --password <app-specific-password>"
    ready=1
  fi

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
    build 2>&1 | "$(dirname "$0")/xcnoise.sh" || exit 1
  cp -R "$DD/Build/Products/Release/$APP_NAME.app" "$EXPORT_DIR/" || exit 1
  codesign --verify --deep --strict --verbose=2 "$EXPORT_DIR/$APP_NAME.app" || exit 1
  pass "signed and verified at $EXPORT_DIR/$APP_NAME.app"
}

notarise() {
  local app="$EXPORT_DIR/$APP_NAME.app"
  [ -d "$app" ] || { fail "no release build; run 'make release' first"; exit 1; }
  local zip="$EXPORT_DIR/$APP_NAME.zip"
  ditto -c -k --keepParent "$app" "$zip" || exit 1
  xcrun notarytool submit "$zip" --keychain-profile "$NOTARY_PROFILE" --wait || exit 1
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

dmg() {
  local app="$EXPORT_DIR/$APP_NAME.app"
  [ -d "$app" ] || { fail "no release build; run 'make release' first"; exit 1; }
  local staging="$EXPORT_DIR/dmg"
  stage_dmg "$app" "$staging" || { fail "could not assemble the disk image"; exit 1; }
  build_dmg "$staging" "$EXPORT_DIR/$APP_NAME.dmg" || exit 1
  rm -rf "$staging"
  codesign --sign "$(identity)" "$EXPORT_DIR/$APP_NAME.dmg" || exit 1
  pass "packaged $EXPORT_DIR/$APP_NAME.dmg"
}

case "${1:-check}" in
  check) check ;;
  build) build ;;
  notarise) notarise ;;
  package) package ;;
  dmg) dmg ;;
  *) echo "usage: release.sh [check|build|notarise|package|dmg]"; exit 2 ;;
esac
