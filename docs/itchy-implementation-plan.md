# Itchy — Implementation Plan

*Draft, September 2026*

## 1. Purpose

This document sequences the work described in `itchy-specification.md` into sprints, and defines the gate each sprint must pass before the next one opens. It is the fourth and last of the planning documents: vision states why, architecture states the shape, requirements state what must be true, specification states how it is assembled, and this states in what order and under what discipline.

The objective is a working MVP — the first release as defined in `itchy-requirements.md`, tagged R1 throughout — reached in as few sprints as the dependency order allows. Sprints after the MVP are sketched rather than planned in detail, because §9 argues that they should be re-planned after the MVP has been in daily use.

Sprints are one week of part-time solo work. That figure is a planning unit rather than a commitment, and the sequence matters considerably more than the durations; a sprint that takes two weeks has not failed, whereas a sprint that exits without passing its gate has.

## 2. The standing exit gate

Every sprint, including Sprint 0, exits only when all four conditions hold. They are cumulative: a later sprint inherits every earlier sprint's tests and must keep them passing.

**G1 — No linting failures.** `swiftlint --strict` reports zero violations, `xcrun swift-format lint --recursive --strict` reports zero, and the architecture lint in §3.4 reports zero. Warnings are errors; there is no allowance for a violation left in place with a comment explaining it.

**G2 — No failing tests, anywhere.** The entire suite passes, not the subset written this sprint. A test written in Sprint 1 that fails in Sprint 4 is a Sprint 4 blocker.

**G3 — Line coverage at or above 80%** over the measured denominator defined in §3.3.

**G4 — Every requirement claimed by the sprint has its acceptance criterion demonstrated**, per `itchy-requirements.md`. For criteria that are automated this is implied by G2; for the manual ones it means the check has actually been performed and recorded in the sprint's closing note, not assumed.

### 2.1 Obsolete tests

A test may be deleted when the behaviour it describes has been deliberately changed or removed, and the deletion is recorded in the sprint's closing note with the requirement that changed. What a deletion may not do is move coverage below the threshold: if removing a test drops the figure under 80%, the sprint does not exit until coverage is restored by testing something real. This is the specific loophole the gate is written to close, because the easiest way to hit a coverage number is to delete the tests that exercise the hard parts.

### 2.2 What the gate is not

The gate is not a quality claim. Eighty per cent line coverage says the lines ran, not that they were checked, and a suite can hold that number while asserting almost nothing. The mitigations are that the store's tests are behavioural and fault-injecting rather than call-and-assert-not-nil, and that §3.3's denominator excludes the code where a coverage number would be least meaningful. Treat the figure as a floor that catches whole areas going untested, which is what it is good at.

## 3. Engineering setup

### 3.1 Toolchain

Swift 6.3 with strict concurrency (D-1), Xcode for the app target via a generated project (D-12), SwiftPM for `ItchyCore` and `ItchyServices` (D-2). Swift Testing for new tests, XCTest where the machinery requires it, XCUITest for the UI smoke suite (D-3).

### 3.2 Linting

`swiftlint` with a checked-in `.swiftlint.yml`: the default rule set, plus opt-in rules for `explicit_acl` on package targets, `force_unwrapping`, `force_try`, and `implicitly_unwrapped_optional`. `swift-format` handles formatting with a checked-in `.swift-format`, invoked as `xcrun swift-format` so that the formatter tracks the toolchain that compiles the code (D-1). Formatting is not negotiated in review because it is not decided in review.

Both tools are already present on the development machine: `swiftlint` 0.65.1 from Homebrew, `swift-format` 6.3.0 from the Xcode 26.6 toolchain. Both were confirmed to exit non-zero on a violation and zero on clean input, which is the only property the gate actually depends on.

### 3.3 Coverage measurement

The number is meaningless without its denominator, so the denominator is specified rather than left to the tool's default.

**Included:** all of `ItchyCore` and `ItchyServices`, and the non-view logic of the app target — window controllers, the registry, the coordinator, the paste interceptor, the hotkey wrapper, the frame-restoration algorithm.

