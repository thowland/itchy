# Changelog

What changed, by version. Versions follow `MAJOR.MINOR.PATCH`, biased toward
patches ([D-22](docs/decisions/D-22-versioning.md)). The build number shown in
About is the commit count.

## Unreleased

**Added**

- Transforms, on the pad: flatten styling, upper, lower and title case,
  pretty-print and minify JSON, encode and decode base64, encode and decode URL
  components, trim whitespace, and sort lines
  ([D-24](docs/decisions/D-24-transform-layer.md)). A transform acts on the
  selection where there is one, applies as a single named undo step, and is not
  offered for input it cannot handle.
- Licensed under the GNU GPL, version 3.
- A user guide, and the README split into user, development and release
  documentation.

**Fixed**

- Flattening a styled pad through the interface did not remove underlines, and
  kept the old point size, because the applier merged attributes instead of
  replacing them.
- An intermittent failure in the store's observation tests, which waited for any
  event where it meant to wait for a particular one.

## 0.1.1

Fit and finish after the first release was feature-complete.

**Added**

- Editor font and size in Settings, applied to text already in pads
  ([D-19](docs/decisions/D-19-editor-font.md)).
- Bold, italic and underline in styled pads, as buttons and as ⌘B, ⌘I and ⌘U
  ([D-20](docs/decisions/D-20-formatting-controls.md)).
- Pad Settings, for one pad's name, mode and pinning
  ([D-21](docs/decisions/D-21-pad-settings.md)).
- About Itchy, showing the version and build
  ([D-22](docs/decisions/D-22-versioning.md)).

**Fixed**

- The last edit before quitting could be lost, and the backup taken at quit came
  before the final save ([D-18](docs/decisions/D-18-archives.md)).
- Backups were taken, or skipped, based on file times, so opening or moving a pad
  counted as a change and real edits could be missed.
- An open pad's title, status line and menu kept a pad's old name and mode until
  it was reopened.

## 0.1.0

The first release to be feature-complete: the menubar, pads as floating panels,
styled text with images, plain mode, the global hotkey, start at login, the
first-run window and backups.
