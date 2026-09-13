# Itchy — Technical Specification

*Draft, September 2026*

## 0. How to read this document

This is the build document. It sits below `itchy-vision.md` (why), `itchy-architecture.md` (shape) and `itchy-requirements.md` (what must be true), and it exists to answer the remaining question, which is how the thing is actually assembled. Where it restates a decision from the architecture document it does so in order to make it concrete; where it takes a new decision it records it in §2 with the reasoning attached, so that a decision can be reversed later by someone who can see why it was taken.

Requirement identifiers in the form `FR-4.2` refer to `itchy-requirements.md` and are the acceptance authority. Code in this document is illustrative of shape and naming rather than final; it is written as Swift because the type signatures are the clearest way to state an interface, not because the implementation is expected to match character for character.

Two classes of statement need distinguishing. Most of this document is settled design. A small number of points depended on framework behaviour unverified on macOS 26 and were marked **[VERIFY]**. All four spikes are now resolved; §18 records each outcome, and D-15 through D-17 carry the detail. Those marks should be cleared before the relevant milestone begins, not discovered during it.

## 1. Deliverables

| Artefact | Description |
|---|---|
| `Itchy.app` | The application bundle: accessory app, no Dock icon, signed, hardened, notarised |
| `itchy-mcp` | Small stdio shim binary, embedded in the bundle's `Contents/MacOS`, proxying stdio MCP to the loopback endpoint |
| `itchyctl` | Development-only command-line harness exercising the core and store without the UI. Not shipped |
| Test suites | Core unit tests, store integration tests with fault injection, a small UI smoke suite, and a performance suite for `NFR-1.1` |

## 2. Decisions taken in this document

Each carries an identifier so that later documents and commit messages can cite it.

**D-1 — Swift 6.3 with strict concurrency checking, no Objective-C of our own.**
The window and text layers are AppKit, but they are consumed from Swift. Strict concurrency is enabled from the first commit rather than adopted later, because the store is an actor and the text system is main-actor-bound, and that boundary is the one place in the application where concurrency mistakes are plausible. Retrofitting `Sendable` conformance across a working codebase is worse than living with the compiler from the start.

The toolchain is whatever Xcode provides, and the formatter comes from it rather than from Homebrew: `swift-format` ships inside the Xcode toolchain and is invoked as `xcrun swift-format`. A separately installed formatter can drift from the compiler that builds the code and then reformat against a grammar the toolchain does not have, which is a class of argument not worth having. `swiftlint` has no toolchain equivalent and is installed from Homebrew.

**D-2 — Local Swift packages for Core and Services, an Xcode app target for Platform and Interface.**
`NFR-4.3` requires the core to be testable without linking a UI framework, and the cheapest way to guarantee that rather than merely intend it is to make it structurally impossible: `ItchyCore` is a package target that does not depend on AppKit, so an accidental `import AppKit` in the store fails to build. The app target depends on the packages; the packages depend on nothing of ours.

**D-3 — Swift Testing for new tests, XCTest only where a test needs XCTest-specific machinery.**
Parameterised cases matter here because the transform suite and the file-format suite are both naturally table-driven, and the store's fault-injection tests read far better as parameterised cases than as twenty near-identical methods. The UI smoke suite stays XCUITest.

**D-4 — No third-party dependencies in R1 or R2.**
There is nothing in the first two releases that a dependency would meaningfully shorten, and an unsandboxed, notarised, security-sensitive application with no dependency graph is a materially easier thing to reason about. The question reopens at R3, where an HTTP and MCP stack is genuinely non-trivial; see D-5.

**D-5 — The MCP transport decision is deferred to a spike, with a stated default.**
The default position is the official MCP Swift SDK if its HTTP server transport fits a long-running host process that owns the state, since that keeps protocol conformance out of our hands. The fallback is Hummingbird for HTTP with a hand-written MCP protocol layer over it. Hand-rolling HTTP on `NWListener` is explicitly rejected despite D-4: the surface is small but HTTP framing, chunked bodies and connection lifetime are exactly the sort of thing that is 90% correct for a year and then silently wrong. Spike S-4 in §18 settles this before milestone M7 opens.

**D-6 — Carbon `RegisterEventHotKey` for the global hotkey, not a global event monitor.**
`NSEvent.addGlobalMonitorForEvents` requires the Accessibility permission, which means a system prompt, a trip to System Settings, and a support surface, all to read one key combination. `RegisterEventHotKey` requires no permission and has been the correct answer for this for twenty years. It is a C API with an untidy callback shape, which is a contained cost paid once in one file. **[VERIFY]** that it remains functional on macOS 26.

**D-7 — Storage is a directory per pad, written atomically, with a schema version in every JSON file.**
Versioning every file from the first write costs a line and buys the ability to change the metadata shape later without guessing. `FR-5.7` requires unknown fields to survive a round trip, which rules out plain `Codable` synthesis over a fixed struct and is addressed in §6.4.

**D-8 — The shadow text file is written by the store, inside the same atomic save, for every pad.**
Per `FR-5.4`. The store extracts the string and writes both files as one operation, so the two cannot diverge. A shadow file present without its content file, or vice versa, is treated as a fault.

**D-9 — Undo lives on the text view, and the store defers to it.**
The store does not maintain its own undo stack. Transforms and MCP writes register their inverse with the pad's `NSTextView.undoManager` inside an undo grouping, which is what makes `FR-6.5` and `FR-8.8` the same mechanism rather than two. The consequence is that a write to a pad whose panel is closed has no undo, which is accepted: §11.7 specifies that such a write is instead recorded as an external-write event on the pad.

**D-10 — Spotlight exclusion. Superseded by D-16.**
D-10 specified an empty `.metadata_never_index` file in the support directory. Spike S-3 showed that has no effect on a directory — it is a volume-root marker — and that a directory named `*.noindex` does work. Pads therefore live in `pads.noindex`, and nothing is written to mark them. See D-16.

**D-11 — Decisions live in value-typed code; view files translate and apply.**
No conditional in a view body, window controller, `NSViewRepresentable`, or app-delegate stub. Every decision those files would otherwise make is extracted into a pure unit named by the convention in §15.1, and the exclusion list that keeps boilerplate out of the coverage denominator is coupled to a complexity cap so that exclusion is earned by triviality rather than claimed. §15 is the full statement, including the seam-by-seam table. This is taken as a decision rather than left as good practice because it is the difference between a coverage floor that measures something and one that measures whether files were excluded.

## 3. Repository and module layout

