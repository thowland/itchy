# Itchy — Architecture

*Draft, September 2026*

## Scope and constraints

This document covers the technical design of the first release, with enough forward structure that the transform menu, provenance capture, MCP server, and model routing described in the vision document can be added without rework.

The constraints we are designing against are as follows. The deployment floor is macOS 15 (D-27). It was macOS 26 while the application was for its author alone, on the reasoning that supporting Sequoia bought nothing; that held until the first signed build was carried to a second Mac and refused to open. Nothing in the design turned out to depend on 26, so the floor moved rather than the code. What the original constraint was really buying — no back-compatibility work, no availability guards, no two paths through anything — is unchanged, because the floor is still a floor and not a range. Distribution is via Developer ID and notarisation rather than the App Store, and the application is not sandboxed. The working set is under ten pads holding at most a few megabytes each, which means that no part of the storage design needs to scale, and designs that trade simplicity for throughput should be rejected on sight.

## Layer structure

The application is organised in four layers, and the boundary that matters most is the one between the store and everything else, because it is what allows a second writer to be added later.

**Core** holds the pad model, the store that owns loading and saving, and the transform protocol. It has no dependency on AppKit or SwiftUI and can be exercised from tests and from a command-line harness.

**Platform** holds the AppKit pieces that SwiftUI does not currently express — the status item, the floating panel subclass, the window controllers, and the text view bridge.

**Interface** holds the SwiftUI views rendered inside those windows, along with settings.

**Services** holds the transform implementations, the MCP server, and the model client. Everything here talks to the store and never to a view.

The single rule that keeps this honest is that the store is the only component that touches disk. Views observe the store, transforms operate on values handed to them by the store, and the MCP server reads and writes through the same interface a view would use.

## Application shape

Itchy runs as an accessory application with no Dock icon, set through `LSUIElement` in the Info.plist and confirmed at launch with `NSApp.setActivationPolicy(.accessory)`.

The menubar presence can be built either with SwiftUI's `MenuBarExtra` in `.menu` style or with `NSStatusItem` and an `NSMenu`. We would start with `MenuBarExtra`, since the pad list is short and largely static and the SwiftUI version is about a tenth of the code, while noting that `MenuBarExtra` has a history of behaving poorly when menu content changes underneath it. The fallback is roughly thirty lines of AppKit and the menu contents are computed from the store either way, so the switch is cheap if it becomes necessary. The decision should be revisited the first time a pad rename fails to appear in the menu.

## Window layer

The floating panel is the first place where SwiftUI's window management does not reach. What we want is a utility window that floats above other applications, does not activate Itchy when clicked, survives application deactivation, and appears over fullscreen spaces — and SwiftUI has no vocabulary for that combination.

The implementation is an `NSPanel` subclass configured with a style mask including `.nonactivatingPanel`, `.utilityWindow`, `.titled`, `.closable`, and `.resizable`; `isFloatingPanel` set true; `level` set to `.floating`; `hidesOnDeactivate` set false so the pad stays visible while the user works in another application; and `collectionBehavior` including `.canJoinAllSpaces` and `.fullScreenAuxiliary` so it follows the user across spaces and over fullscreen applications. The detail that will cost an afternoon if it is missed is that a non-activating panel does not become key by default, so `canBecomeKey` has to be overridden to return true; without it the panel appears correctly and refuses to accept typed input.

Content is hosted with `NSHostingView`. Each pad gets its own window controller, held in a dictionary keyed by pad identifier, so that opening a pad that is already open brings the existing window forward rather than creating a second one. Frame persistence is handled by writing the frame into the pad's metadata on `windowDidMove` and `windowDidResize` rather than by `setFrameAutosaveName`, because we want the frame to travel with the pad record and to be readable by the same machinery that reads everything else.

## Text layer

The second place SwiftUI does not reach is the editor itself, and the reason is specific. SwiftUI's `TextEditor` gained genuine rich-text editing on macOS 26 through `AttributedString` and `AttributedTextSelection`, and for styled text alone it would be the right choice. It does not support text attachments; an attributed string loaded from RTFD with an embedded image will report the attachment present and will not render it in a `TextEditor`, while the AppKit text view displays it correctly. Since pasted screenshots are in the first-release scope, this settles the question.

