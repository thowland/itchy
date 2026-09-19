# Itchy

A menubar-resident scratchpad service for macOS. Fixed set of pads, floating
non-activating panels, styled text with images, indefinite retention, and — the
differentiating position — pads exposed as a surface software agents can read
from and write to over MCP.

**Status: R1 shipped-ready, every acceptance criterion demonstrated.** Sprints 0–5 are done, and so are
Sprint 6 (transforms), Sprint 8 (the MCP server) and all of Sprint 9 but the
stdio shim. On 19 September 2026 a signed, notarised 0.1.1 disk image opened on
a Mac that had never seen it, with no Gatekeeper override, and ran correctly
through its smoke tests on macOS 15. ⌃⌥Space fires there, and a connection from
a second machine to the agent server is refused — so `NFR-4.2`, `FR-1.4` and
`FR-8.3` are all demonstrated, and `§14.6`'s manual checklist is empty for the
first time.

What comes next is the month of daily use the plan's §9 calls for, not more
features.

## Documents, in precedence order

Read these before proposing anything. Where two disagree, the earlier one
governs, except that the architecture document governs the specification on
matters of implementation.

| Document | Answers |
|---|---|
| `README.md` | What it is, how to install and build it, and where everything else is |
| `docs/development.md` | Building, testing, permissions, signing for development, troubleshooting |
| `docs/releasing.md` | Versioning, certificates, notarisation, packaging |
| `docs/itchy-vision.md` | Why this exists, and what it must never become |
| `docs/itchy-architecture.md` | The shape: layers, storage, build order |
| `docs/itchy-requirements.md` | What must be true — numbered, with acceptance criteria |
| `docs/itchy-specification.md` | How it is assembled — decisions D-1…D-11, seams, formats |
| `docs/itchy-implementation-plan.md` | In what order, and under what gate |
| `docs/decisions/` | Everything decided since, D-12 onward |

Cite requirement identifiers (`FR-4.2`, `NFR-1.1`, `CON-3`, `D-11`) in commits,
comments, and discussion. They are permanent; a withdrawn requirement is marked
withdrawn in place and its number is never reused.

## The governing constraint

Itchy is for transient content. Before adding anything, ask whether the feature
serves transient content or permanent content; if permanent, decline it
(`CON-3`). No document library, folder hierarchy, tagging, or corpus-wide search
(`CON-1`). No save, title, or filing prompts — pad deletion is the single
exception (`CON-2`, `FR-2.6`). No cloud sync, no telemetry, no chat panel.

The largest risk to this project is not technical. It is accretion into the
note-taking application it was built to avoid.

## Architectural rules that must not decay

Each is enforced by a check in `Scripts/arch-lint.sh`, and each exists because
it is the kind of rule that erodes silently.

1. **The store is the only component that touches disk** (`CON-4`). No
   `FileManager` outside `ItchyCore/Store` — in shipping sources; tests reach
   for it freely, because verifying what landed on disk is the point.
2. **`ItchyCore` links no UI framework** (D-2, `NFR-4.3`). An `import AppKit`
   there must fail the build.
3. **One call site for `Transform.apply`** (specification §12), so the menu path
   and the MCP path are subject to the same routing policy rather than two
   policies that are meant to agree.
4. **Coverage exclusions pass the complexity cap** (D-11, §15.3). Exclusion is
   earned by triviality.
5. **No test reaches the real Keychain** (D-26). Opening it asks the person
   running the suite for permission, and a run that waits for an answer hangs —
   unanswerably, on CI. `MCPTokenStore` is the seam; tests get
   `InMemoryTokenStore`. The rule has no exception mechanism on purpose.

## Testability doctrine (D-11)

View files translate and apply; they do not decide. Every decision that would
otherwise sit in a view body, window controller, `NSViewRepresentable`, or
delegate stub is extracted into a pure value-typed unit — `*Model` for a
projection, `*Plan` / `*Policy` / `*Resolver` for a decision, `*Codec` for a
conversion. Decisions return enumerations, never Booleans or Boolean pairs. No
function both decides and performs.

When something feels hard to test, the question is not "how do I test this view"
but "what decision is stranded inside this view". Specification §15.2 lists the
ones already found; adding another means adding a row in the same commit.

## Sprint exit gate

No sprint exits until all four hold, and they are cumulative — earlier sprints'
tests must still pass:

- **G1** no lint failures (`swiftlint --strict`, `swift-format lint --strict`, `arch-lint`)
- **G2** no failing tests anywhere
- **G3** line coverage ≥ 80% over the denominator in plan §3.3
- **G4** every requirement the sprint claims has its acceptance criterion demonstrated

An obsolete test may be deleted, recorded with the requirement that changed —
but never in a way that drops coverage below the floor.

## Test timing

Nothing here legitimately takes ten seconds. We run locally against a store of at
most twenty small files, so a test that runs long has hung, and a hung test is a
failed test. `Tests/ItchyTests/TestTiming.swift` holds the rules; waits fail at
the boundary and name what they were waiting for rather than returning quietly.

A warm `make test` takes about twenty seconds. If it takes minutes, something is
forcing a full rebuild — usually the Xcode project being regenerated when it did
not need to be.

`Scripts/test.sh` kills orphaned processes before starting. An Itchy instance
left behind by an interrupted run confuses `XCUIApplication`, which expects to
own the process it launches, and the symptom is a run that never finishes.

**The UI suite is not in the default path.** It is the only part that needs
macOS automation permission, and a permission prompt blocks invisibly — what you
see is a hang, not a question. `make test` skips it; `make test-ui` runs it; CI
runs it as a separate job that does not gate a merge.