```
itchy/
├── Itchy.xcodeproj
├── App/                          # app target: Platform + Interface
│   ├── ItchyApp.swift            # @main, activation policy, MenuBarExtra
│   ├── Platform/
│   │   ├── StatusItemController.swift
│   │   ├── PadPanel.swift        # NSPanel subclass
│   │   ├── PadWindowController.swift
│   │   ├── PadWindowRegistry.swift
│   │   ├── HotKey.swift          # RegisterEventHotKey wrapper
│   │   ├── LoginItem.swift       # SMAppService
│   │   └── TextViewBridge/
│   │       ├── PadTextView.swift          # NSTextView subclass
│   │       ├── PadTextEditor.swift        # NSViewRepresentable
│   │       ├── PadTextCoordinator.swift   # NSTextViewDelegate
│   │       └── PasteInterceptor.swift
│   └── Interface/
│       ├── PadView.swift
│       ├── PadStatusBar.swift    # name, mode, exposure, routing
│       ├── ProvenanceList.swift
│       ├── TransformMenu.swift
│       └── Settings/
├── Packages/
│   ├── ItchyCore/                # no AppKit, no SwiftUI (D-2)
│   │   └── Sources/ItchyCore/
│   │       ├── Model/            # Pad, PadID, PadMode, PadMetadata, …
│   │       ├── Store/            # PadStore, PadStorage, SaveScheduler
│   │       ├── Transform/        # Transform protocol, registry
│   │       └── Support/          # atomic write, JSON, errors, clock
│   └── ItchyServices/            # depends on ItchyCore
│       └── Sources/ItchyServices/
│           ├── Transforms/       # deterministic implementations
│           ├── MCP/              # server, tool handlers, auth
│           └── Models/           # local + remote model clients
├── Shim/                         # itchy-mcp stdio proxy
├── Harness/                      # itchyctl
├── Tests/
└── docs/
```

The one rule that keeps the layer boundary real: `ItchyCore` imports Foundation and nothing else of consequence, `ItchyServices` imports `ItchyCore`, and `App` imports both. Nothing points the other way. A service that needs to affect the interface does so by mutating the store, which the interface observes.

## 4. Concurrency model

Three isolation domains, and the interesting design work is in keeping them from leaking into each other.

**The store is an actor.** `PadStore` owns all pad state and is the sole owner of disk access, per `CON-4`. Every mutation is an `await` from the caller's perspective. Its internal save scheduler is an actor-isolated structure, so debounce timers cannot race a forced save.

**The view layer is `@MainActor`.** Panels, text views, the status item and all SwiftUI views. The text view is the authoritative live copy of a pad's content while its panel is open, which is the one place the model is not simply owned by the store; §5.4 states how that is reconciled.

**Services are unisolated and re-enter the store.** Transforms are `async` functions taking a value and returning a value. The MCP server runs its own task tree and calls into the store exactly as a view does.

Observation flows one way. The store publishes changes through an `AsyncStream` of `PadChange` events plus an `@Observable` projection for SwiftUI:

```swift
public enum PadChange: Sendable {
    case padsReordered([PadID])
    case padAdded(PadID)
    case padRemoved(PadID)
    case metadataChanged(PadID)
    case contentChangedExternally(PadID, origin: WriteOrigin)
    case sizeThresholdCrossed(PadID, bytes: Int)
    case storeFault(PadID?, PadStoreFault)
}

public enum WriteOrigin: Sendable, Equatable {
    case user
    case transform(String)
    case mcp(client: String?)
}
```

`contentChangedExternally` deliberately carries no payload. A panel receiving it reloads from the store, which keeps the reconciliation logic in one place rather than duplicating merge rules into the event.

## 5. Core domain model

### 5.1 Types

```swift
public struct PadID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: UUID              // directory name on disk
}

public enum PadMode: String, Sendable, Codable {
    case styled
    case plain
}

public enum RoutingPolicy: String, Sendable, Codable {
    case localOnly          // default (FR-9.1)
    case remotePermitted
    case askEachTime
}

public struct PadFrame: Sendable, Codable, Equatable {
    public var x, y, width, height: Double
    public var displayID: UInt32?          // for restore heuristics, §8.5
}

public struct ProvenanceEntry: Sendable, Codable, Identifiable {
    public let id: UUID
    public let arrived: Date
    public let sourceBundleID: String?
    public let sourceAppName: String?
    public let sourceURL: URL?
    public let approximateRange: Range<Int>?   // FR-7.4: approximate, never authoritative
    public let byteCount: Int
    public let kind: Kind                      // text, styledText, image, file
}

public struct PadMetadata: Sendable, Codable, Equatable {
    public var schemaVersion: Int
    public var id: PadID
    public var name: String
    public var mode: PadMode
    public var created: Date
    public var modified: Date
    public var frame: PadFrame?
    public var isPinned: Bool
    public var provenance: [ProvenanceEntry]
    public var isExposedToMCP: Bool            // R3; default false (FR-8.7)
    public var routingPolicy: RoutingPolicy    // R4; default .localOnly
    public var lastOpened: Date?               // drives FR-1.4
    public var externalWriteMarker: ExternalWriteMarker?   // R3, §11.7
}
```

`PadContent` is the styled payload and is the one type that cannot live in `ItchyCore` as a rendered value, since `NSAttributedString` is AppKit-adjacent. The core therefore handles content as opaque data plus its extracted plain text, and the conversion to and from `NSAttributedString` happens at the platform boundary:

```swift
public struct PadContent: Sendable, Equatable {
    /// RTFD bundle contents keyed by filename; "TXT.rtf" plus attachments.
    public var bundle: [String: Data]   // authoritative (FR-5.3)
    public var plainText: String        // derived; written to shadow file (FR-5.4)
}
```

The bundle is a filename-to-bytes map rather than opaque `Data` (D-13). An RTFD
bundle is a directory, and `FR-5.3` requires that what Itchy writes opens in
TextEdit — which a flat packed representation does not satisfy. A map is
`Sendable` and `Equatable`, which opaque `Data` is too but `FileWrapper` is not.

This is a deliberate inversion of the obvious design. It would be more natural for the store to hold an `NSAttributedString`, and it would also mean the store links AppKit and D-2 collapses. Serialising at the boundary costs one conversion per load and per save, both of which are already off the keystroke path.

### 5.2 Pad count bounds

```swift
public enum PadBounds {
    public static let defaultCount = 9
    public static let hardCeiling = 20     // FR-2.1; not configurable
    public static func clamp(_ requested: Int) -> Int {
        min(max(requested, 1), hardCeiling)
    }
}
```

The ceiling is enforced in three places, and all three are required rather than defensive: at the settings control, at the point of reading the stored preference (a value above the ceiling is clamped and written back), and at `createPad`. `FR-2.1`'s acceptance criterion specifically includes a hand-edited stored value, so the read-path clamp is a requirement and not a nicety.

### 5.3 Store interface

```swift
public protocol PadStoring: Actor {
    var pads: [PadMetadata] { get }                       // in slot order
    var changes: AsyncStream<PadChange> { get }

    func content(of id: PadID) async throws -> PadContent
    func createPad(name: String?) async throws -> PadMetadata
    func deletePad(_ id: PadID) async throws
    func rename(_ id: PadID, to name: String) async throws
    func setMode(_ id: PadID, to mode: PadMode) async throws
    func reorder(to order: [PadID]) async throws
    func setPinned(_ id: PadID, _ pinned: Bool) async throws
    func setFrame(_ id: PadID, _ frame: PadFrame) async

    // Content mutation; every path funnels here (CON-4)
    func stage(_ content: PadContent, for id: PadID, origin: WriteOrigin) async
    func flush(_ id: PadID) async throws
    func flushAll() async throws

    func appendProvenance(_ entry: ProvenanceEntry, to id: PadID) async
    func clearProvenance(of id: PadID) async
}
```

`stage` is the hot path and is intentionally non-throwing and non-awaited-on-result: the text view calls it on every change notification and must not be able to block on I/O or handle an error inline. It records the new content in memory, marks the pad dirty, and resets the debounce. `flush` is what actually writes, and is called by the scheduler, by panel close, by termination, and by resignation of active status (`FR-5.5`).

