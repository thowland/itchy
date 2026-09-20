# Itchy

A menubar-resident scratchpad service for macOS. Fixed set of pads, floating
non-activating panels, styled text with images, indefinite retention, and — the
differentiating position — pads exposed as a surface software agents can read
from and write to over MCP.

**Status: 1.0.0, released.** Every sprint in the plan is done, 0 through 10,
and every requirement has its acceptance criterion recorded as met. The
repository is public at <https://github.com/thowland/itchy> under GPL-3.0, and
1.0.0 is the first disk image anybody can download — which is what D-22
reserved the number for, since 0.1.1 was signed and notarised but existed only
on two machines belonging to the same person.

`§14.6`'s manual checklist passed for 0.1.1 on 19 September 2026 and is empty:
a notarised image opened on a Mac that had never seen it with no Gatekeeper
override, it ran correctly on macOS 15, ⌃⌥Space fired, and a connection to the
agent server from a second machine was refused — `NFR-4.2`, `FR-1.4` and
`FR-8.3`. That list comes round again at the next release; keep it.

The plan's §9 interval is closed (D-28): a week of daily use, and working text
stopped being routed through messages-to-self.

## Documents, in precedence order

Read these before proposing anything. Where two disagree, the earlier one
governs, except that the architecture document governs the specification on
matters of implementation.

| Document | Answers |
|---|---|
| `README.md` | What it is, how to install and build it, and where everything else is |
| `docs/development.md` | Building, testing, permissions, signing for development, troubleshooting |
| `docs/releasing.md` | Versioning, certificates, notarisation, packaging, publishing |
| `docs/user-guide.md` | Using Itchy, for somebody who did not build it |
| `docs/itchy-vision.md` | Why this exists, and what it must never become |
| `docs/itchy-architecture.md` | The shape: layers, storage, build order |
| `docs/itchy-requirements.md` | What must be true — numbered, with acceptance criteria |
| `docs/itchy-specification.md` | How it is assembled — decisions D-1…D-11, seams, formats |
| `docs/itchy-implementation-plan.md` | In what order, and under what gate |
| `docs/decisions/` | Everything decided since, D-12 through D-33 |

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

`FR-3.8` is the worked example of where the line falls, and it is worth reading
before arguing about a new feature. A pad may carry a coloured rule, which is
one step from a tag — so the requirement ends with a MUST NOT: the colour may
never be used to filter, sort or search. A landmark for finding one window among
many is allowed; a category the collection can be queried by is `CON-1` and is
refused. Most additions can be settled the same way, by asking what the feature
would let somebody ask of the whole set.

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
6. **Outbound connections are confined to a named list** (`NFR-3.1`,
   `FR-9.4`). The application listens and does not dial; only the shim may open
   a connection, and only to loopback. R4's model client joins the list
   deliberately, as a reviewable change.

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

**A green CI run is not the gate and does not claim to be** (D-32). It answers a
narrower question: does this build and pass on a machine that is not this one.
That question is worth asking — it has already caught a `sending` capture that
only Swift 6.4 accepted — but `make gate` on real hardware is what G1–G3 mean,
and G4 is manual. Do not report a change as gated because GitHub went green.

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
own the process it launches, and the symptom is a run that never finishes. It
spares the installed copy on purpose — that one is somebody's working
application, and it never lives under `Build/Products`, which is how the reap
tells them apart.

