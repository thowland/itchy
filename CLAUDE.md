# Itchy

A menubar-resident scratchpad service for macOS. Fixed set of pads, floating non-activating panels, styled text with images, indefinite retention, and — the differentiating position — pads exposed as a surface that software agents can read from and write to over MCP.

**Status: planning complete, no code yet.** The next work is Sprint 0 in `docs/itchy-implementation-plan.md`.

## Documents, in precedence order

Read these before proposing anything. Where two disagree, the earlier one governs, except that the architecture document governs the specification on matters of implementation.

| Document | Answers |
|---|---|
| `docs/itchy-vision.md` | Why this exists, and what it must never become |
| `docs/itchy-architecture.md` | The shape: layers, storage, build order |
| `docs/itchy-requirements.md` | What must be true — numbered, with acceptance criteria |
| `docs/itchy-specification.md` | How it is assembled — decisions D-1…D-11, seams, formats |
| `docs/itchy-implementation-plan.md` | In what order, and under what gate |
| `docs/itchy-architecture-diagram.html` | The system in one view, including external collaborators |

Cite requirement identifiers (`FR-4.2`, `NFR-1.1`, `CON-3`, `D-11`) in commits, comments, and discussion. They are permanent; a withdrawn requirement is marked withdrawn in place and its number is never reused.

## The governing constraint

Itchy is for transient content. Before adding anything, ask whether the feature serves transient content or permanent content; if permanent, decline it (`CON-3`). No document library, folder hierarchy, tagging, or corpus-wide search (`CON-1`). No save, title, or filing prompts — pad deletion is the single exception (`CON-2`, `FR-2.6`). No cloud sync, no telemetry, no chat panel.

The largest risk to this project is not technical. It is accretion into the note-taking application it was built to avoid.

## Architectural rules that must not decay

Each is enforced by a check in `Scripts/arch-lint.sh`, and each exists because it is the kind of rule that erodes silently.

1. **The store is the only component that touches disk** (`CON-4`). No `FileManager` outside `ItchyCore/Store`.
2. **`ItchyCore` links no UI framework** (D-2, `NFR-4.3`). An `import AppKit` there must fail the build.
3. **One call site for `Transform.apply`** (specification §12), so the menu path and the MCP path are subject to the same routing policy rather than two policies that are meant to agree.
4. **Coverage exclusions pass the complexity cap** (D-11, §15.3). Exclusion is earned by triviality.

## Testability doctrine (D-11)

View files translate and apply; they do not decide. Every decision that would otherwise sit in a view body, window controller, `NSViewRepresentable`, or delegate stub is extracted into a pure value-typed unit — `*Model` for a projection, `*Plan` / `*Policy` / `*Resolver` for a decision, `*Codec` for a conversion. Decisions return enumerations, never Booleans or Boolean pairs. No function both decides and performs.

When something feels hard to test, the question is not "how do I test this view" but "what decision is stranded inside this view". Specification §15.2 lists the ones already found; adding another means adding a row in the same commit.

## Sprint exit gate

No sprint exits until all four hold, and they are cumulative — earlier sprints' tests must still pass:

- **G1** no lint failures (`swiftlint --strict`, `swift-format lint --strict`, `arch-lint`)
- **G2** no failing tests anywhere
- **G3** line coverage ≥ 80% over the denominator in plan §3.3
- **G4** every requirement the sprint claims has its acceptance criterion demonstrated

An obsolete test may be deleted, recorded with the requirement that changed — but never in a way that drops coverage below the floor.

## Commands

```
make gate        # the sprint exit gate: lint, arch-lint, test, coverage (G1-G3)
make open        # regenerate Itchy.xcodeproj and open it in Xcode
make test        # packages and app target
make coverage    # coverage against the 80% floor; COVERAGE_REPORT=1 for per-file
make verify-gate # prove the gates fail when they should
make format      # apply swift-format in place
```

`Itchy.xcodeproj` is generated from `project.yml` and is not committed (D-12).
`make project` regenerates it, and `test`, `coverage` and `app` do so first.
A file created in the editor is picked up on the next generate; adding it inside
Xcode does not add it to `project.yml`.

## Conventions

- Swift 6.3, strict concurrency from the first commit (D-1). The store is an actor; the view layer is `@MainActor`.
- `swiftlint` from Homebrew; `swift-format` from the Xcode toolchain via `xcrun swift-format`, never from Homebrew (D-1).
- Swift Testing for new tests; XCTest only where its machinery is required; XCUITest for the UI smoke suite.
- `xcodegen` from Homebrew generates the project (D-12). It is a development tool, not a shipped dependency, so it sits outside D-4.
- No third-party dependencies in R1 or R2 (D-4). The question reopens at R3 for the MCP stack only (D-5).
- Documents are written in British spelling and in continuous prose with reasoning attached. A decision recorded without its reasoning cannot be reversed safely later.
- A decision taken during implementation goes in `docs/decisions/`, numbered from D-12. If it contradicts the specification, update the specification in the same commit.

## Unresolved before coding

Four framework behaviours are marked **[VERIFY]** in the specification and gate specific sprints (§18): Carbon `RegisterEventHotKey` on macOS 26 (S-1, Sprint 5), `TextEditor` attachment rendering (S-2, Sprint 3), `.metadata_never_index` efficacy (S-3, Sprint 5), MCP Swift SDK fit for a long-running host (S-4, Sprint 8). Run each before its sprint opens, not during it.
