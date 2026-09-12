# D-13 — Pad content is an RTFD *bundle map*, not opaque `Data`

*Taken in Sprint 1.*

## Decision

`PadContent` holds `bundle: [String: Data]` — filenames within the RTFD bundle
mapped to their bytes — plus the derived `plainText`. The store writes that map
as a directory, atomically, and reads it back the same way.

## Why this needed deciding

Specification §5.1 described content as `rtfd: Data` while §6.1 and §6.3
described `content.rtfd` as a *directory* whose replacement needs directory-aware
atomic write. Both cannot be true, and the inconsistency only surfaces when
something actually has to write the bytes.

`NSAttributedString` offers both forms: `rtfd(from:)` returns flat packed data,
and `fileWrapper(from:)` returns a directory. Flat data is far simpler to store —
one file, trivial atomic replace, and `PadContent.rtfd: Data` as originally
written. It also fails `FR-5.3`, whose acceptance criterion is that content
written by Itchy opens in TextEdit with images intact: TextEdit expects `.rtfd`
to be a bundle, not a file with a bundle's extension. So the directory wins, and
the model has to represent one.

Given a directory, the remaining choice was `FileWrapper` or a map. `FileWrapper`
is Foundation, so D-2 permits it in the core, but it is a reference type that is
neither `Sendable` nor `Equatable` — which makes it hostile to an actor-isolated
store and to tests that want to compare one whole expected value against one
actual value. A `[String: Data]` map is both, is trivially inspectable in a
failure message, and is writable as a directory without AppKit.

## What this costs

The core can only synthesise trivial RTF, which is why `PadContent.plainText(_:)`
hand-rolls a minimal document with escaping. Anything styled is produced by the
platform layer's `ContentCodec` in Sprint 3, where `NSAttributedString` does the
work properly. The core's RTF writer exists for the degenerate case and for
tests, and should not grow.

Verified: a bundle written by `itchyctl` is read correctly by `textutil`, with
brace and backslash escaping intact. Images are Sprint 3 and not yet exercised.

## Consequence for the specification

§5.1's `PadContent` has been corrected to match. Nothing else changes: §6.3
already specified directory-aware atomic replacement, and that is now what the
code does.
