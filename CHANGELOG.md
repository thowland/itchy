# Changelog

What changed, by version. Versions follow `MAJOR.MINOR.PATCH`, biased toward
patches ([D-22](docs/decisions/D-22-versioning.md)). The build number shown in
About is the commit count.

## Unreleased

**Added**

- Itchy is now signed with a Developer ID and notarised by Apple, so it opens
  on a machine that has never seen it without a Gatekeeper override. Both the
  application and the disk image carry their own notarisation ticket.

- Transforms, on the pad: flatten styling, upper, lower and title case,
  pretty-print and minify JSON, encode and decode base64, encode and decode URL
  components, trim whitespace, and sort lines
  ([D-24](docs/decisions/D-24-transform-layer.md)). A transform acts on the
  selection where there is one, applies as a single named undo step, and is not
  offered for input it cannot handle.
- An agent server, off until you switch it on, in Settings under Agents
  ([D-25](docs/decisions/D-25-mcp-server.md)). It listens on 127.0.0.1 only, so
  nothing outside this machine can reach it, and every request needs the bearer
  token shown beside the switch. Regenerating that token stops the previous one
  working straight away.
- Pads are exposed to agents one at a time, in the pad's own settings, and none
  is by default. An exposed pad says "exposed" on itself, and the menubar says
  when the server is listening.
- Five tools and nothing else: list, read, append, write and create. A pad an
  agent creates is exposed to it; a pad you made is not until you say so.
- An agent's write to a pad you have open lands in the window and is one undo
  from reverted — and the Edit menu names it, so you can see what the undo will
  revert before you press it. A write to a pad that was closed cannot be undone,
  and the pad says so rather than offering a button that would undo something
  else.
- A banner on any pad written by something other than you, and a mark in the
  menubar for a pad written while it was closed.
- Reading a pad that contains an image now returns the text with `[image
  1240×820]` in its place, rather than a character that means nothing. The same
  placeholder appears in the pad's plain-text copy on disk.
- Help, from the menubar or from About: how to set up agents and backups, what
  the transforms do, how pads work, and where your files are
  ([D-26](docs/decisions/D-26-diagnostic-log-and-help.md)).
- An optional diagnostic log, in **Settings → General**, off by default. When
  on, Itchy records what it did — backups taken and skipped and why, agent
  requests and where each write went, transforms applied and declined — to
  /tmp/itchy.log. It records how much was written, never what: pad contents and
  the agent token cannot appear in it.
- Licensed under the GNU GPL, version 3.
- A user guide, and the README split into user, development and release
  documentation.

**Fixed**

- Flattening a styled pad through the interface did not remove underlines, and
  kept the old point size, because the applier merged attributes instead of
  replacing them.
- An intermittent failure in the store's observation tests, which waited for any
  event where it meant to wait for a particular one.
- `list_pads` reported the size of the pad's directory under a heading that said
  "characters", which for a five-character pad was several hundred.
- A first launch, with no pads yet, recorded a failed backup. There was simply
  nothing to back up, which is not the same thing.
- Itchy took a backup twice on every launch when the daily backup was switched
  off. The second never did anything, because nothing had changed since the
  first a moment earlier.

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