**`NFR-1.1`'s budget is skipped on CI**, by `Scripts/test.sh` rather than by
anything inside the test (D-32). The 250 ms hotkey-to-pad budget is a claim
about the machine somebody types on; a hosted runner measured 497 ms on code
that takes about 40 ms here. The skip is announced on the line after the result,
because a test that quietly stops running is how a suite stops checking things.
It lives in the script because `xcodebuild` does not forward its environment to
a hosted test process, so a check for `$CI` inside the test cannot see it — that
was tried first and failed on CI exactly as before.

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
make help        # every target, with a line each
make gate        # the sprint exit gate: lint, arch-lint, test, coverage (G1-G3)
make open        # regenerate Itchy.xcodeproj and open it in Xcode
make regenerate  # force a regeneration when the cache is wrong
make test        # packages, harness, app target — no permissions needed
make test-ui     # the XCUITest suite, which does need automation permission
make test-all    # both
make lint        # swiftlint and swift-format, strict (G1)
make format      # apply swift-format in place
make arch-lint   # the six architectural invariants
make coverage    # coverage against the 80% floor; COVERAGE_REPORT=1 for per-file
make verify-gate # prove the gates fail when they should
make sign-setup  # point Debug builds at a keychain identity (see below)
make bump        # raise the patch version; PART=minor or PART=major (D-22)
make version     # print the current version
make icon        # regenerate the app icon from the cat.fill symbol
make screenshots # regenerate docs/images from the running application
make app         # build the bundle into ./build and print its path
make run         # build and launch it
make reveal      # build and show it in Finder
make package     # DMG from the current build — app, Applications link, README
make release     # Developer ID signed, hardened release build (NFR-4.2)
make notarise    # notarise and staple that build
make dmg         # signed, notarised, stapled disk image
make publish     # draft a GitHub release from it; PUBLISH=1 to go live
make ship-check  # report whether this machine can produce a shippable build
make clean       # remove build products and the generated project
```

`make app` copies the bundle to `build/Itchy.app` rather than leaving it under
`.build/`, because Finder hides directories whose names begin with a dot and an
app nobody can find is an app nobody can run. Every `xcodebuild` invocation
names its destination: without that it warns about choosing between arm64 and
x86_64, which reads as an error.

The release chain runs in order and each step refuses to proceed on the
previous one's absence: `release` → `notarise` → `dmg` → `publish`. `publish`
drafts a GitHub release unless `PUBLISH=1`, takes its notes from the version's
section of `CHANGELOG.md`, and re-verifies stapling, Gatekeeper and the version
inside the mounted image rather than trusting that `make dmg` ran. Its refusals
are documented in `docs/releasing.md`; each is a mistake that produces a release
which looks correct and is not.

`Itchy.xcodeproj` is generated from `project.yml` and is not committed (D-12).
It regenerates only when `project.yml` changed; `make regenerate` forces one. A
file created on disk is picked up on the next generate — adding it inside Xcode
does not add it to `project.yml`, and the symptom is a build error naming a type
that plainly exists.

## Conventions

- Swift language mode 6 with strict concurrency from the first commit (D-1);
  `SWIFT_VERSION` is 6.0 and the packages declare tools 6.2. The store is an
  actor; the view layer is `@MainActor`. The *toolchain* differs between here
  and CI — 6.4 locally, 6.3 on the runner at the time of writing — and that is
  useful rather than a problem, because strict-concurrency diagnostics are
  exactly where minor versions disagree (D-32). Write for the stricter one.
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
  after the last — D-33 at the time of writing — and added to that directory's
  `README.md` index in the same commit. If it contradicts the specification,
  update the specification in the same commit too.

## Where things are

```
App/            menubar, panels, text bridge, settings, help, coordinator
Packages/
  ItchyCore/    model, store, atomic writes, migrations, the debug log.
                No UI framework
  ItchyServices/transforms, MCP server and its loopback transport, model client
Harness/        itchyctl — drives the store without the interface
Shim/           itchy-mcp — stdio to the loopback endpoint, no protocol logic
Scripts/        arch-lint, coverage, test, release, screenshots,
                automation-mode, sign-setup, xcnoise, make-appicon
docs/images/    generated by `make screenshots`, never edited by hand
```

Pads live in `~/Library/Application Support/Itchy/pads.noindex/`. The `.noindex`
suffix is load-bearing: a rename that drops it silently restores Spotlight
indexing of every pad, with nothing failing (D-16).

## The repository is public

<https://github.com/thowland/itchy>, GPL-3.0, since September 2026. Three things
follow that did not apply before.

Anything committed is published, including comments and commit messages. The
tree was checked before the first push — no credentials, no team identifier, no
absolute home paths, and `docs/releasing.md` uses placeholders throughout — and
secret scanning with push protection is on, but scanning is a backstop and not a
review.

Issues and pull requests may arrive from people who have never read the vision
document. `CONTRIBUTING.md` states the one question every feature has to answer
and `SECURITY.md` names what is worth reporting; both are kept current rather
than left to rot, because they are the only things standing between a stranger's
reasonable request and `CON-3`.

CI runs `gate` and `ui` as separate jobs on `macos-26`. The `ui` job is
`continue-on-error` and does not block a merge, and it does pass on the hosted
image — Automation Mode is configured there, which had been an open question.

## Blocked on a person

Nothing standing, but one item comes round every release and is live now.

`§14.6`'s manual checklist has to be run against each shipped image, and it
passed for 0.1.1 on 19 September 2026. **It has not been run for 1.0.0.** None of
it can be done from the machine under test, which is why it is a list rather than
a suite:

- A signed, notarised image opens on a Mac that has never seen the build, with
  no Gatekeeper override (`NFR-4.2`).
- The application runs correctly on macOS 15, the floor D-27 moved it to, so
  that floor is observed rather than compiled-for.
- ⌃⌥Space fires (`FR-1.4`). Registration is verified in the suite; the firing
  cannot be, because a synthesised keypress cannot be posted from a test
  process.
- A connection to the agent server's port from a second machine fails to
  establish (`FR-8.3`).

All four framework spikes are resolved (D-15, D-16, D-17) and the provisioning
is done, so nothing else needs a person.

## What is next

**Every sprint in the plan is done**, 0 through 10, every requirement has its
acceptance criterion recorded as met, and 1.0.0 is published. There is nothing
left that the plan asked for.

That makes this the most dangerous point in the project rather than the safest.
The vision document's warning was never about missing features; it was about the
ones that arrive afterwards, one reasonable request at a time. `CON-3` is the
question to ask of every one of them, and it is not rhetorical: does this serve
transient content, or permanent content? If permanent, decline it.

What would be worth doing, if anything:

- Use it, and let §9's answer be re-asked in three months rather than assumed.
  D-28 closed the interval after a week; a week is evidence and not a habit.
- **A live model completion has never been run.** Ollama is up on this machine
  with no models pulled (D-31), so `OllamaClient` has only ever been exercised
  against a stubbed session. Pulling a model and running Tidy Prose over a real
  pad is the last unverified path in the product, and the one most likely to
  hold a surprise.
- Run `§14.6` against the 1.0.0 image, as above.