**Excluded**, via a checked-in exclusion list with a one-line reason each: SwiftUI `body` implementations, `NSViewRepresentable` `makeNSView`/`updateNSView` bodies, `@main` and app-delegate lifecycle stubs, and generated code. These are excluded because covering them means asserting that a view hierarchy was constructed, which is the kind of test that raises the number and finds nothing.

**Exclusion is earned, not asserted.** A file may sit on the exclusion list only while it passes a scoped lint configuration setting `cyclomatic_complexity` to 2 and prohibiting `if`, `switch`, and `for` other than optional unwrapping (specification §15.3). A view file that acquires a branch stops qualifying, and the choice at that point is to extract the branch into a seam or to start covering the file. Both are fine; an untested branch sitting inside an unmeasured file is not, and without this coupling the exclusion list is exactly where such branches would accumulate.

The consequence is that the 80% floor bites hardest on the store, the transforms, the MCP service and the algorithms — which is where it should bite. It also means the figure is only honest while the exclusion list stays short: adding an entry to it is a change that needs the same scrutiny as deleting a test, and §2.1 applies to it by analogy.

Mechanically: `swift test --enable-code-coverage` for the packages, `xcodebuild -enableCodeCoverage YES` for the app target, both exported through `llvm-cov` and combined by `Scripts/coverage.sh`, which applies the exclusion list and exits non-zero below 80%.

### 3.4 Architecture lint

Four checks, run in CI alongside the linters, each encoding a constraint that would otherwise decay silently:

| Check | Encodes |
|---|---|
| No `import AppKit` or `import SwiftUI` anywhere in `Packages/ItchyCore` | D-2, `NFR-4.3` |
| No `FileManager` or `URL(fileURLWithPath:)` outside `ItchyCore/Store` | `CON-4` — the store is the only component that touches disk |
| Exactly one call site for `Transform.apply` | §12 of the specification — one routing-policy enforcement point |
| Every path on the coverage exclusion list passes the scoped complexity cap | D-11, specification §15.3 — exclusion is earned by triviality |

The first three are greps, and their crudeness is acceptable: each is a rule with an obvious textual signature, and the alternative is noticing the violation a year later. The fourth runs the linter with a scoped configuration over exactly the paths the coverage script excludes, so the two lists cannot drift apart.

### 3.5 Decision log

`docs/decisions/` holds one short file per decision taken during implementation, numbered continuing from the specification's D-10. A decision that contradicts the specification updates the specification in the same commit; the two must not be allowed to disagree.

### 3.6 Testability doctrine

Specification §15 is a standing constraint on every sprint below, not a phase of work. Its short form: view files translate and apply, and every decision they would otherwise make lives in a value-typed unit that runs without a window server — `*Model` for a projection, `*Plan`, `*Policy` or `*Resolver` for a decision, `*Codec` for a conversion.

The sprint scopes below name these units explicitly wherever a sprint creates one, and each is listed under that sprint's tests rather than left implicit. Two of them — `FrameResolver` in Sprint 2 and `PastePlan` in Sprint 3 — carry logic that is genuinely intricate and would, placed conventionally, be reachable only by opening windows and pasting things by hand.

A useful check when a sprint feels hard to test: the question is almost never "how do I test this view", it is "what decision is stranded inside this view". §15.2 is the list of the ones already found; a sprint that discovers another adds a row to it in the same commit.

---

## Sprint 0 — Foundation

**Goal.** A repository that builds, lints, tests, and measures itself, with an application that launches into the menubar and does nothing else. No pad functionality whatsoever.

The point of the sprint is that every subsequent gate is mechanical. Standing up the gate after the code exists means retrofitting coverage onto code written without it, which is the expensive order.

**Scope.**

1. Repository skeleton per specification §3: `ItchyCore` and `ItchyServices` packages, `App/`, `Shim/`, `Harness/`, `Tests/`, and `project.yml` from which the Xcode project is generated (D-12).
2. `.swiftlint.yml`, `.swift-format`, `.gitignore`, `.editorconfig`.
3. Swift Testing wired for both packages; XCTest and XCUITest targets present with one trivial test each, so that the harness is proven rather than assumed.
4. `Scripts/coverage.sh` with the exclusion list, the scoped complexity configuration that governs it (§3.3), and `Scripts/arch-lint.sh` with the four checks of §3.4.
5. `Makefile`: `test`, `lint`, `coverage`, `app`, `notarise`, `dmg`.
6. CI running `lint`, `test`, `coverage`, `arch-lint` on every push.
7. Accessory-mode app: `LSUIElement`, `setActivationPolicy(.accessory)`, a `MenuBarExtra` showing a static placeholder, an empty settings window.
8. `docs/decisions/` seeded with the specification's D-1 through D-10 as the existing record.

