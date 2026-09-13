# Development

Building, testing and troubleshooting Itchy. For how to use it, see the
[user guide](user-guide.md); for versions and distribution, see
[releasing](releasing.md).

## Requirements

| | |
|---|---|
| macOS | 26 or later. There is no back-compatibility story and there will not be one |
| Xcode | 26 or later, for the toolchain and for `swift-format` |
| SwiftLint | `brew install swiftlint` |
| XcodeGen | `brew install xcodegen` |

`swift-format` comes from the Xcode toolchain and is invoked as
`xcrun swift-format`. Do not install it from Homebrew: a separately installed
formatter drifts from the compiler that builds the code.

## Building

```bash
make open        # generates Itchy.xcodeproj and opens it in Xcode
make app         # build the application bundle into ./build
make run         # build and launch it
make reveal      # build and show it in Finder
make help        # every target
```

`Itchy.xcodeproj` is generated from `project.yml` and is not committed. Files
created on disk are picked up on the next generate; adding a file inside Xcode
does not add it to `project.yml`, and the symptom is a build error naming a type
that plainly exists. `make regenerate` forces a generate. See
[D-12](decisions/D-12-xcode-project.md).

`make app` leaves the bundle at `build/Itchy.app`. Xcode's own build products
live under `.build/`, which Finder hides because the name begins with a dot.

Itchy has no Dock icon and opens no window: when it launches, look for the cat
in the menubar. A development build registers itself as a login item only when
it runs from `/Applications`, so a build directory never ends up in System
Settings.

## Tests and the gate

```bash
make test        # packages, harness and app target, without the UI suite
make test-ui     # the XCUITest suite, which needs macOS automation permission
make test-all    # both
make coverage    # coverage against the 80% floor; COVERAGE_REPORT=1 for per-file
make gate        # lint, architecture checks, tests and coverage
make verify-gate # prove the gates fail when they should
```

A warm `make test` takes about twenty seconds. If it takes minutes, something is
forcing a full rebuild; see *Troubleshooting*.

No individual test should take more than ten seconds. One that does has not
found a slow path, it has hung, and the harness treats that as a failure. The
rules live in `Tests/ItchyTests/TestTiming.swift`.

`make test` skips the UI suite on purpose. It is the only part that needs
automation permission, and a permission dialog blocks invisibly: the symptom is
a run that hangs rather than a question you can answer.

`make gate` is the exit gate every change passes: no lint failures, no failing
tests, line coverage of at least 80%. The architectural rules it enforces, and
why each exists, are in [CLAUDE.md](../CLAUDE.md) and `Scripts/arch-lint.sh`.

## Permission prompts

There are two different prompts, with different fixes.

### Automation Mode asking for authentication

XCUITest switches macOS into Automation Mode for every run, and by default the
system asks for a password each time. This is a device policy, so signing does
not affect it. Check with:

```bash
automationmodetool
# "This device requires user authentication to enable Automation Mode."
```

`make test-ui` handles this itself (`Scripts/automation-mode.sh`). It switches
the authentication requirement off for the duration of the run and puts it back
when the run ends, including a failed or interrupted run:

- From a terminal, `automationmodetool` asks for your password at the start,
  before the build, and may ask again at the end to put the setting back.
- If the setting is already off, as on a CI runner configured for UI testing,
  nothing is asked and nothing is restored.
- With no terminal to ask in (an editor task, an agent, a CI runner that has not
  been configured), it stops immediately and says why, rather than hanging on a
  dialog. `ITCHY_UI_ALLOW_PROMPT=1 make test-ui` runs anyway and relies on
  someone answering the dialog.

To make it permanent instead, on a machine used only for development or on a
self-hosted runner:

```bash
automationmodetool enable-automationmode-without-authentication
# and to undo:
automationmodetool disable-automationmode-without-authentication
```

Not under `sudo`. The tool asks for the password of the user running it, so
under `sudo` it asks for root's, which on macOS normally has none.

The trade-off is that any process running as you can then enter Automation Mode,
which allows synthesised input, without asking. A self-hosted runner must also
run inside a logged-in user session (a LaunchAgent, not a LaunchDaemon), or UI
tests cannot drive windows at all.

### Permission asked for again after every rebuild

```bash
make sign-setup
make regenerate
```

An ad-hoc signed application has no stable designated requirement, so TCC keys
its grant on the code hash, and the hash changes on every build. Every rebuild
therefore looks like a different application. Signing Debug builds with a real
identity gives a requirement that is stable across rebuilds, so answering the
prompt once is enough:

```
designated => identifier "com.wdogsystems.itchy" and anchor apple generic
              and certificate leaf[subject.CN] = "Apple Development: …"
```

