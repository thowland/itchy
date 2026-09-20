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
2. Find the team identifier. `make ship-check` prints the right one in the
   command it suggests, which is the reliable way: it takes it from the
   Developer ID certificate itself. Read it by hand only if you must, and read
   it from the parentheses on the **Developer ID Application** line of
   `security find-identity -v -p codesigning` — a machine with more than one
   Apple account shows several parenthesised identifiers there and only that one
   is the team that owns the certificate.
3. Store the credentials in the keychain, once:

```bash
xcrun notarytool store-credentials notarytool \
  --apple-id "you@example.com" \
  --team-id "ABCDE12345"
```

Leave `--password` off. notarytool then asks for the app-specific password at a
secure prompt, so it does not end up in `~/.zsh_history`. Passing it as an
argument works and is what most examples online show, but a credential in shell
history is a credential you have to remember to remove.

`store-credentials` validates against Apple before saving, so a wrong password
or team identifier fails here rather than at the first notarisation.

The profile name `notarytool` is what the release script expects; override it
with `ITCHY_NOTARY_PROFILE`.

`make ship-check` tells the two failures apart: a profile that is missing, and a
profile that exists but was refused — because the advice differs, and
"create a profile" is the wrong thing to do about an expired password or a
network outage.

### 3. Releasing

```bash
make ship-check   # confirm both of the above
make release      # Developer ID signed, hardened runtime, verified
make notarise     # submit the application, wait, staple it
make dmg          # package, notarise and staple the disk image
```

Both steps notarise, and that is not redundant. The disk image is what carries
the quarantine attribute when somebody downloads it, so the image is what
Gatekeeper assesses when they open it — a merely-signed image holding a
perfectly notarised application is refused before anyone reaches the
application, and macOS says the file is damaged rather than that it is
unnotarised. The application is stapled too, so that it still passes once it has
been dragged out of the image and the image is gone.

`make dmg` refuses to run before `make notarise`, because packaging an
unstapled application would produce an image that passes on the way in and
an application that fails on the way out. It finishes by asking Gatekeeper
whether it would accept the result, and says so.

The finished image is left at `build/Itchy.dmg`, which is where `make package`
writes its unsigned one too. That is deliberate: there should be one
`Itchy.dmg` and it should be the most recently built one, rather than a
shippable image hidden under `.build/` next to an unshippable one of the same
name and nearly the same size.

The hardened runtime is required for notarisation and applies to Release builds
only. It blocks XCTest bundle injection, so Debug builds do not use it.

`make release` checks the signed build for the three things the notary service
refuses and `codesign --verify` does not notice, before it says it succeeded:

- **`com.apple.security.get-task-allow`**, the entitlement that lets a debugger
  attach. Xcode injects it unless `CODE_SIGN_INJECT_BASE_ENTITLEMENTS` is `NO`,
  and its default is `YES` — so a Release build signs and verifies perfectly on
  the machine that made it and is refused minutes after the upload. The setting
  is `NO` for Release in `project.yml`, and Debug keeps it because XCTest
  injection needs it.
- **A secure timestamp**, which `--timestamp` supplies.
- **The hardened runtime**, and a Developer ID Application authority.

Each is cheap to check here and expensive to discover at the far end of a
submission.

Verify the result on a machine that has never seen the build: it should open
from Finder without a Gatekeeper override. That check is on the manual list
because it cannot be made from the machine that produced the build.

## Publishing the repository

The repository is <https://github.com/thowland/itchy>. It does not exist on
GitHub yet. When it is created:

1. Push, and make the repository public.
2. Enable private vulnerability reporting, which `SECURITY.md` depends on. GitHub
   offers it only on public repositories, so it cannot be done earlier. Either
   **Settings → Code security → Private vulnerability reporting → Enable**, or:

   ```bash
   gh api -X PUT repos/thowland/itchy/private-vulnerability-reporting
   ```

3. Confirm that <https://github.com/thowland/itchy/security/advisories/new>
   opens the reporting form when signed in as someone other than the owner.
4. Check that the CI workflow's `gate` job passes on GitHub's runner, and whether
   the `ui` job finds Automation Mode already configured (see
   [development](development.md), *Permission prompts*).

## Publishing a release

`make publish` uploads the disk image to GitHub Releases and tags the commit it
was built from. It is the last step of the chain rather than part of it: the
image has to exist, be notarised and be stapled first.

```bash
make bump                    # D-22; PART=minor or PART=major
# rename '## Unreleased' in CHANGELOG.md to the new version, and commit
make release notarise dmg
make publish                 # drafts the release
make publish PUBLISH=1       # or publishes it outright
```

It creates a **draft** unless `PUBLISH=1` is set. A draft has a page you can
read, with the notes rendered and the asset attached, and nothing is downloadable
until you press publish. Since a published release is the first thing anybody
sees of a version and the tag is awkward to take back once people have fetched
it, reviewing the page is worth the extra step; `gh release edit v0.1.2
--draft=false` publishes it without going to the browser.

The release notes are the version's own section of `CHANGELOG.md`, so they are
written once rather than typed again into a text box where they can quietly
disagree with the file. Appended to them are the system requirement, a sentence
about the image being notarised, and the asset's `sha256`.

### What it refuses to do

Each of these is a mistake that produces a release which looks correct and is
not, which is why they are checked here rather than noticed later:

- **An unreleased section left in the changelog.** The common shape of this is
  that `Config/Version.xcconfig` still names the version that went out last and
  the work since then is sitting under `## Unreleased`. Both the version check
  and the tag check pass, because the numbers agree with each other and simply
  describe the wrong build.
- **A version inside the image that is not the version being released.** Read by
  mounting the image and asking its `Info.plist`, rather than by trusting that
  `make dmg` ran after `make bump`.
- **An image that is not stapled, or that Gatekeeper refuses.** Re-checked here
  even though `make dmg` checks it, because the image on disk may be from an
  earlier run, and because this failure lands on the downloader's machine rather
  than on this one.
- **A dirty working tree, or a commit that is not on the remote.** A release
  names a commit; the tag would otherwise point at something nobody can fetch.
- **A tag that already exists on the remote.**

The asset is uploaded as `Itchy-<version>.dmg` rather than `Itchy.dmg`, so that
two of them in a Downloads folder can still be told apart.

## Packaging without a certificate

`make package` builds a disk image from the current build, containing the
application, a link to `/Applications` to drag it onto, and the README. It signs
the image if a Developer ID is present and says plainly when there is none.

That is enough to hand a build to someone who already trusts where it came from,
and no more. Without notarisation, Gatekeeper refuses it on a machine that has
never seen it, and tells the person opening it that the application is damaged
rather than that it is unsigned. `make dmg` produces the version that opens
anywhere — notarised and stapled, both the image and the application inside.