**Automation Mode is switched for the run.** XCUITest enters macOS Automation
Mode, which by default asks for authentication every time: a device policy that
signing does not touch. `make test-ui` turns the authentication requirement off
for the run and restores it afterwards (`Scripts/automation-mode.sh`). From a
terminal, the tool asks for your password at the start and may ask again at the
end. Never under `sudo`: it then asks for root's password. With no terminal, as
when an agent runs it, it stops and says so instead of hanging;
`ITCHY_UI_ALLOW_PROMPT=1` accepts the on-screen dialog instead.

**If the prompt keeps coming back after rebuilds, run `make sign-setup`.** An ad-hoc signed
application has no stable designated requirement, so TCC keys its grant on the
code hash, and the hash changes on every build — so every rebuild looks like a
new application. Signing Debug with a real identity makes the requirement stable
and the grant sticks. The identity lives in `Config/Signing.local.xcconfig`,
which is not committed; `Config/Debug.xcconfig` defaults to ad-hoc so a clone and
a CI runner still build.

Note: `CODE_SIGN_IDENTITY` must not be set at project level in `project.yml`. A
project-level value overrides the xcconfig, and the symptom is a build that is
still ad-hoc for no visible reason.

## Commands

```
make gate        # the sprint exit gate: lint, arch-lint, test, coverage (G1-G3)
make open        # regenerate Itchy.xcodeproj and open it in Xcode
make test        # packages, harness, app target — no permissions needed
make test-ui     # the XCUITest suite, which does need automation permission
make test-all    # both
make coverage    # coverage against the 80% floor; COVERAGE_REPORT=1 for per-file
make verify-gate # prove the gates fail when they should
make sign-setup  # point Debug builds at a keychain identity (see below)
make format      # apply swift-format in place
make bump        # raise the patch version; PART=minor or PART=major (D-22)
make version     # print the current version
make icon        # regenerate the app icon from the cat.fill symbol
make app         # build the bundle into ./build and print its path
make run         # build and launch it
make package     # DMG from the current build — app, Applications link, README
make ship-check  # report whether this machine can produce a shippable build
```

`make app` copies the bundle to `build/Itchy.app` rather than leaving it under
`.build/`, because Finder hides directories whose names begin with a dot and an
app nobody can find is an app nobody can run. Every `xcodebuild` invocation
names its destination: without that it warns about choosing between arm64 and
x86_64, which reads as an error.

`Itchy.xcodeproj` is generated from `project.yml` and is not committed (D-12).
It regenerates only when `project.yml` changed; `make regenerate` forces one. A
file created on disk is picked up on the next generate — adding it inside Xcode
does not add it to `project.yml`, and the symptom is a build error naming a type
that plainly exists.

## Conventions

- Swift 6.3, strict concurrency from the first commit (D-1). The store is an
  actor; the view layer is `@MainActor`.
- `swiftlint` from Homebrew; `swift-format` from the Xcode toolchain via
  `xcrun swift-format`, never from Homebrew (D-1).
- `xcodegen` from Homebrew generates the project (D-12). It is a development
  tool, not a shipped dependency, so it sits outside D-4.
- Swift Testing for new tests; XCTest only where its machinery is required;
  XCUITest for the UI smoke suite.
- Documents are written in British spelling and in continuous prose with
  reasoning attached. A decision recorded without its reasoning cannot be
  reversed safely later.
- A decision taken during implementation goes in `docs/decisions/`, numbered
  from D-12. If it contradicts the specification, update the specification in
  the same commit.

## Where things are

```
App/            menubar, panels, text bridge, settings, help, coordinator
Packages/
  ItchyCore/    model, store, atomic writes, migrations, the debug log.
                No UI framework
  ItchyServices/transforms, MCP server and its loopback transport, model client
                (the model client is still to come)
Harness/        itchyctl — drives the store without the interface
Shim/           itchy-mcp (Sprint 9)
Scripts/        arch-lint, coverage, test, release, make-appicon
```

Pads live in `~/Library/Application Support/Itchy/pads.noindex/`. The `.noindex`
suffix is load-bearing: a rename that drops it silently restores Spotlight
indexing of every pad, with nothing failing (D-16).

## Blocked on a person

Nothing, for the first time. All four framework spikes are resolved (D-15, D-16,
D-17), the provisioning is done, and every item on the manual checklist in
`§14.6` passed for 0.1.1 on 19 September 2026:

- A signed, notarised image opened on a Mac that had never seen the build, with
  no Gatekeeper override (`NFR-4.2`).
- The application ran correctly on macOS 15, which is the floor D-27 moved it
  to, so that floor is observed rather than compiled-for.
- ⌃⌥Space fires (`FR-1.4`). Registration was verified in the suite from Sprint
  5; the firing could not be, because a synthesised keypress cannot be posted
  from a test process. That gap is closed.
- A connection to the agent server's port from a second machine failed to
  establish (`FR-8.3`).

Three of those had been outstanding since the sprints that claimed them, for the
same reason: none can be run from the machine under test. Keep the list — the
next release needs it run again — but it is empty now.

The only work that is *waiting* rather than blocked is the stdio shim
(`FR-8.2`), which the Developer ID certificate unblocked and which nobody has
written.

## What is next

Sprint 7 (provenance) and Sprint 10 (model routing). The plan's §9 puts a month
of daily use between R1 and the second release, deliberately: the measure of
this project is whether working text actually stops being routed through
messages-to-self, and that cannot be read while features are still arriving.

Now that the MCP server runs, that month is also the first real test of the
thing the project exists for. `docs/mcp-remaining-work.md` is down to the shim
and the two acceptance criteria that cannot be run from this machine.