### 5.4 Reconciling the text view with the store

While a panel is open, its `NSTextView`'s text storage is the live copy and the store holds the last staged snapshot. This is the only place in the design with two copies of anything, so the rules are stated explicitly:

1. The text view is authoritative for a pad whose panel is open, for user edits only.
2. Every user edit is staged to the store within one debounce interval, so the store is never more than that far behind.
3. A write from any other origin — a transform, an MCP client — is applied *to the text view* when the panel is open, never to the store behind the view's back. The service calls a main-actor applier that the panel registers with the registry on open.
4. If the panel is closed, the same write is applied directly to the store, and the pad is marked with an external-write marker so the user learns about it when they next open the pad.

Rule three is what makes `FR-8.8` and `FR-6.5` fall out of the same code, and rule four is the honest consequence of D-9.

## 6. Storage layer

### 6.1 On-disk layout

```
~/Library/Application Support/Itchy/
├── index.json                     # slot order + schema version
├── settings.json                  # non-secret preferences
└── pads.noindex/                  # excluded from Spotlight — D-16 / NFR-3.4
    └── <uuid>/
        ├── content.rtfd/          # authoritative styled content (a file wrapper)
        ├── content.txt            # shadow, derived, never read (FR-5.4)
        └── meta.json
```

`content.rtfd` is a directory, being an RTF file wrapper with its attachments alongside. This matters for the atomic write algorithm, because replacing a directory atomically is a different operation from replacing a file, and §6.3 handles it.

### 6.2 File formats

`index.json`:

```json
{
  "schemaVersion": 1,
  "order": ["A1B2…", "C3D4…"],
  "lastOpened": "A1B2…"
}
```

`meta.json`:

```json
{
  "schemaVersion": 1,
  "id": "A1B2C3D4-…",
  "name": "scratch",
  "mode": "styled",
  "created": "2026-09-12T10:04:11Z",
  "modified": "2026-09-12T14:22:03Z",
  "frame": { "x": 1200, "y": 400, "width": 420, "height": 560, "displayID": 1 },
  "isPinned": false,
  "provenance": [
    {
      "id": "…", "arrived": "2026-09-12T14:21:58Z",
      "sourceBundleID": "com.apple.Safari",
      "sourceAppName": "Safari",
      "sourceURL": "https://example.invalid/orders/88121",
      "approximateRange": { "lowerBound": 0, "upperBound": 412 },
      "byteCount": 412, "kind": "styledText"
    }
  ],
  "isExposedToMCP": false,
  "routingPolicy": "localOnly",
  "lastOpened": "2026-09-12T14:20:00Z"
}
```

Dates are ISO 8601 with fractional seconds omitted, encoded via a fixed `JSONEncoder` configuration held in one place so that no two call sites can disagree. Keys are sorted and output is pretty-printed, on the grounds that a file which is going to be read by people and by agents should diff cleanly and the cost is nil at this scale.

### 6.3 Atomic write algorithm

`FR-5.6` and `NFR-2.1` turn on this being right, so it is specified as a procedure rather than described.

For a single file:

1. Create `.<name>.<pid>.<counter>.tmp` in the *same directory* as the target, so that the replacement is within one filesystem.
2. Write the full contents and `fsync` the file descriptor before closing. Without the sync, the replacement can be durable while the contents are not, which is the failure that produces a zero-length pad after a power loss.
3. `FileManager.replaceItemAt(_:withItemAt:)`, which performs an exchange and removes the temporary on success.
4. On any failure, unlink the temporary and surface the error; the target is untouched by construction.

For `content.rtfd`, which is a directory: write the whole wrapper to a sibling temporary directory, then `replaceItemAt` the directory. The same call handles directories, and the same guarantee applies.

A pad save writes `content.rtfd`, `content.txt` and `meta.json`, which is three replacements and therefore not atomic as a set. Making it atomic as a set would mean a per-pad staging directory and a directory swap, and it is not worth it: the failure mode of a partial set is a pad whose metadata timestamp disagrees with its content, and the ordering below reduces that to a cosmetic inconsistency.

Ordering within a save: content first, then shadow, then metadata last. Metadata is written last because `modified` is the thing that claims the save happened, and a metadata write that lands without its content would be the one genuinely misleading outcome.

Startup runs a sweep for orphaned `.tmp` entries older than one hour and removes them.

### 6.4 Unknown-field preservation

`FR-5.7` requires an unknown field added by hand to survive the next save, which synthesised `Codable` does not provide, since decoding to a struct discards what it does not know. The approach is to decode twice: once into `PadMetadata`, and once into a `[String: JSONValue]` retained alongside it. On encode, the struct's fields are written over a copy of that dictionary, so known fields take the struct's value and unknown ones pass through untouched.

```swift
struct PreservingMetadata {
    var metadata: PadMetadata
    var unknown: [String: JSONValue]   // keys not in PadMetadata's CodingKeys
}
```

This is more machinery than it looks worth for a personal application, and the reason it is worth it is the direction the product is going: the data model is intended to be addressable by other software, and a store that silently deletes fields it does not recognise is hostile to exactly that.

### 6.5 Migration

Each JSON file carries `schemaVersion`. On read, a version below current is passed through an ordered list of migration closures; a version above current causes that pad to be reported unreadable rather than guessed at, per `FR-5.8`. Migrations are pure functions over `[String: JSONValue]` and are unit tested against captured fixtures of each historical shape. There are no migrations at version 1; the machinery ships empty because adding it later means writing migrations for files that predate the versioning.

### 6.6 Save scheduler

```swift
actor SaveScheduler {
    private var pending: [PadID: Task<Void, Never>] = [:]
    static let debounce: Duration = .milliseconds(750)      // FR-5.5
}
```

Staging a pad cancels its pending task and starts a new one that sleeps for the debounce and then flushes. Forced flush paths cancel the pending task and flush inline. Cancellation is checked after the sleep, so a cancelled debounce never writes.

Three force points are required (`FR-5.5`) and a fourth is worth adding: panel close, `applicationWillTerminate`, `applicationWillResignActive`, and — the addition — on receiving `NSWorkspace.willSleepNotification`. A laptop closing its lid is the common case that resembles a crash, and it is one notification.

Termination needs care, because `applicationWillTerminate` is not an async context and the store is an actor. The flush on termination is performed by blocking the main thread on a semaphore released by the flush task, with a hard timeout of two seconds after which termination proceeds regardless. Blocking the main thread is normally indefensible; at termination, with a bounded timeout, losing a pad is worse.

### 6.7 Fault taxonomy

```swift
public enum PadStoreFault: Error, Sendable {
    case metadataUnreadable(PadID, underlying: String)
    case metadataSchemaTooNew(PadID, found: Int, supported: Int)
    case contentUnreadable(PadID, underlying: String)
    case contentMissing(PadID)
    case shadowDesynchronised(PadID)
    case indexUnreadable(underlying: String)
    case writeFailed(PadID, underlying: String)
    case padLimitReached(limit: Int)
    case diskSpaceExhausted
}
```