The editor is therefore `NSTextView` wrapped in an `NSViewRepresentable`, with a coordinator acting as `NSTextViewDelegate`. A considerable amount of the feature list arrives free with that decision: image paste and drag-and-drop, spell checking, the system find bar, the standard Edit and Format menu responder chain, and `pasteAsPlainText:` as an existing responder action, which covers the paste-and-match-style requirement without any implementation on our side.

Two behaviours need explicit handling. The first is the plain-versus-styled distinction, which we model as a per-pad mode rather than as a global setting: a pad in plain mode has `isRichText` disabled and typing attributes pinned to the default font, and switching a pad from styled to plain flattens the existing content by rebuilding the attributed string from its `string` value. The second is change notification, where `textDidChange` feeds a debounced save through the store rather than writing on every keystroke.

## Data model and storage

A pad is a small record: identifier, display name, mode, creation and modification timestamps, window frame, pinned flag, and a provenance list. Content lives beside it rather than inside it.

Storage is flat files under `~/Library/Application Support/Itchy/`, with one directory per pad named by its identifier, containing `content.rtfd`, `content.txt`, and `meta.json`, plus a top-level `index.json` recording pad order. There is no database. For ten records, SQLite through Core Data or SwiftData is overhead in exchange for capabilities we will never use, and it makes the content opaque to every other tool on the machine, which matters more than usual here given where this is going.

RTFD is the content format because `NSAttributedString` reads and writes it directly and it is the only widely supported format that carries inline image attachments without our inventing an attachment scheme. Its weakness is that it is close to unreadable by anything that is not AppKit, which is a problem for an application whose stated direction is agent addressability. The mitigation is to write a derived plain-text shadow file on every save. `content.txt` is never read back by the application and is never authoritative; it exists so that the MCP server, any future search, Spotlight, and ordinary command-line tooling can all read pad contents without a dependency on the AppKit text system. Writing it costs a string extraction on a save path that is already debounced.

Saves are debounced on roughly 750 milliseconds of typing inactivity, and forced on window close, on application termination, and on `applicationWillResignActive`. Writes are atomic — write to a temporary file in the same directory, then replace — so that a crash mid-save loses at most the last few seconds rather than the pad.

## Provenance capture

When content arrives by paste or drop, we capture what we can about where it came from: the frontmost application at the moment before Itchy received the event, obtained from `NSWorkspace.shared.frontmostApplication`; any URL present on the pasteboard under `public.url` or the web URL types that browsers supply alongside HTML; and a timestamp.

The tempting implementation is to attach this to the text as a custom attribute, and we would advise against it, because attributes are exactly what the flatten-to-plain operation destroys, and provenance should survive that operation. It is stored instead as an entry in `meta.json` carrying the source record and the character range it was inserted at.

The honest difficulty is that character ranges drift as the user edits, and maintaining accurate range mapping through arbitrary editing is more machinery than this feature is worth. Our current thinking is to record the range as it was at insertion, to treat it as approximate, and to display provenance at the pad level — a short list of what has been pasted into this pad and from where — rather than attempting to attribute individual characters. If per-range attribution proves worth the effort later, `NSTextStorage` edit notifications give enough information to maintain it properly.

## Transform pipeline

Transforms are defined by a protocol carrying an identifier, a display name, a predicate describing what input it applies to, and an execution function. Deterministic transforms run synchronously; model-backed transforms return asynchronously and the protocol therefore has to be asynchronous throughout, with the synchronous cases simply returning immediately.

The first-release set is deterministic and small: flatten styling, change case, pretty-print and minify JSON, encode and decode base64, encode and decode URL components, trim whitespace, and sort lines. Model-backed transforms implement the same protocol and appear in the same menu, which is the structural point — the interface makes no distinction between an operation that costs a microsecond and one that costs two seconds and a network round trip, other than showing progress and offering cancellation for the latter.

Every transform is applied through the store and pushed onto the text view's undo manager as a single grouped operation, so that any transform is one undo away from being reverted.

## MCP server

This is the piece with the most design risk, and the shape of it is constrained by a protocol assumption that does not fit our situation.