**Requirements claimed.** `FR-1.1`, `FR-1.5` (stub), `NFR-1.3`, `NFR-4.1`, `NFR-4.3`.

**Tests.** A test asserting `ItchyCore` builds and runs without a UI framework — which, given the package structure, is the build itself. A test that `Scripts/coverage.sh` fails when given a deliberately under-covered fixture, because a coverage gate nobody has seen fail is a coverage gate nobody knows works.

**Exit gate.** G1–G4, with coverage trivially satisfied at this size. Additionally: CI red when a lint violation is introduced on purpose, and green when it is removed. Verify this once, by hand, this sprint.

**Note on the coverage floor in early sprints.** With almost no code, 80% is easy and therefore uninformative. It becomes a real constraint in Sprint 1 and stays one. Do not take Sprint 0's green as evidence that the gate works — the deliberate-failure check above is that evidence.

---

## Sprint 1 — Core model and store

**Goal.** The complete storage layer, fully tested, with no user interface at all. Exercised through `itchyctl`.

This is first because `CON-4` and the MCP direction both depend on the store interface being right, and because it is the one part of the application that can be tested exhaustively without fighting AppKit. It is also where most of the project's coverage is earned; if the store is thinly tested, no later sprint will make up the difference.

**Scope.**

1. Model types per specification §5.1: `PadID`, `PadMode`, `PadFrame`, `ProvenanceEntry`, `PadMetadata`, `PadContent`, `RoutingPolicy`.
2. `PadBounds` with the clamp at all three enforcement points (`FR-2.1`).
3. JSON codecs with the fixed encoder configuration, and the unknown-field preservation of §6.4.
4. Migration machinery, shipping empty at schema version 1 (§6.5).
5. Atomic write per §6.3, for both files and the RTFD directory wrapper, including the `fsync` before replace and the orphaned-temporary sweep.
6. `SaveScheduler` with an injected clock (§6.6).
7. `PadStore` actor implementing `PadStoring`, the `PadChange` stream, and the fault taxonomy of §6.7.
8. `itchyctl`: create, list, read, write, delete, and a `fault` subcommand that injects each fault for manual inspection.

**Requirements claimed.** `FR-2.1`, `FR-2.2`, `FR-2.3`, `FR-2.5`, `FR-5.1`–`FR-5.8`, `FR-5.10`, `NFR-2.1`, `NFR-2.2`.

**Tests.** This sprint carries the heaviest test load in the project, and it is where the 80% floor should be comfortably exceeded rather than just met.

- Bounds clamp at the settings path, the read path with a hand-edited value above the ceiling, and `createPad` at the limit.
- JSON round-trip for every type; unknown-field preservation with a hand-edited fixture.
- Migration fixtures — one per historical shape, which is currently none, so the test is that an unknown-future version is refused rather than guessed.
- Atomic write with injected failure between temporary write and replace, asserting the previous content survives intact.
- Save scheduler debounce, cancellation, and every forced-flush path, against an advanced clock rather than a real sleep.
- Every fault in the taxonomy, each asserting both that the store remains usable and that no case yields an empty writable pad over unreadable content.

**Exit gate.** G1–G4. Additionally, the fault-injection suite must cover every case in `PadStoreFault` — not 80% of them, all of them, since a fault case with no test is a fault case that has never executed.

---

## Sprint 2 — Shell and panels

**Goal.** Real pads from the store, listed in the menubar, opening into floating panels that accept typed input over a fullscreen application. Content is plain and unpersisted; the text layer is Sprint 3.

**Scope.**