`NFR-2.2` requires a fault affecting one pad not to prevent launch. Concretely: `indexUnreadable` causes the index to be rebuilt by enumerating `pads/` in creation order; any per-pad fault causes that pad to be listed in a faulted state, selectable in the menubar, and opening it shows the fault and offers to reveal the directory in Finder rather than an empty editable pad. An empty editable pad over unreadable content is the one behaviour that could destroy the content on the next save, and is therefore prohibited.

## 7. Transform layer

### 7.1 Protocol

```swift
public protocol Transform: Sendable {
    var id: String { get }                     // stable; used by MCP and telemetry-free logging
    var title: String { get }
    var requiresNetwork: Bool { get }          // gates against RoutingPolicy (R4)
    func applicability(to input: TransformInput) -> Applicability
    func apply(to input: TransformInput) async throws -> TransformOutput
}

public enum Applicability: Sendable {
    case applicable
    case notApplicable(reason: String)
}

public struct TransformInput: Sendable {
    public let plainText: String
    public let rtfd: Data?                    // present only for transforms that need styling
    public let scope: Scope                   // .selection(Range<Int>) or .wholePad
    public let padMode: PadMode
}

public enum TransformOutput: Sendable {
    case plainText(String)
    case styled(Data)                          // rtfd
    case report(String)                        // e.g. a diff; shown, not applied
}
```

`apply` is `async` throughout even though every R1 and R2 transform returns immediately, per `FR-6.1`. The point is that the R4 model-backed transforms are the same type, appearing in the same menu, distinguished only by progress and cancellation — and if the protocol were synchronous now, that would be a breaking change later at exactly the moment we are least inclined to make one.

`report` exists so that a comparison transform (`FR-6.7`) has somewhere to put its output without mutating a pad.

### 7.2 The deterministic set

| `id` | Title | Input predicate | Notes |
|---|---|---|---|
| `flatten` | Flatten styling | styled pad | Shares its implementation with the mode switch (`FR-4.5`) |
| `case.upper` / `case.lower` / `case.title` | Change case | any text | Title case uses a conservative rule, not a word list |
| `json.pretty` | Pretty-print JSON | parses as JSON | Two-space indent, keys preserved in order |
| `json.minify` | Minify JSON | parses as JSON | |
| `base64.encode` | Encode base64 | any text | UTF-8, no line breaks |
| `base64.decode` | Decode base64 | valid base64 *and* decodes to valid UTF-8 | Both conditions, or the transform offers itself and then produces mojibake |
| `url.encode` / `url.decode` | URL component | any text / valid percent-encoding | Component encoding, not whole-URL |
| `whitespace.trim` | Trim whitespace | any text | Trailing per line plus leading/trailing overall |
| `lines.sort` | Sort lines | ≥2 lines | Localised comparison, stable, ascending |
| `pads.diff` | Compare with pad… | any | Returns `.report`; `FR-6.7`, MAY |

The applicability predicates are the part with actual content, per `FR-6.3`. Predicates run on every menu open against the current selection, so each must be cheap; `json.pretty` parses to decide, which is acceptable at a few megabytes but is capped — above 256 KB the predicate assumes applicable rather than parsing, and a parse failure at apply time reports cleanly under `FR-6.6`.

### 7.3 Application path

A transform invocation, from menu selection to settled state:

1. The panel gathers `TransformInput` from the text view, using the selection if non-empty (`FR-6.4`).
2. `TransformRunner` checks applicability, then — from R4 — checks `requiresNetwork` against the pad's `RoutingPolicy` (§12), refusing before any work is done.
3. `apply` runs. If it has not returned within 150 ms, the panel shows progress and a cancel affordance; below that threshold nothing is shown, since flashing a spinner for a synchronous operation is worse than showing nothing.
4. The output is applied to the text view inside `undoManager.beginUndoGrouping()` / `endUndoGrouping()`, with the action name set to the transform's title, so that the Edit menu reads "Undo Pretty-print JSON" (`FR-6.5`).
5. The text change notification stages to the store as any edit would. The transform does not write to disk itself; it has no more disk access than a keystroke does.
6. On throw, nothing is applied and the reason is surfaced (`FR-6.6`).

Step four is the load-bearing one. Every mutation that is not a keystroke — transforms, mode flattening, MCP writes, emptying a pad — goes through the same grouped applier, which is why there is one undo story rather than four.

## 8. Platform layer

### 8.1 Activation policy and menubar

`LSUIElement` is set to true in `Info.plist`, and `NSApp.setActivationPolicy(.accessory)` is asserted in `applicationDidFinishLaunching` as a belt-and-braces measure for the case of a stale plist in a development build.

`MenuBarExtra` in `.menu` style is the starting implementation per the architecture document, with `StatusItemController` as a thin seam: the menu's contents are computed from `store.pads` in both implementations, so the AppKit fallback replaces one file. The trigger for switching is named in `FR-1.2`'s acceptance criterion — a rename that fails to appear — and the fallback is written the first time that is observed rather than kept warm in advance.

Menu contents:

```
scratch                        ⌃⌥1      ← pads in slot order
json dump                      ⌃⌥2
notes ⚠ 48 MB                  ⌃⌥3      ← size marker, FR-5.9
⋯
New Pad                        ⌃⌥N
Pads…                                    ← reorder, rename, delete
Settings…                      ⌘,
Quit Itchy                     ⌘Q
```

### 8.2 The panel

`PadPanel: NSPanel`, configured exactly as follows. The table is the specification; a deviation from it is a bug.

| Property | Value | Requirement |
|---|---|---|
| `styleMask` | `[.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel]` | `FR-3.1`, `FR-3.7` |
| `isFloatingPanel` | `true` | `FR-3.1` |
| `level` | `.floating` | `FR-3.1` |
| `hidesOnDeactivate` | `false` | `FR-3.1` |
| `collectionBehavior` | `[.canJoinAllSpaces, .fullScreenAuxiliary]` | `FR-3.1` |
| `isReleasedWhenClosed` | `false` | Controller owns lifetime |
| `animationBehavior` | `.utilityWindow` | |
| `canBecomeKey` | overridden `true` | **`FR-3.2`** |
| `canBecomeMain` | overridden `false` | Keeps Itchy from becoming the active app |

The `canBecomeKey` override is the single detail most likely to cost an afternoon, because a non-activating panel does not become key by default and the symptom is a panel that appears entirely correct and silently discards every keystroke. `FR-3.2` exists as a separate requirement for this reason, and there is a test for it.

Content is hosted in `NSHostingView`. The minimum size is 240×160; below that the status bar in `PadStatusBar` stops being legible and there is no reason to permit it.

### 8.3 Window registry

```swift
@MainActor final class PadWindowRegistry {
    private var controllers: [PadID: PadWindowController] = [:]
    private var appliers: [PadID: (TransformOutput, String) -> Void] = [:]

    func show(_ id: PadID)            // FR-3.3: existing panel forward, never a second
    func close(_ id: PadID)
    func applier(for id: PadID) -> ((TransformOutput, String) -> Void)?
}
```

The `appliers` dictionary is how §5.4 rule three is realised: a panel registers a main-actor closure on open and removes it on close, and a service wanting to write to a pad asks the registry whether one exists. If it does, the write goes through the text view and is undoable; if not, the write goes to the store and is marked. The service does not know or care which happened, beyond what it reports back.

### 8.4 Frame persistence

