# Releasing

Versions, signing, notarisation and packaging. For day-to-day building and
testing, see [development](development.md).

## Versions

`MAJOR.MINOR.PATCH`, biased toward patches: a change raises the patch unless it
adds something a user would call a feature. Itchy stays below 1.0.0 until its
first signed and notarised release. See [D-22](decisions/D-22-versioning.md).

```bash
make version            # print the current version
make bump               # 0.1.1 -> 0.1.2
make bump PART=minor    # 0.1.2 -> 0.2.0
make bump PART=major    # 0.2.0 -> 1.0.0
```

The version lives in `Config/Version.xcconfig`. The build number is the commit
count, stamped into the built application, and the About screen shows both.
Record what changed in [CHANGELOG.md](../CHANGELOG.md).

## Distribution

Itchy is distributed directly, signed with a Developer ID and notarised, not
through the App Store. The sandbox would complicate the loopback MCP server, the
Keychain-held token and any future local process invocation, and buys nothing
when distribution is direct.

Check what this machine can do:

```bash
make ship-check
```

It reports each requirement and what to do about it. The first two steps below
need a person; neither can be done from a build script.

### 1. A Developer ID Application certificate

Requires membership of the Apple Developer Program. A free account issues
*Apple Development* certificates, which cannot sign for direct distribution. If
`make ship-check` lists only those, this is the missing step.

Through Xcode:

1. **Xcode → Settings → Accounts**, and add the Apple ID if it is not there.
2. Select the team, then **Manage Certificates…**
3. **+** → **Developer ID Application**.
4. Confirm with `security find-identity -v -p codesigning`. The line should read
   `Developer ID Application: <name> (<team id>)`.

Through the portal instead, if the certificate is needed on a machine other than
the one generating the request: create a Certificate Signing Request in
**Keychain Access → Certificate Assistant → Request a Certificate From a
Certificate Authority**, upload it at **developer.apple.com → Certificates,
Identifiers & Profiles → Certificates → + → Developer ID Application**, then
download and double-click the result.

Keep the private key. A Developer ID certificate cannot be re-downloaded with
its key, and losing it means revoking and reissuing.

### 2. A notarytool credential profile

Notarisation authenticates with an app-specific password rather than an Apple ID
password.

1. At **appleid.apple.com → Sign-In and Security → App-Specific Passwords**,
   generate one and copy it.
2. Find the team identifier at **developer.apple.com → Membership details**, or
   in the parentheses of the `security find-identity` output above.
3. Store the credentials in the keychain, once:

```bash
xcrun notarytool store-credentials notarytool \
  --apple-id "you@example.com" \
  --team-id "ABCDE12345" \
  --password "abcd-efgh-ijkl-mnop"
```

The profile name `notarytool` is what the release script expects; override it
with `ITCHY_NOTARY_PROFILE`.

### 3. Releasing

```bash
make ship-check   # confirm both of the above
make release      # Developer ID signed, hardened runtime, verified
make notarise     # submit, wait, staple
make dmg          # package a signed disk image
```

The hardened runtime is required for notarisation and applies to Release builds
only. It blocks XCTest bundle injection, so Debug builds do not use it.

Verify the result on a machine that has never seen the build: it should open
from Finder without a Gatekeeper override. That check is on the manual list
because it cannot be made from the machine that produced the build.

## Packaging without a certificate

`make package` builds a disk image from the current build, containing the
application, a link to `/Applications` to drag it onto, and the README. It signs
the image if a Developer ID is present and says plainly when there is none.

That is enough to hand a build to someone who already trusts where it came from,
and no more. Without notarisation, Gatekeeper refuses it on a machine that has
never seen it, and tells the person opening it that the application is damaged
rather than that it is unsigned. `make dmg` produces the version that opens
anywhere.