1. `MenuModel` projecting `[PadMetadata]` to rows, and `StatusItemController` rendering them with `MenuBarExtra` behind it.
2. `PanelConfiguration` as a value, and `PadPanel` applying it, per specification §8.2 — including the `canBecomeKey` override, which is asserted against the value rather than against a live window.
3. `PadWindowController`, `PadWindowRegistry` with one-window-per-pad (`FR-3.3`).
4. Frame persistence on move and resize, debounced at 200 ms (§8.4).
5. `FrameResolver` — the frame restoration algorithm as a pure function over a stored frame and a set of screen rectangles, all four rules (§8.5).
6. `PadStatusBar` showing name and mode (`FR-3.6`, R1 form).
7. Close forces a flush (`FR-3.5`).

**Requirements claimed.** `FR-1.2`, `FR-3.1`–`FR-3.7`.

**Tests.** `MenuModel`, `PanelConfiguration`, `FrameResolver` and the registry are all pure or headless and carry this sprint's coverage. `FrameResolver` gets a table of cases: frame fully on screen, frame partly off, frame on a display that no longer exists, no stored frame, and a frame whose display ID matches a screen at a different resolution — the proportional-placement rule being the one most likely to be quietly wrong.

The UI smoke suite gains its two most valuable members: a panel summoned over a fullscreen application accepts typed text, and selecting the same pad five times yields one window.

**Exit gate.** G1–G4, plus one condition stated separately because the whole sprint depends on it:

> **The fullscreen keyboard-input test passes before any work begins on the text layer.**

A non-activating panel that silently discards keystrokes looks entirely correct, and discovering it in Sprint 4 means debugging it through three layers of code written on top of it.

---

## Sprint 3 — Text and persistence

**Goal.** Styled text with inline images, persisted through the store, surviving relaunch and abrupt termination. After this sprint the application is genuinely useful to its author, if rough.

**Scope.**

1. `PadTextView`, `PadTextEditor`, `PadTextCoordinator` per §9.2, configured per mode.
2. `ContentCodec` — `NSAttributedString` ⇄ `PadContent` — with RTFD load and save through the store and the plain-text extraction feeding the shadow file.
3. `PastePlan` and `DownsamplePolicy` as pure decisions over a pasteboard descriptor (§9.4), with `PasteInterceptor` reduced to reading the pasteboard into that descriptor and executing the plan, for both paste and drop.
4. `PreviousAppTracker` (§9.5), built now even though provenance itself is R2, because the interceptor is being written now and retrofitting the ordering later means revisiting the same code.
5. Serialisation debounce at 120 ms, staging into the store's 750 ms write debounce (§9.3).
6. `Flatten` as a pure operation on `PadContent`, driving mode switching (`FR-4.5`) and shared verbatim with the future `flatten` transform.
7. The grouped applier used by mode flattening, registered with the registry for later use by transforms and MCP.

**Requirements claimed.** `FR-4.1`–`FR-4.9`, `FR-5.9`.

**Tests.** `ContentCodec` is tested directly against fixtures including one with an image attachment. `DownsamplePolicy` is tested either side of the threshold. `PastePlan` is table-driven over pasteboard descriptors — styled with image into a styled pad, the same into a plain pad, URL-bearing browser paste, file drop, plain text with no URL — which is the case matrix that would otherwise be checked by pasting things by hand and looking. The two-stage debounce is tested against injected clocks at both levels.

UI smoke gains: a pasted image renders, survives relaunch, and is present in stored content.

**Exit gate.** G1–G4. Additionally, a manual check that content written by Itchy opens in TextEdit with its images intact (`FR-5.3`), because that is the property that makes the storage format defensible and no automated test asserts it.

---

## Sprint 4 — Pad lifecycle

**Goal.** Pads are fully manageable. Every R1 behaviour except the entry-point work exists.

**Scope.**

1. Creation with no prompt, rename in place, delete with its single confirmation, reorder, pin (`FR-2.3`–`FR-2.7`).
2. Pinned pads reopening at launch.
3. Pad count setting with the ceiling stated in the UI, and the lowering behaviour of `FR-2.2`.
4. Empty-pad action, undoable (`FR-2.6`).
5. Size markers in the menubar past the 32 MB threshold (`FR-5.9`).
6. Faulted pads presented per §6.7 — listed, selectable, showing the fault and offering to reveal the directory, never an empty editable pad.
7. Copy-entire-pad-as-plain-text (`FR-4.9`).
8. Settings General and Editor panes made real.