`windowDidMove` and `windowDidResize` both call `store.setFrame`, debounced at 200 ms to avoid staging on every frame of a drag. Frame changes do not mark content dirty and do not trigger a content write; `setFrame` is deliberately the one store method that is neither `throws` nor part of the content save path.

`setFrameAutosaveName` is explicitly not used, per the architecture document: the frame belongs in the pad record so that it travels with the pad and is readable by the same machinery that reads everything else.

### 8.5 Frame restoration

`FR-3.4` requires that a frame stored for a detached display does not open offscreen, so restoration is an algorithm rather than an assignment:

1. If the stored frame intersects the visible frame of any current screen by at least 120×80 points, use it unchanged.
2. Otherwise, if `displayID` matches a current screen, clamp the frame into that screen's visible frame.
3. Otherwise, place the panel on the screen containing the mouse, preserving size, positioned at the same proportional offset within the visible frame as the stored frame had within its own.
4. If no stored frame exists, cascade from the top-right of the screen containing the mouse, offset by the number of open panels, so that opening several pads does not stack them exactly.

Rule three rather than "centre it" is worth the extra few lines: a user who keeps a pad at the bottom-right of a large display finds it bottom-right on the laptop screen too, which is what they meant by putting it there.

### 8.6 Global hotkey

`HotKey.swift` wraps `RegisterEventHotKey` per D-6, with the handler installed once via `InstallEventHandler` on `kEventClassKeyboard` / `kEventHotKeyPressed`. The default binding is ⌃⌥Space, recorded in settings as a key code plus modifier mask.

The handler's behaviour is specified by `FR-1.4`, and the toggle case needs stating precisely because "already frontmost and focused" is ambiguous for a non-activating panel:

```
on hotkey:
    target ← pad with greatest lastOpened, else first pad in slot order
    if target's panel exists AND is visible AND is the key window:
        close the panel        (which forces a flush, FR-3.5)
    else:
        show the panel, order front, make key
        set target.lastOpened = now
```

Optional per-pad chords (⌃⌥1 … ⌃⌥9) are registered through the same wrapper. These were not selected as a first-release requirement and are therefore implemented as menu key equivalents in R1, which cost nothing, and promoted to global hot keys only if the menu equivalents prove insufficient.

### 8.7 Cold-launch budget

`NFR-1.1` sets 250 ms at the 95th percentile from hotkey to typeable pad, and `FR-1.6` forbids reading content at launch. The consequence is a launch sequence that reads only `index.json` and each `meta.json`, which is a few kilobytes:

1. Assert activation policy, install the hotkey, create the status item.
2. Read index and metadata; publish the pad list. The menubar is live at this point.
3. Asynchronously, open panels for pinned pads (`FR-2.7`).
4. Content for any pad is read on first open of its panel, and then cached in the store for the lifetime of the process.

Instrumentation is `OSSignposter` intervals named `hotkey→visible`, `panel.create`, `content.load` and `firstResponder`, which is what the performance suite in §14.5 measures rather than a stopwatch.

## 9. Text layer

### 9.1 Why AppKit, restated as a constraint

SwiftUI's `TextEditor` on macOS 26 handles styled text through `AttributedString` and would be the right choice for styling alone. It does not render text attachments: an attributed string loaded from RTFD with an embedded image reports the attachment present and draws nothing, while `NSTextView` displays it correctly. Pasted screenshots are `FR-4.2`, a first-release requirement, so the decision is settled and is not to be revisited on the grounds that the SwiftUI code would be shorter. Verified by spike S-2 and recorded in D-15: the behaviour is unchanged, and the evidence is in `docs/spike-s2-texteditor-attachments.png`.

### 9.2 Bridge structure

`PadTextEditor: NSViewRepresentable` wraps a scroll view containing `PadTextView: NSTextView`, with `PadTextCoordinator` as delegate. What arrives free with this decision, and is therefore specified as "do not reimplement": image paste and drop, spell checking, the system find bar, the standard Edit and Format responder chain, and `pasteAsPlainText:` — which satisfies `FR-4.6` with no implementation of ours at all.

Configuration per mode:

| | styled | plain |
|---|---|---|
| `isRichText` | `true` | `false` |
| `allowsImageEditing` | `true` | `false` |
| `importsGraphics` | `true` | `false` |
| `typingAttributes` | inherited from insertion point | pinned to the editor font (D-19) |
| `isAutomaticQuoteSubstitutionEnabled` | user default | `false` |
| `isAutomaticDashSubstitutionEnabled` | user default | `false` |

The substitution settings are off in plain mode without being configurable, and this is a judgement worth defending: a plain pad's purpose is holding a JSON fragment or a SQL clause, and smart quotes silently corrupting a string literal is the single most annoying thing a scratchpad can do.

### 9.3 Change notification and staging

`textDidChange` builds a `PadContent` and calls `store.stage`. Building it means serialising the text storage to RTFD, which is more expensive than a keystroke warrants at every keystroke, so the coordinator debounces the *serialisation* at 120 ms and the store debounces the *write* at 750 ms. Two debounces sounds like one too many; the reason is that the first protects `NFR-1.2` (typing latency in a large pad) and the second protects disk churn, and collapsing them would mean either serialising on every keystroke or leaving the store up to 750 ms stale, the latter of which weakens the crash guarantee in `NFR-2.1`.

### 9.4 Paste and drop pipeline

Every incoming paste or drop passes through one interceptor, because both provenance capture (`FR-7.1`) and image downsampling (`FR-4.3`) hook here and neither should have its own entry point.

```
1. Capture NSWorkspace.shared.frontmostApplication BEFORE handling
   — see §9.5; this is the ordering that makes provenance correct
2. Read pasteboard: public.url, public.file-url, WebURLsWithTitles,
   public.rtfd, public.rtf, public.html, public.tiff/png, public.utf8-plain-text
3. If plain mode: reduce to plain text, discard attachments
4. If styled mode: prefer rtfd > rtf > html > image > plain text
5. For each image: if max dimension > 1600 px, downsample to 1600 px
   preserving aspect, re-encode as PNG, replace the attachment (FR-4.3)
6. Insert via the grouped applier so one paste is one undo
7. Emit a ProvenanceEntry to the store (R2) with the range at insertion
```

Step five's threshold of 1600 px on the longest edge is chosen to reduce an ordinary Retina screenshot substantially while leaving a screenshot of text legible. `NFR-1.4`'s acceptance criterion is twenty full-screen Retina pastes staying under a documented ceiling; at this threshold and PNG re-encoding, that lands around 20–40 MB, and the ceiling is therefore documented as 64 MB per pad, with the `FR-5.9` size marker appearing at 32 MB.

### 9.5 Provenance capture ordering

The one subtlety in `FR-7.1` is that by the time a paste is being handled, Itchy may already be frontmost, at which point `frontmostApplication` is Itchy and the record is useless. The fix is to maintain the previous frontmost application continuously rather than querying it on demand: `PreviousAppTracker` observes `NSWorkspace.didActivateApplicationNotification`, retains the last non-Itchy activation, and the interceptor reads that. Because pad panels are non-activating, the common case is that Itchy never became frontmost at all and the direct query would have worked — but the case where the user clicks into the panel first is exactly the case where they are about to paste.

### 9.6 Mode switching

Styled → plain (`FR-4.5`): rebuild the attributed string from its `string` value with default typing attributes, apply through the grouped applier with the action name "Flatten Styling", then update metadata. This shares its implementation with the `flatten` transform; there is one code path, invoked from two places.