`make sign-setup` picks an identity from the keychain, preferring Developer ID
and then Apple Development, and writes `Config/Signing.local.xcconfig`, which is
not committed. Without an identity, builds stay ad-hoc and everything still works
except that the prompt returns.

```bash
./Scripts/sign-setup.sh --list
./Scripts/sign-setup.sh ABCDE12345   # team, name fragment or certificate hash
```

The chosen identity is recorded by certificate hash rather than by name. One
common name can cover many certificates, since annual renewals accumulate, and
`codesign` given an ambiguous name is free to pick any of them, including an
expired one.

Do not set `CODE_SIGN_IDENTITY` at project level in `project.yml`. A
project-level value overrides the xcconfig, and the symptom is a build that is
still ad-hoc for no visible reason.

## Layout

```
App/              the application: menubar, panels, text bridge, settings, coordinator
Packages/
  ItchyCore/      model, store, atomic writes, migrations, backups. Links no UI framework
  ItchyServices/  transforms, MCP server and model client, mostly still to come
Harness/          itchyctl, a development-only command-line driver for the store
Shim/             itchy-mcp, the stdio proxy (arrives with the MCP server)
Scripts/          test runner, gates, coverage, signing, release
Config/           build settings: version, signing
docs/             vision, architecture, requirements, specification, plan, decisions
```

## Storage

Pads are flat files under `~/Library/Application Support/Itchy/`:

```
Itchy/
├── index.json          pad order and the last-used pad
├── settings.json       preferences
├── pads.noindex/       one directory per pad
│   └── <uuid>/
│       ├── content.rtfd/   the pad's content, with any images
│       ├── content.txt     the same as plain text
│       └── meta.json       name, mode, window position, and so on
└── archives.noindex/   backups, one timestamped directory each
```

There is no database, and everything is readable with `ls` and `cat`. The
`.noindex` suffix keeps pad contents out of Spotlight while leaving them
readable to `grep` and to tooling. It is load-bearing: a rename that drops it
silently restores indexing. See [D-16](decisions/D-16-spotlight-exclusion.md)
and, for backups, [D-18](decisions/D-18-archives.md).

`itchyctl` drives the store without the interface, which is useful for looking
at what is actually on disk:

```bash
cd Harness && swift build
ITCHY_ROOT=/tmp/scratch .build/debug/itchyctl create "notes"
ITCHY_ROOT=/tmp/scratch .build/debug/itchyctl list
ITCHY_ROOT=/tmp/scratch .build/debug/itchyctl fault content   # damage a pad on purpose
```

Its other commands are `read`, `write`, `rename`, `delete`, `faults` and
`where`, and `fault` also accepts `metadata`, `schema` and `index`.

## Troubleshooting

**`make test` takes minutes.** Something is forcing a full rebuild. The usual
cause is `Itchy.xcodeproj` being regenerated when it did not need to be; it is a
file target that regenerates only when `project.yml` or a source directory
changes.

**A test run never finishes.** Two causes, in order of likelihood.

A permission dialog is waiting on screen. It blocks the test runner and is easy
to miss on a second display. Usually it is Automation Mode asking for
authentication, which `make test-ui` switches off for the run; otherwise
`make sign-setup` stops it recurring. To see whether one is up:

```bash
osascript -e 'tell application "System Events" to get name of every process whose frontmost is true'
```

Or an Itchy instance was left behind by an interrupted run, and
`XCUIApplication` expects to own the process it launches. `Scripts/test.sh`
kills strays before starting, but only builds under a `Build/Products`
directory, never an installed copy. By hand:

```bash
pkill -f "/Build/Products/.*Itchy.app/Contents/MacOS/Itchy"
```

**A package target fails with "cannot find X in scope" for a type that exists.**
A new file in `ItchyCore` has not reached a dependent package's build cache.
Remove the dependent's cache: `rm -rf Packages/ItchyServices/.build Harness/.build`.

**`make app` says it built, but the app is nowhere.** It is at
`build/Itchy.app`; `make reveal` shows it in Finder.

**The installed app does not appear in Spotlight.** Every build and test run
registers another copy with the same bundle identifier, and a copy that is
later deleted leaves its registration behind. List what LaunchServices holds:

```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -dump \
  | grep -E "^path:.*Itchy.app"
```

and unregister stale entries with `lsregister -u <path>`. `Scripts/coverage.sh`
unregisters its own temporary builds.

**A login item appears pointing at a build directory.** Itchy only registers
itself automatically when running from `/Applications`. If an older build left
one, remove it in **System Settings → General → Login Items**.
