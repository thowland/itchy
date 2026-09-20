# D-22 — Semantic versions biased toward patches, and an About screen that shows them

*Taken during fit-and-finish, after R1.*

## The scheme

`MAJOR.MINOR.PATCH`, as specification §16 already said, with a stated bias:
**a change raises the patch unless it adds something a user would call a
feature**. Development moves quickly and most of what lands is fixes and
finish. Under a stricter reading of semver every week would be a minor release,
and the minor number would stop meaning anything.

The application stays below 1.0.0 while it is pre-release. The first bump is to
0.1.1, for the fit-and-finish branch that introduced this record. 1.0.0 is for
the first signed and notarised release (`NFR-4.2`), which is a decision about
the product and not about the number.

*Reached September 2026. 1.0.0 is the release published to GitHub, and the
condition above is what decided it rather than the amount of work in the
section. 0.1.1 was signed and notarised, and opened on a Mac that had never seen
it, but it was never released: it existed on two machines belonging to the same
person, and a build nobody can obtain is not a release. The first disk image
attached to a tag is where `NFR-4.2` stops being a property of a build and
becomes a property of something somebody has.*

The build number is the commit count, as §16 specifies.

## Where the numbers live

- **`Config/Version.xcconfig`** holds `MARKETING_VERSION`, and both build
  configurations include it. It is not in `project.yml`, because editing
  `project.yml` regenerates the Xcode project, and a regenerated project costs
  a full rebuild. A project-level value in `project.yml` would also silently
  override the xcconfig, the same trap `CODE_SIGN_IDENTITY` already documents.
- **`make bump`** raises the patch. `make bump PART=minor` and `PART=major` do
  what they say, and `make version` prints the current version.
- **The build number is stamped** into the built `Info.plist` by a script phase
  running `git rev-list --count HEAD`. Written into a checked-in file, it would
  change on every commit. The phase declares the processed `Info.plist` as its
  input, because without that the build system ran it before the plist was
  written and the stamp was overwritten. Code signing runs after every script
  phase, so the signature covers the stamped value. The xcconfig carries `0` as
  a placeholder, so a missing stamp is visible rather than looking like build 1,
  and a test fails on it.

## The About screen

"About Itchy" in the menubar menu opens the first-run window (convention names
the item without an ellipsis, since it opens no further choices). The window now
shows "Version 0.1.1 (412)", selectable so it can be pasted into a report. Two
things differ when it is opened as About:

- The button says Close rather than "Start Scratching".
- Closing it records nothing. It does not mark the first run as seen, so opening
  About before ever dismissing the first run cannot suppress it.

Asking for About while the first-run window is already up brings that window
forward rather than replacing it, since a replacement would lose the record
that the first run had been seen. These decisions are `FirstRunPolicy`'s.