Plain → styled: no content change, configuration only. The previously discarded styling does not come back, and the mode switch is not an undo of the flatten. Undo of the flatten is undo of the flatten.

## 10. Interface layer

`PadView` is a `VStack` of the text editor and `PadStatusBar`. The status bar is the whole of `FR-3.6` and grows by release rather than being restructured:

```
R1:  scratch · styled
R2:  scratch · styled · 3 pastes ⓘ
R3:  scratch · styled · 3 pastes ⓘ · ⇄ exposed
R4:  scratch · styled · 3 pastes ⓘ · ⇄ exposed · ⌂ local only
```

Each element is a control: the name renames in place, the mode switches with a confirmation on the flattening direction only, the paste count opens the provenance list, exposure and routing toggle. Settings exist for the same properties, and neither surface is authoritative — both mutate the store.

An external-write marker (§11.7) appears as a transient banner within the panel, dismissible, reading what wrote and when, with an Undo button that performs the same undo the keyboard would.

Settings panes: **General** (login item, hotkey, pad count with its ceiling stated), **Editor** (default mode for new pads, default font), **Agents** (R3: server on/off, port, token with regenerate and copy, per-pad exposure table), **Models** (R4: local endpoint, remote credentials, default routing policy).

## 11. MCP server

### 11.1 Transport

Per the architecture document, Itchy is a long-running process that owns the state, so it cannot be launched per session over stdio. Two transports, one protocol implementation:

```
Agent (HTTP client)  ──────────────────────────┐
                                               ├──▶ 127.0.0.1:<port> ──▶ MCPService ──▶ PadStore
Agent (stdio client) ──▶ itchy-mcp shim ───────┘
```

The shim does nothing but proxy, per `FR-8.2`. It reads the port and token from the same well-known location the app writes them to — the port from a small `endpoint.json` in the support directory, the token from the Keychain via a shared access group — and it holds no state and implements no protocol logic. If it grows a single protocol-aware line, that is a defect.

Binding is to `127.0.0.1` explicitly, never `0.0.0.0` (`FR-8.3`). The default port is 8-something in the ephemeral-adjacent range, configurable, with the actual bound port recorded in `endpoint.json` so the shim needs no configuration.

### 11.2 Authentication

Bearer token, 32 bytes from `SecRandomCopyBytes`, base64url-encoded, stored in the Keychain as a generic password (`NFR-3.3`), surfaced in settings with copy and regenerate. Regeneration invalidates immediately (`FR-8.4`) — the server holds the current token in memory and compares in constant time. A request without a valid token gets `401` and no information about what pads exist.

### 11.3 Tool surface

Exactly five tools (`FR-8.5`), and the narrowness is the point:

```json
[
  { "name": "list_pads",
    "description": "List scratchpads exposed to agents.",
    "inputSchema": { "type": "object", "properties": {} } },

  { "name": "read_pad",
    "description": "Read a pad's contents as plain text.",
    "inputSchema": { "type": "object",
      "properties": { "pad": { "type": "string" } },
      "required": ["pad"] } },

  { "name": "append_pad",
    "description": "Append text to the end of a pad.",
    "inputSchema": { "type": "object",
      "properties": { "pad": { "type": "string" },
                      "text": { "type": "string" } },
      "required": ["pad", "text"] } },

  { "name": "write_pad",
    "description": "Replace a pad's entire contents with plain text.",
    "inputSchema": { "type": "object",
      "properties": { "pad": { "type": "string" },
                      "text": { "type": "string" } },
      "required": ["pad", "text"] } },

  { "name": "create_pad",
    "description": "Create a new pad if a slot is free.",
    "inputSchema": { "type": "object",
      "properties": { "name": { "type": "string" },
                      "text": { "type": "string" } } } }
]
```

`pad` accepts either the identifier or the display name, resolving names case-insensitively and failing with an explicit list of candidates when a name is ambiguous. Agents refer to pads the way the user does — "pad four", "the json one" — and requiring a UUID would mean every session starts with a `list_pads` purely to translate.

Pads are additionally exposed as MCP *resources* with URIs of the form `itchy://pad/<id>`, which is what `FR-8.1` means by treating the pad as a surface the agent can read: a resource can be attached to a conversation rather than fetched by a tool call.

### 11.4 Reads return plain text

`read_pad` returns the shadow representation (`FR-8.6`) — plain text, no markup. An image attachment is rendered as a single line reading `[image 1240×820]`, which answers §9's open question in the requirements document in favour of a placeholder: telling the agent that something is present and not retrievable is more truthful than silently omitting it, and an agent that then asks for the image gets a clean refusal rather than a wrong answer about the pad's contents.

### 11.5 Exposure

Not exposed by default, opted in per pad (`FR-8.7`). An unexposed pad is absent from `list_pads`, and `read_pad` against its identifier returns the same error as a nonexistent pad — deliberately the same, so that the tool surface does not confirm the existence of pads the caller may not read.

### 11.6 Write path

An agent write resolves to the registry applier if the panel is open and to the store if not (§5.4, §8.3). In the open case it is grouped on the text view's undo manager and is one undo from reverted (`FR-8.8`). Writes are serialised per pad by the store actor, so two concurrent agent writes cannot interleave, and no locking scheme is introduced (`FR-8.8` explicitly places that out of scope).

### 11.7 External-write visibility

```swift
public struct ExternalWriteMarker: Sendable, Codable, Equatable {
    public let at: Date
    public let origin: WriteOrigin
    public let characterDelta: Int
}
```

Set on every non-user write (`FR-8.9`). When the panel is open, the banner in §10 appears. When it is closed, the marker persists in metadata, the menubar entry for that pad carries an indicator, and the banner appears on next open — which is the compensating control for D-9's consequence that a closed-pad write has no undo.

### 11.8 Off by default

The server does not listen until enabled (`FR-8.10`). Enabling and disabling take effect without relaunch, and the listening state is shown in settings and in the menubar when active.

## 12. Model routing

One enforcement point, below the view layer, per `FR-9.2`:

```swift
func run(_ transform: Transform, on pad: PadID, input: TransformInput) async throws -> TransformOutput {
    if transform.requiresNetwork {
        switch await store.routingPolicy(of: pad) {
        case .localOnly:       throw RoutingRefusal.localOnly(pad: pad)
        case .askEachTime:     guard await consent.request(pad, transform) else { throw RoutingRefusal.declined }
        case .remotePermitted: break
        }
    }
    return try await transform.apply(to: input)
}
```

`TransformRunner` is the only caller of `Transform.apply` in the codebase, which is what makes the menu path and the MCP path subject to the same restriction rather than two policies that are meant to agree. A second call site is a defect, and is checkable by grep in CI.

Local inference targets a locally running Ollama endpoint. Failure to reach it fails the transform; there is no fallback to remote under any policy, including `remotePermitted` (`FR-9.4`), because a silent upgrade from local to remote is precisely the outcome the policy exists to prevent. Remote credentials live in the Keychain and never touch the support directory or any log (`FR-9.5`).

Model-backed transforms implement `Transform` and appear in the same menu, deterministic ones listed first (`FR-9.6`). There is no chat surface, no conversation view, and no model panel; adding one would make the model the centre of the product, which is the position the vision document explicitly declines to take.