**Requirements claimed.** `FR-2.4`, `FR-2.6`, `FR-2.7`, `FR-2.8`, `FR-1.5` (full R1 form).

**Tests.** Lifecycle operations are store operations and are tested there; the new UI-side coverage is the faulted-pad presentation, which is worth an explicit test asserting that a pad with unreadable content never presents an editable empty editor.

**Exit gate.** G1–G4.

---

## Sprint 5 — MVP

**Goal.** Ship R1. After this sprint the application is installed, launching at login, and in daily use.

**Scope.**

1. `HotKeyAction` deciding open, close, or create-first (§8.6), with a `RegisterEventHotKey` wrapper (D-6) that does no deciding of its own, and settings to rebind. Spike S-1 is resolved at the start of this sprint, not during it.
2. Login item via `SMAppService` (`FR-1.3`).
3. `LaunchPlan` describing what is read eagerly and what is deferred (`FR-1.6`, §8.7), executed by a delegate stub that only runs the steps.
4. `OSSignposter` instrumentation and the performance suite enforcing `NFR-1.1` at 250 ms, 95th percentile, first-run included.
5. Spotlight exclusion (`NFR-3.4`, D-10; spike S-3 resolved first).
6. Accessibility pass: full keyboard reachability, system text settings, VoiceOver labels.
7. Signing, hardened runtime, notarisation, stapling, DMG, and a Gatekeeper launch test on a machine that has never seen the build.

**Requirements claimed.** `FR-1.3`, `FR-1.4`, `FR-1.6`, `NFR-1.1`, `NFR-1.2`, `NFR-1.4`, `NFR-3.1`, `NFR-3.4`, `NFR-3.5`, `NFR-4.2`, `NFR-5.1`–`NFR-5.3`.

**Tests.** The performance suite is the significant addition and it is a build-failing test, not a report. It runs against a fixture of nine pads at realistic sizes including one at the size marker, and fails above 250 ms at the 95th percentile.

`NFR-3.1` — no outbound network connection at all in R1 — gets a test asserting the built binary links no networking framework and the process opens no sockets during a scripted session.

**Exit gate.** G1–G4, plus the manual checklist of specification §14.6 performed and recorded: accessibility, Gatekeeper on a clean machine, Spotlight exclusion verified both ways, and idle CPU over five minutes.

**This is the MVP.** Everything in `itchy-requirements.md` tagged R1 now holds.

---

## 9. The interval after the MVP

The next sprint does not begin when Sprint 5 exits. It begins after a month of daily use, and the reason is in the vision document: the measure of this project is whether working text stops being routed through messages-to-self and untitled editor windows, and that cannot be read while features are still arriving.

Two outcomes are worth planning for. If the pads have absorbed that traffic, the sprints below proceed roughly as sketched. If they have not, the correct response is to diagnose the friction rather than to build Sprint 6, because a scratchpad that is not reached for will not become reached-for by acquiring a transform menu.

A month of use is also likely to reorder what follows, and the sketches below are deliberately shallow so that reordering costs nothing.

**Resolved September 2026 (D-28).** The pads absorbed the traffic — the first of the two outcomes above — so the sprints below proceed roughly as sketched. The interval ran for a week of daily use of the first notarised build rather than the month written here, and D-28 records why that was judged sufficient and where it is weaker than the plan intended: Sprint 6 shipped during the interval rather than after it, so §9 gated Sprints 7 and 10 but not the transform work it was written to gate.

---

## 10. Sprints after the MVP, sketched

**Sprint 6 — Transforms.** The `Transform` protocol, the registry, `TransformRunner` as the single call site, and the ten deterministic transforms of specification §7.2 with their applicability predicates. Table-driven tests per transform over representative, empty, boundary, malformed, and multi-byte input. Claims `FR-6.1`–`FR-6.6`. Sparkle lands here (`NFR-4.4`).