Most MCP servers are launched as subprocesses by the client and communicate over stdio, which suits a server that exists only for the duration of a session. Itchy is a long-running GUI application that owns the state, so it cannot be launched per-session by an agent. The arrangement we would propose is that Itchy runs a local HTTP endpoint bound to the loopback interface on a fixed port, authenticated with a token held in the Keychain and surfaced in settings, and that a small stdio shim binary ships alongside the application for clients that expect to launch a subprocess. The shim does nothing but proxy stdio to the loopback endpoint, which keeps the protocol surface in one place while remaining compatible with clients on either transport.

The exposed surface is deliberately narrow: `list_pads` returning identifiers, names, modes and sizes; `read_pad` returning plain text from the shadow file; `append_pad`; `write_pad` replacing contents; and `create_pad` where a free slot exists. Reading returns plain text rather than RTFD, because an agent has no use for styling and every use for predictable input.

Two policy questions need answers before this is built rather than after. The first is exposure: pads should be opted in individually rather than exposed wholesale, so that a pad holding something sensitive is not readable by whatever process holds the token. The second is write conflict, since an agent may write to a pad while it is open and being edited. Our current preference is that agent writes to an open pad are applied through the same undo-grouped path as a transform, with a visible indication on the pad that an external write occurred, so that the user can see it happen and undo it — rather than any locking or merge scheme, which would be considerable machinery for a single-user application where the two writers are the user and a process the user started.

## Model routing

Each pad carries a routing policy: local only, remote permitted, or ask on each use, defaulting to local only. Local inference goes to a locally running Ollama endpoint; remote goes to a hosted API with credentials in the Keychain. The policy is enforced in the service layer rather than in the view, so that a transform invoked over MCP is subject to the same restriction as one invoked from the menu, and the pad's current policy is displayed in the pad window so the state is never ambiguous.

## Distribution

Developer ID signing with the hardened runtime, notarised, distributed directly. The hardened runtime is required for notarisation and is compatible with running unsandboxed. Updates through Sparkle once there is any audience beyond ourselves; until then, replacing the application bundle is adequate.

The reason for staying out of the App Store is that the sandbox would complicate the loopback server, the Keychain-held token, and any future local process invocation, and none of those complications buys us anything given that distribution is direct.

## Risks

The window and text layers carry ordinary implementation risk that is well understood, and the specific failure we expect is the non-activating panel refusing keyboard input, which is addressed above.

Pasted images are the most likely source of unpleasant surprise, since a screenshot pasted at Retina resolution can be several megabytes and a pad accumulating them will grow without anyone noticing. We would downsample on paste above a threshold dimension and surface pad size in the menu once it passes some limit, on the grounds that a scratchpad silently holding four hundred megabytes is a support problem we would be creating for ourselves.

The MCP write path is the second risk, and the mitigation is the visibility and undo behaviour described above rather than any attempt at correctness through locking.

The largest risk is not technical. An application of this kind fails by accumulating features until it becomes the note-taking application it was built to avoid, and the vision document's list of what Itchy is not should be treated as the governing constraint on every subsequent decision.

## Build order

The sequence below front-loads the parts that are hard to change and defers the parts that are self-contained.

1. Status item with a hardcoded pad list, accessory activation policy, settings window stub.
2. `NSPanel` subclass, window controller, open and close, frame persistence.
3. `NSTextView` bridge with load and save to RTFD, shadow text file, debounced autosave, atomic writes.
4. Real pad list from the store, pad creation, rename, reorder, plain and styled modes.
5. Transform menu with the deterministic set.
6. Provenance capture at the pad level.
7. MCP server and stdio shim, with per-pad exposure settings.
8. Model routing and model-backed transforms.

Steps one through four constitute the first release. Everything after it is additive, and none of it should require the storage format or the store interface to change.

## Open questions

Whether the pad count should be fixed at a number chosen now or allowed to grow, given that a soft limit tends to erode and the fixed-slot constraint is part of what makes the application what it is.

Whether a global hotkey to open the most recent pad is worth adding to the first release, since it likely accounts for a large share of actual use and the rest of the category treats it as the primary entry point.

Whether the shadow text file should be written for every pad or only for pads exposed over MCP, which is a small privacy question about what is left readable on disk.
