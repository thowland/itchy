# Itchy

A menubar scratchpad for macOS: a small fixed set of pads, each a floating
window you can summon over whatever you are working in, type or paste into, and
close without being asked to name or file anything.

What makes it worth building rather than another notes application is what the
pads are connected to. Text in a pad can be reshaped in place by a transform —
pretty-print the JSON, decode the base64 field, sort the lines — or handed to a
language model to tidy or summarise, and the same pad can be opened up to a
coding agent that reads and writes it over the Model Context Protocol. The pad
is the shared surface: you work in it, and so does whatever else you have
running.

<p align="center">
  <img src="docs/images/pad-panel.png" width="420" alt="A pad panel holding a tracking number, a JSON fragment and a note">
</p>

> **Status: version 0.1.x, in daily use by its author.** Builds are signed with
> a Developer ID and notarised, so one opens on a Mac that has never seen it,
> but there is no published download yet and you build it from source. Runs on
> macOS 15 or later.

## A session

A request fails. You paste the response body into a pad, where it arrives as one
unreadable line, and pretty-print it from the wand menu. The interesting part is
a base64 field, so you select that and decode it in place. You add two lines of
your own underneath about what you think is going on.

Then you expose the pad and tell Claude Code to look at it. It reads the pad,
works out that the token expired four hours ago, and appends what it found below
your notes — one undo away if you disagree. Nothing was copied between windows,
and there is no third place where the conversation lives.

Everything below is detail about how each of those parts behaves.

## The pad

Nine pads by default and never more than twenty, listed under the cat in the
menubar. A pad opens over whatever you are doing, including a fullscreen
application, and stays where you put it without pulling focus or rearranging
anything behind it. ⌃⌥Space brings back the one you used last from inside any
application, and pressing it again puts it away.

Styled pads keep formatting and images, so a paste from a browser arrives intact
with its screenshots. Plain pads hold text and nothing else, which is what you
want for code and JSON where smart quotes are never welcome.

There is nothing to save, no title to invent and no folder to choose. Close a
pad and it is still there next time. Pads are ordinary files in your Library,
readable with any editor and kept out of Spotlight, and Itchy makes no network
connection of its own until you configure something that needs one.

## Transforms

Twelve of them, from the wand button on the pad: flatten styling, upper and
lower and title case, pretty-print and minify JSON, encode and decode base64,
encode and decode URL components, trim whitespace, sort lines. Each acts on the
selection if there is one and the whole pad if there is not, and each is a single
undo step that the Edit menu names.

A transform is offered only when it would work on the text in front of you, so
Decode Base64 is greyed out on text that is not base64 and says why when you
hover it. The alternative is a menu that offers everything and then fails, which
teaches you to distrust the menu.

## Models

Three more transforms in the same menu, once you have configured a model: tidy
the prose, summarise it, or turn it into bullet points. They replace text with
text and undo in one step like everything else. There is no chat panel and no
conversation view, because a scratchpad that answers questions grows a reply
field, then a history, and ends up as a chat window with a save button.

Itchy looks for a model on your Mac first — Ollama, or anything speaking its
API — under every setting and on every pad, because a model running locally
sends nothing anywhere. If the local one cannot be reached, Itchy says so rather
than sending your text to a remote service instead, and that holds even on a pad
you have set to allow remote work. Each pad carries its own answer to whether
its text may go remote at all: local only, allowed, or ask me each time, which
asks before anything leaves and names where it is going.

## Agents

Switch the agent server on, expose a pad, and a coding agent can list, read,
append to, replace and create pads over the Model Context Protocol. It listens
on `127.0.0.1` and nothing else, every request carries a token you can
regenerate, and no pad is reachable until you expose it individually.

Five tools and no sixth. An agent cannot run your transforms, reach your models,
or see a pad you have not opened up, and widening that surface is a decision
somebody has to take rather than a line somebody adds.

When an agent writes to a pad you have open, the write lands in the window as a
single named undo. When it writes to one you have closed, the pad says so the
next time you look at it, and the menubar marks it until you do. Clients that
run on your Mac work directly — Claude Code, Codex, and Claude Desktop through
the small shim that ships inside the application.

## What it will not become

Itchy is for content that is passing through: a tracking number, a failing
request's JSON, a paragraph still being argued over. It is not a note-taking
application and will not grow into one. There is no document library, no
folders, no tags and no search across everything, because the whole collection
fits in a glance.

[The vision document](docs/itchy-vision.md) explains why the limit is the
design, and what the project is measured by.

## Installing

There is no published download yet, so build it:

```bash
brew install swiftlint xcodegen
git clone https://github.com/thowland/itchy.git && cd itchy
make app
```

Then drag `build/Itchy.app` into `/Applications` and open it. Itchy has no Dock
icon and no main window; look for the cat in the menubar. It only offers to
start at login when it runs from `/Applications`.

The [user guide](docs/user-guide.md) covers everything from there, and **Itchy
Help** in the menubar covers the same ground inside the application.

## Building from source

| | |
|---|---|
| To run | macOS 15 or later |
| To build | macOS 26 and Xcode 26, which also provides `swift-format` |
| SwiftLint, XcodeGen | `brew install swiftlint xcodegen` |

```bash
make open        # generate the Xcode project and open it
make run         # build and launch
make test        # the test suite, without the UI tests
make gate        # lint, architecture checks, tests and coverage
make help        # everything else
```

The gate is what a change has to pass: SwiftLint and `swift-format` in strict
mode, six architecture checks, every test, and a coverage floor of 80 per cent.
[docs/development.md](docs/development.md) covers the rest — the test suites and
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
