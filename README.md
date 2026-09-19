# Itchy

A menubar scratchpad for macOS. A small fixed set of pads, each a floating
window you can summon over whatever you are working in, type or paste into, and
close without being asked to name or file anything. Content stays until you
remove it.

<p align="center">
  <img src="docs/images/pad-panel.png" width="420" alt="A pad panel holding a tracking number, a JSON fragment and a note">
</p>

> **Status: early, and not yet signed for distribution.** Version 0.1.x is in
> daily use by its author. There is no notarised release yet, so for now Itchy
> is built from source. The agent integration works over HTTP; the stdio shim,
> for agents that cannot speak HTTP, is waiting on the same signing certificate
> the release is.

## What it does

- **A handful of pads, one click away.** Nine by default, never more than twenty,
  listed under the cat in the menubar.
- **Pads float.** A pad opens over whatever you are doing, including fullscreen
  applications, and stays where you put it.
- **One hotkey.** ⌃⌥Space brings back the pad you used last, from anywhere.
  Press it again to put the pad away.
- **Styled text and pictures, or plain text.** Paste from a browser or a word
  processor and the formatting survives, screenshots included. Switch a pad to
  plain mode for code and JSON, where smart quotes are never welcome.
- **Nothing to save.** No titles, folders or save prompts. Close a pad and it is
  still there next time. Name a pad only if you want to.
- **Backups you control.** A copy is kept when something has changed, as many as
  you choose, and zero is one of the choices.
- **Your files, readable.** Pads are plain files on your Mac, kept out of
  Spotlight, and Itchy makes no network connections.
- **Pads an agent can read and write — if you say so.** Switch the agent server
  on in Settings, expose a pad, and a coding agent can read it, append to it and
  replace it over the Model Context Protocol. It listens on this machine only,
  every request needs a token, and nothing is exposed until you expose it. An
  agent's write into a pad you have open is one undo from reverted, and a pad
  something else wrote to says so.

## What it will not become

Itchy is for content that is passing through: a tracking number, a failing
request's JSON, a paragraph still being argued over. It is not a note-taking
application and will not grow into one. There is no document library, no
folders, no tags and no search across everything, because the whole collection
fits in a glance.

The idea the project exists for is that pads become a surface both you and a
coding agent can read and write, over the Model Context Protocol —
[the vision document](docs/itchy-vision.md) explains why. That surface is five
tools and nothing else, and the narrowness is the point.

## Installing

There is no signed download yet. Build it from source:

```bash
brew install swiftlint xcodegen
git clone https://github.com/thowland/itchy.git && cd itchy
make app
```

Then drag `build/Itchy.app` into `/Applications` and open it. Itchy has no Dock
icon and no main window; look for the cat in the menubar. It only offers to start
at login when it runs from `/Applications`.

The [user guide](docs/user-guide.md) covers everything from there.

## Building from source

| | |
|---|---|
| macOS | 26 or later |
| Xcode | 26 or later, which also provides `swift-format` |
| SwiftLint, XcodeGen | `brew install swiftlint xcodegen` |

```bash
make open        # generate the Xcode project and open it
make run         # build and launch
make test        # the test suite, without the UI tests
make gate        # lint, architecture checks, tests and coverage
make help        # everything else
```

[docs/development.md](docs/development.md) covers the rest: the test suites and
their permissions, signing for development, the repository layout, and
troubleshooting.

## Documentation

| | |
|---|---|
| [User guide](docs/user-guide.md) | Using Itchy |
| [Development](docs/development.md) | Building, testing, permissions, troubleshooting |
| [Releasing](docs/releasing.md) | Versions, certificates, notarisation, packaging |
| [Changelog](CHANGELOG.md) | What changed, by version |
| [Vision](docs/itchy-vision.md) | Why this exists, and what it must never become |
| [Architecture](docs/itchy-architecture.md) | Layers, storage, build order |
| [Requirements](docs/itchy-requirements.md) | Numbered, with acceptance criteria |
| [Specification](docs/itchy-specification.md) | How it is assembled |
| [Implementation plan](docs/itchy-implementation-plan.md) | Sprints and the exit gate |
| [Decisions](docs/decisions/) | Every design decision, with its reasoning |

## Contributing

Itchy is a personal tool first, and its main risk is growing into the
application it was built to avoid. Bug reports are welcome. Before proposing a
feature, read [CONTRIBUTING.md](CONTRIBUTING.md), which explains the one
question every addition has to answer.

Security issues: see [SECURITY.md](SECURITY.md).

## Licence

Copyright © 2026 Tim Howland.

Itchy is free software, released under the
[GNU General Public License, version 3](LICENSE).