**Sprint 7 — Provenance.** Capture through the interceptor built in Sprint 3, storage in metadata rather than attributes, pad-level presentation, clearing. Claims `FR-7.1`–`FR-7.5`. The test that matters is that flattening a pad leaves its provenance list intact, since that is the entire reason the data does not live in text attributes.

**Sprint 8 — MCP transport and surface.** Spike S-4 resolves the SDK question before the sprint opens (D-5). Loopback HTTP binding, Keychain-held bearer token, the five tools, the resource form, plain-text reads with the image placeholder. Claims `FR-8.1`–`FR-8.6`, `FR-8.10`, `NFR-3.3`.

*Complete.* The loopback listener, `endpoint.json`, the shadow-text placeholder and the Agents settings section all landed, and a real MCP client drives the server over HTTP in the suite. The decisions taken along the way are in D-25.

**Sprint 9 — MCP safety.** Per-pad exposure, the write path through the registry applier, external-write markers and the banner, the stdio shim. Claims `FR-8.7`–`FR-8.9`, `NFR-3.2`. Separated from Sprint 8 because the exposure and write-conflict policies are the two questions the architecture document says must be answered before the feature ships, and bundling them with transport work is how they get answered in a hurry.

*Complete.* Exposure has a per-pad toggle and shows on the pad, the registry-aware writer lands an agent write in the open panel as one named undo, the banner and the menubar marker say when something else wrote, and the stdio shim ships inside the bundle with `FR-8.2` demonstrated in the suite. The shim's token does not come from a shared Keychain access group as planned — D-29 has the measurements that ruled that out.

**Sprint 10 — Model routing.** Per-pad policy, enforcement in `TransformRunner`, the Ollama client, remote credentials, and model-backed transforms appearing in the existing menu. Claims `FR-9.1`–`FR-9.6`. The test with teeth is that a local-only pad makes no outbound connection when the local endpoint is unreachable.

---

## 11. Dependency order, and what could run in parallel

```
Sprint 0 ──▶ Sprint 1 ──▶ Sprint 2 ──▶ Sprint 3 ──▶ Sprint 4 ──▶ Sprint 5 ──▶ [ one month of use ]
                                                                                    │
                                    ┌───────────────────────────────────────────────┤
                                    ▼                                               ▼
                              Sprint 6 (transforms) ──▶ Sprint 7 (provenance)   Sprint 8 ──▶ Sprint 9
                                    │                                               │
                                    └───────────────────┬───────────────────────────┘
                                                        ▼
                                                   Sprint 10 (routing)
```

Sprints 0 through 5 are strictly sequential, and there is no useful parallelism in them for a solo developer. After the MVP, the transform track and the MCP track are independent until Sprint 10, which needs the transform protocol from Sprint 6 and is subject to the same enforcement point reached from the MCP path.

The one genuinely parallel item throughout is documentation: the specification is expected to change as spikes resolve, and per §3.5 that change belongs in the same commit as the code that provoked it.

## 12. Risks to the plan itself

**The coverage gate will be under most pressure in Sprints 2 and 5**, which are the two sprints heaviest in AppKit glue and lightest in what conventionally gets treated as testable logic. The mitigation is structural rather than negotiated, and it is D-11: `MenuModel`, `PanelConfiguration`, `FrameResolver`, `HotKeyAction` and `LaunchPlan` are all pure units, so those two sprints have substantially more testable surface than their subject matter suggests. If a sprint still cannot reach the floor honestly, the response is to find the decision still stranded in a view file and extract it — never to widen the exclusion list, which §3.3's complexity coupling is designed to make difficult anyway.

**The spikes gate two sprints.** S-1 and S-3 gate Sprint 5, S-2 gates Sprint 3, S-4 gates Sprint 8. Each is an afternoon, and each has a stated fallback in specification §18, so none of them can block indefinitely — but running one during its sprint rather than before it is how an afternoon becomes a week.

**The largest risk remains the one the vision document names**, which is accretion into a note-taking application. The plan's control is that `CON-1` through `CON-3` are checkable, that this document adds no requirement not already in `itchy-requirements.md`, and that the month in §9 exists specifically so that the second release is planned against evidence rather than enthusiasm.