## 13. Errors and logging

`OSLog` with subsystem `com.wdogsystems.itchy` and categories `store`, `window`, `text`, `transform`, `mcp`, `model`. Pad *content* is never logged, at any level, in any build — not truncated, not hashed. Pad identifiers and byte counts are logged freely. The MCP category logs the tool name, the pad identifier and the outcome, never the text.

`NFR-3.5` forbids telemetry, so there is no crash reporting service and no analytics dependency. Diagnostics are the system log and, in development, the `itchyctl` harness.

User-facing errors appear in the surface that provoked them — a transform failure in the panel, a store fault on the pad it affects, a server bind failure in settings — and never in a modal alert, with the sole exception of pad deletion confirmation (`FR-2.6`).

## 14. Testing strategy

### 14.1 Core unit tests

`ItchyCore` tests run without a UI framework (`NFR-4.3`), and the target's inability to link AppKit is itself the test of D-2. The units extracted under D-11 and tabulated in §15.2 are tested here too, even though several of them live in the app target rather than in a package: they are pure, they need no window server, and they are where most of the application's actual decisions are made. Coverage: the bounds clamp at all three enforcement points, JSON round-trips including unknown-field preservation, migration fixtures, the save scheduler's debounce and cancellation semantics under a controlled clock, and the fault taxonomy's mapping from bad input to fault case.

The clock is injected. A test that sleeps for 750 ms to observe a debounce is a test that will be deleted within a month for being slow, so `SaveScheduler` takes a `Clock` and the tests advance it.

### 14.2 Store integration tests with fault injection

Against a temporary directory, exercising: atomic write under injected failure between temporary write and replace (`FR-5.6`), truncated metadata, absent content directory, metadata with a future `schemaVersion`, an index naming a pad that does not exist, a pad directory absent from the index, shadow file deleted, disk full simulated by a write-failing `FileManager` seam, and a hand-edited metadata file carrying an unknown field.

Each case asserts two things: that the application would launch with remaining pads usable (`NFR-2.2`), and that no case produces an empty editable pad over unreadable content (§6.7).

### 14.3 Transform tests

Table-driven per transform: representative input, empty input, input at the applicability boundary, malformed input, and input containing multi-byte characters and combining marks. `base64.decode` gets specific attention because its predicate has two conditions and the interesting case is input that is valid base64 and decodes to invalid UTF-8.

### 14.4 UI smoke suite

Small and deliberately shallow, XCUITest, covering the things unit tests structurally cannot reach:

- A panel summoned over a fullscreen application accepts typed text (`FR-3.2`). This is the highest-value test in the suite; it is the failure the architecture document predicts.
- Selecting the same pad repeatedly yields one window (`FR-3.3`).
- A pasted image renders, survives relaunch, and is present in stored content (`FR-4.2`).
- Rename appears in the menubar (`FR-1.2` — the `MenuBarExtra` trigger condition).
- A full session completed without the pointer (`NFR-5.1`).

### 14.5 Performance suite

`NFR-1.1` is a number, so it is measured rather than asserted by feel. An XCTest performance case drives the hotkey path twenty times against a fixture of nine pads at realistic sizes, including one at the 32 MB marker, reading the `OSSignposter` intervals from §8.7 and failing the build if the 95th percentile of `hotkey→firstResponder` exceeds 250 ms. The first iteration after launch is included, not discarded as a warm-up, because it is the iteration the user actually experiences.

### 14.6 Manual checklist per release

Dragging a pad's title bar over another application's window, confirming that no
other Itchy window comes forward and the user's arrangement is otherwise
untouched (`FR-3.1`; see D-14 for why this is manual). Accessibility passes
(`NFR-5.2`, `NFR-5.3`), Gatekeeper launch on a clean machine (`NFR-4.2`), Spotlight exclusion verified by searching for pad-unique content and then grepping the same content out of the directory (`NFR-3.4`), and idle CPU observed over five minutes (`NFR-1.3`).

## 15. Testability seams

### 15.1 The doctrine

Every file that touches AppKit or SwiftUI is a translator, not a decision-maker. It converts system types into our value types, hands those values to code that runs without a window server, and applies whatever comes back. A conditional inside a view body, a window controller, or an `NSViewRepresentable` is a defect of placement rather than a matter of taste.

There are two reasons, and only one of them is about testing. The practical one is that `NFR-4.3` and the coverage floor in the implementation plan are both unreachable if decisions live in files that need a running window server to execute. The structural one matters more: logic embedded in a view is logic that can only be understood by running the application, which means it is logic that gets reasoned about by trying things. Everything below is a decision that would otherwise be made in a place where it could not be examined.

The naming convention is load-bearing, because it is what makes a misplacement visible in a file listing: `*Model` for a projection from state to what is displayed, `*Plan`, `*Policy` or `*Resolver` for a decision, `*Codec` for a conversion. A type with one of these names that imports AppKit for anything beyond a value type is wrong, and so is a view file containing a decision that has no such type behind it.

### 15.2 The seams

| System boundary | Extracted unit | What the unit decides | What the shell still does |
|---|---|---|---|
| Status item / `MenuBarExtra` | `MenuModel.rows(for:threshold:)` | Row order, titles, size markers, key equivalents, faulted-pad presentation | Render rows, dispatch selection |
| `PadPanel` | `PanelConfiguration` | Style mask, level, collection behaviour, minimum size, key/main eligibility | Apply the value to an `NSPanel` |
| `PadWindowController` | `FrameResolver.resolve(stored:screens:mouseScreen:openCount:)` | Which rectangle a panel opens at, across all four rules of §8.5 | `setFrame` |
| Hot-key handler | `HotKeyAction.decide(target:panelState:)` | Open, close, or create-first — the toggle semantics of §8.6 | Register the key, call the registry |
| Launch | `LaunchPlan.steps(index:metadata:)` | What is read eagerly, what is deferred, which pinned pads open | Execute the steps in order |
| `PasteInterceptor` | `PastePlan.plan(descriptor:mode:)` | Chosen representation, discard rules for plain mode, downsample targets, the provenance entry | Read the pasteboard into a descriptor, execute the plan |
| Image handling | `DownsamplePolicy.target(for:)` | Target dimensions, or nil when the image is already small enough | Perform the resample |
| `PadTextCoordinator` | `ContentCodec` | `NSAttributedString` ⇄ `PadContent`, including the plain-text extraction | Call it on the serialisation debounce |
| Mode switching | `Flatten.apply(to:)` | The flattened content, shared with the `flatten` transform | Push the result through the grouped applier |
| `PadStatusBar` | `StatusBarModel.segments(for:)` | Which segments appear at this release and their wording | Render segments as controls |
| External-write banner | `BannerModel.state(for:now:)` | Visible or not, wording, whether undo is offered | Render the banner |
| MCP request handling | `ToolRouter.route(_:) -> StoreOperation` | Pad resolution by id or name, ambiguity errors, the not-found/not-exposed equivalence of §11.5 | Transport, framing, authentication |
| Settings | `SettingsModel` | Validation and clamping, including the pad-count ceiling | Bind controls |
| Formatting controls | `FormattingPlan` | Which traits read as on, whether a toggle applies or removes, which chords are shortcuts, availability by mode (D-20) | `TextFormatter` reads the selection and applies the change through the text view's undo |
| `updateNSView` | `ModeConfigurationPlan.decide(configured:requested:)` | Whether an update reconfigures the text view, so typing attributes survive unrelated refreshes (D-20) | `PadTextView.configureIfNeeded` |
| Pad settings sheet | `PadSettingsModel` | Name trimming and the empty-name rule, the duplicate-name notice (D-21) | Bind controls; apply the name on Return and close |
| About | `FirstRunPolicy.dismissal(for:)`, `aboutRequest(showing:)`, `AppVersion.display` | Whether closing records the first run, whether About opens or raises, the version wording (D-22) | Show the window |
| Editor font | `EditorFontPolicy.treatment(runFamily:mode:bodyFamilies:)` | Which runs follow the font setting, which keep their own, and which families count as body text (D-19) | `BodyFont` resolves the font and applies the treatment to the text storage |

Each extracted unit is a value type or a namespace of pure functions, is `Sendable`, and is `Equatable` wherever it returns a value rather than performing an action — so that a test compares one whole expected value against one actual value, rather than poking at six fields and hoping it has checked the ones that matter.

Two rules keep the seam honest. A decision returns an enumeration rather than a Boolean or a pair of Booleans, because a Boolean pair has states that mean nothing and a test cannot tell which of them the code is in. And no function both decides and performs: `HotKeyAction.decide` returns what should happen and does not make it happen, which is the only reason its toggle semantics can be tested at all.

### 15.3 Exclusion is earned, not asserted

The coverage exclusion list in the implementation plan is the obvious place for this doctrine to rot, since any file can be made to hit its coverage target by being excluded from measurement. The exclusion list is therefore coupled to a complexity constraint: a file may appear on it only while it passes a scoped lint configuration setting `cyclomatic_complexity` to 2 and prohibiting `if`, `switch`, and `for` other than optional unwrapping.

The effect is that exclusion is available only to files that are genuinely boilerplate, and a view file that acquires a branch stops qualifying — at which point the choice is to extract the branch into a seam or to start covering the file. Both are acceptable; leaving an untested branch inside an unmeasured file is not.

## 16. Build and release

Signing with Developer ID Application, hardened runtime enabled, notarised via `notarytool`, stapled, distributed as a signed DMG. No entitlements beyond what the hardened runtime requires; specifically no App Sandbox (`CON-6`), and the Keychain access group shared between the app and the shim.

Versioning is `MAJOR.MINOR.PATCH` with the build number from the commit count, biased toward patch releases and set in `Config/Version.xcconfig` (D-22). A `Makefile` carries `make test`, `make app`, `make notarise`, `make dmg`, so that the release sequence is not a remembered list of commands.

CI runs `make test` plus the grep-based structural checks that enforce the architecture: no `import AppKit` in `ItchyCore`, no `FileManager` use outside the store, and exactly one call site for `Transform.apply`. Those three greps encode `CON-4`, D-2 and §12's single enforcement point respectively, and each is a rule that would otherwise decay silently.

Updates via Sparkle from R2 (`NFR-4.4`); until then, replacing the bundle.

## 17. Milestones

Each milestone exits on its listed requirements passing their acceptance criteria. The ordering front-loads what is hard to change, per the architecture document's build order, with the two additions §7 of the requirements document identified.

| # | Milestone | Exit criteria |
|---|---|---|
| M1 | Shell | `FR-1.1`, `FR-1.2`, `FR-1.5`, `NFR-1.3`. Hardcoded pad list; settings stub; CI green with the structural greps in place |
| M2 | Panels | `FR-3.1`–`FR-3.5`, `FR-3.7`. **The fullscreen keyboard-input test passes before anything else is built on top** |
| M3 | Text and storage | `FR-4.1`–`FR-4.3`, `FR-4.6`–`FR-4.8`, `FR-5.1`–`FR-5.6`, `NFR-2.1`. Fault-injection suite green |
| M4 | Store-backed pads | `FR-2.1`–`FR-2.8`, `FR-4.4`, `FR-4.5`, `FR-4.9`, `FR-5.7`–`FR-5.10`, `FR-3.6`, `NFR-2.2` |
| M5 | R1 completion | `FR-1.3`, `FR-1.4`, `FR-1.6`, `NFR-1.1`, `NFR-1.2`, `NFR-1.4`, `NFR-3.1`, `NFR-3.4`, `NFR-3.5`, `NFR-4.1`–`NFR-4.3`, `NFR-5.1`–`NFR-5.3`. **Ships. Then is used daily for a month before M6 opens** |
| M6 | Transforms and provenance | `FR-6.1`–`FR-6.6`, `FR-7.1`–`FR-7.5`, `NFR-4.4` |
| M7 | MCP | Spike S-4 settled first. `FR-8.1`–`FR-8.10`, `NFR-3.2`, `NFR-3.3` |
| M8 | Model routing | `FR-9.1`–`FR-9.6` |

The gap between M5 and M6 is a specification item rather than a scheduling accident. The vision document's success measure is behavioural — whether working text actually stops being routed through messages-to-self — and it cannot be evaluated while features are still arriving. A month of daily use before the second release also has a good chance of reordering M6 through M8, which is information worth having.

## 18. Risks and spikes

| | Risk | Mitigation / spike |
|---|---|---|
| R-1 | Non-activating panel refuses keyboard input | `canBecomeKey` override (§8.2) plus the M2 exit test. Known, specified, tested |
| R-2 | `MenuBarExtra` stale under content change | Seam at `StatusItemController`; AppKit fallback is one file. Trigger is named in `FR-1.2` |
| R-3 | Pasted images grow pads unnoticed | Downsample at 1600 px, 64 MB documented ceiling, 32 MB marker (§9.4, `FR-4.3`, `FR-5.9`) |
| R-4 | MCP write path correctness | Visibility and undo rather than locking (§11.6, §11.7). Accepted by `FR-8.8` |
| R-5 | Feature accretion into a note-taking application | `CON-1`–`CON-3` are the control, and the M5–M6 gap is the enforcement mechanism |
| S-1 | `RegisterEventHotKey` on macOS 26 | **Resolved** (D-17). Registers with `noErr` and no Accessibility permission; D-6 stands. Live firing is a manual check |
| S-2 | `TextEditor` attachment rendering on shipping macOS 26 | **Resolved** (D-15). Unchanged: the attachment is in the model and is not drawn. §9.1 stands |
| S-3 | Spotlight exclusion | **Resolved** (D-16). `.metadata_never_index` does nothing; pads now live in `pads.noindex`, verified against real Spotlight |
| S-4 | MCP Swift SDK fit for a long-running host | **Resolved** (D-17). Fits: the transport owns no socket and exposes `handleRequest`. SDK adopted; the fallback is not needed |

## 19. Deliberate non-goals, restated

No document library, folder hierarchy, tagging, or corpus-wide search (`CON-1`). No save, title, or filing prompts (`CON-2`). No cloud sync (`FR-5.10`). No telemetry (`NFR-3.5`). No App Store build (`CON-6`). No chat panel (`FR-9.6`). No inline arithmetic or unit conversion, which the vision document notes is thoroughly claimed by incumbents and is not where this application differentiates.

A feature request arriving from any direction is evaluated against `CON-3` first: transient content or permanent content. If permanent, it is declined, and the decline is the correct answer rather than a deferral.
