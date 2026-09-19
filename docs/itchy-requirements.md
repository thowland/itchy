# Itchy — Requirements

*Draft, September 2026*

## 1. Purpose and scope

This document states the requirements for Itchy as a set of numbered, individually verifiable propositions. It is subordinate to two other documents and should be read after both: `itchy-vision.md` establishes what the application is for and, more importantly, what it is not, and `itchy-architecture.md` establishes how it is to be built. Where this document and the vision document appear to conflict, the vision document governs and this document is wrong. Where this document and the architecture document appear to conflict on a matter of implementation, the architecture document governs; where they conflict on a matter of observable behaviour, this document governs.

The scope is the complete product across all four planned releases, rather than the first release alone. Requirements for later phases are stated at lower fidelity than those for the first, which is appropriate given that model routing in particular is expected to be reshaped by the platform before it is reached.

The audience is the author, who is also the implementer and the primary user. The document exists to make the design decisions already taken in the other two documents testable, and to record the small number of decisions taken since.

## 2. Conventions

### 2.1 Requirement keywords

The keywords MUST, MUST NOT, SHOULD, SHOULD NOT and MAY are used as defined in RFC 2119. MUST marks a requirement whose absence means the release is not complete. SHOULD marks a requirement that may be traded away against a stated reason recorded in this document. MAY marks a genuine option.

### 2.2 Identifier scheme

Functional requirements are numbered `FR-<area>.<n>`, non-functional requirements `NFR-<area>.<n>`, and constraints `CON-<n>`. Identifiers are permanent. A requirement that is withdrawn is marked withdrawn in place rather than deleted, and its number is not reused.

### 2.3 Release tags

| Tag | Release | Contents |
|-----|---------|----------|
| R1 | First release | Menubar, pads, floating panels, styled text with images, indefinite retention, flatten-to-plain, global hotkey |
| R2 | Second | Transform menu (deterministic set), provenance capture |
| R3 | Third | MCP server, stdio shim, per-pad exposure |
| R4 | Fourth | Model routing, model-backed transforms |

Each requirement carries the release in which it must first hold. A requirement tagged R1 is also a requirement of R2, R3 and R4; nothing is permitted to regress.

### 2.4 Acceptance

Every MUST and SHOULD requirement carries an acceptance criterion stating how the requirement is demonstrated to hold. A criterion that cannot be checked by an automated test or a described manual procedure is a defect in this document, not a licence to skip verification.

## 3. Definitions

**Pad** — one addressable scratch surface, consisting of a metadata record and its content. Pads are the only unit of content in the application; there is no document, file, folder, or note.

**Slot** — a position in the pad list. The list is ordered and bounded, and a pad occupies exactly one slot.

**Panel** — the floating window in which a pad's content is displayed and edited.

**Mode** — a per-pad property, either *styled* or *plain*, governing whether the pad retains text attributes.

**Shadow file** — the derived plain-text representation of a pad's content, written on save, never read back by the application, and never authoritative.

**Transform** — a named operation taking a pad's content, or a selection within it, and returning replacement content. Transforms are either deterministic or model-backed; the interface does not distinguish them beyond progress and cancellation.

**Provenance record** — a note of where a piece of pasted or dropped content came from: source application, source URL where available, and arrival timestamp.

**Exposure** — the per-pad property determining whether a pad is readable and writable over MCP.

**Routing policy** — the per-pad property determining whether model-backed transforms on that pad may reach a remote service.

## 4. Governing constraints

These are not requirements in the sense of things to be built. They are limits on what may be built, and they are stated first because their function is to cause requests to be declined.

**CON-1.** Itchy MUST NOT acquire a document library, a folder hierarchy, a tagging system, or a search facility spanning the corpus. The corpus is small enough to be seen at once, and each of these features is the mechanism by which the application would become the note-taking application it exists to avoid.

**CON-2.** Itchy MUST NOT require a filing decision of the user at any point. No save prompt, no title prompt, no location prompt, no confirmation on close. Content that has been typed or pasted is retained; content is removed only by an explicit destructive action on a pad.

**CON-3.** Any proposed feature MUST be evaluated by asking whether it serves transient content or permanent content. Features serving permanent content are out of scope regardless of merit.

**CON-4.** The store is the only component permitted to touch disk. Views observe the store; transforms operate on values handed to them by the store; the MCP server reads and writes through the same interface a view uses. This constraint exists to make a second writer safe to add, and it MUST hold from the first commit rather than being arranged for later.

**CON-5.** The deployment floor is macOS 15. No back-compatibility work is to be undertaken below it.

*Amended September 2026 (D-27). The floor was macOS 26 for R1, on the reasoning that the application was for its author alone and supporting Sequoia bought nothing. It bought something the moment the first signed build was carried to a second machine and refused to open. Nothing in the code required 26 — it builds at 15 with no availability guards and no changes — so the floor was lowered to the oldest release the author actually runs. The constraint's second half is unchanged and is the important half: no back-compatibility work. 15 is where the floor sits, not the start of a compatibility matrix.*

**CON-6.** The application is not sandboxed and is distributed via Developer ID and notarisation. App Store distribution is out of scope, and no requirement may be written that presupposes it.

**CON-7.** Nothing in the storage design may be justified by scale. The working set is under twenty pads of a few megabytes each. Where simplicity and throughput conflict, simplicity wins without argument.

## 5. Functional requirements

### FR-1 Application shell

**FR-1.1 — Accessory application** *(R1, MUST)*
Itchy MUST run as an accessory application with no Dock icon and no application window of its own, configured through `LSUIElement` and confirmed at launch.
*Acceptance:* the application appears in the menubar and not in the Dock or the application switcher after a cold launch and after being relaunched while running.

**FR-1.2 — Menubar entry point** *(R1, MUST)*
The menubar item MUST list every pad in slot order and MUST open the corresponding pad on selection. The list MUST reflect pad creation, renaming, reordering and deletion without requiring a relaunch.
*Acceptance:* renaming a pad while the menu machinery is live causes the new name to appear on the next menu open. This case is called out specifically because it is the known failure mode of `MenuBarExtra` and the trigger for falling back to `NSStatusItem`.

**FR-1.3 — Launch at login** *(R1, SHOULD)*
Itchy SHOULD offer to start at login and SHOULD default to doing so, on the grounds that an application reached in the first two seconds of need cannot be one the user has to start first.
*Acceptance:* the setting is present, toggling it registers and unregisters the login item, and the state survives a restart.

**FR-1.4 — Global hotkey to last-used pad** *(R1, MUST)*
A user-configurable global hotkey MUST open the most recently used pad and bring its panel forward and focused, from any application, including over a fullscreen application. Pressing the hotkey while that pad's panel is already frontmost and focused MUST dismiss it.
*Acceptance:* with a fullscreen application frontmost, the hotkey produces a focused pad accepting typed input; a second press hides it; the pad chosen is the one most recently edited or opened. **Demonstrated 19 September 2026** for 0.1.1, by hand on macOS 15. Registration was verified in the suite from Sprint 5 (D-17); the firing could not be, because a synthesised keypress cannot be posted from a test process. This was the press.

**FR-1.5 — Settings** *(R1, MUST)*
A settings window MUST exist and MUST be reachable from the menubar. In R1 it carries the login item, the hotkey, and the pad count; later releases extend it rather than restructure it.
*Acceptance:* each setting present in a given release is readable, writable, and persistent across relaunch.

**FR-1.7 — About and version** *(R1, SHOULD)*
The menubar menu SHOULD offer an About item that shows the application's version and build number, reusing the first-run window. Opening it MUST NOT alter whether the first run has been seen. Added after R1, at the author's request (D-22).
*Acceptance:* About opens the welcome window with a Close button and a line reading "Version MAJOR.MINOR.PATCH (build)"; closing it leaves the first-run record unchanged.

**FR-1.6 — Cold launch cost** *(R1, MUST)*
Launching Itchy MUST NOT block on reading pad content. Pad metadata and order are read at launch; content is read when a pad is first opened.
*Acceptance:* with every pad at its maximum practical size, the menubar item is present and responsive within the budget set in NFR-1.1.

### FR-2 Pads and slots

**FR-2.1 — Bounded pad list** *(R1, MUST)*
The pad list MUST be bounded. The bound defaults to nine pads, MUST be user-configurable, and MUST NOT exceed a hard ceiling of twenty pads under any circumstance, including direct editing of stored settings.

The reasoning is worth recording, because this requirement is a deliberate softening of the fixed-slot model the vision document describes, and the vision document's own warning is that a soft limit tends to erode. The configurable range is therefore narrow and the ceiling is itself a requirement rather than a guideline: twenty pads still fit in one glance at a menu, and a ceiling that cannot be raised from settings, from a defaults write, or from a hand-edited index file is not a limit that erodes quietly. If the ceiling is ever reached in practice, that is evidence about the product's direction and should be treated as such rather than raised.

*Acceptance:* the pad count setting refuses values above twenty; a stored settings value above twenty is clamped on read and the clamped value is written back; pad creation fails cleanly at the configured count with the reason stated.

**FR-2.2 — Lowering the bound** *(R1, MUST)*
Lowering the configured pad count below the number of existing pads MUST NOT delete or hide content. The reduction takes effect for pad creation only, and the setting MUST state this where it is presented.
*Acceptance:* with nine pads present, setting the count to four leaves all nine pads listed and readable, and prevents creation of a tenth.

**FR-2.3 — Pad creation** *(R1, MUST)*
Creating a pad MUST require no input from the user. A new pad receives a default name, the default mode, and a default frame, and MUST be immediately ready to accept typing.
*Acceptance:* from the menubar, creating a pad produces a focused panel with a text cursor and no intervening dialogue.

**FR-2.4 — Pad naming** *(R1, MUST)*
A pad MUST have a display name, MUST be renameable, and MUST NOT require the user to supply one at any point. Names need not be unique.
*Acceptance:* a renamed pad shows its new name in the menubar and panel title, and the name persists across relaunch.

**FR-2.9 — Per-pad settings** *(R1, SHOULD)*
Each pad SHOULD have a settings sheet reached from the pad itself, holding its name, mode and pinned state, and later its exposure and routing policy. An empty name MUST NOT be saved. A name shared with another pad SHOULD be pointed out, since it prevents asking for the pad by name. Added after R1, at the author's request (D-21).
*Acceptance:* renaming from the sheet updates the menubar, the panel title and the status bar without reopening the pad; clearing the name keeps the old one; a duplicate name, in any case, shows a notice.

**FR-2.5 — Reordering** *(R1, MUST)*
Slot order MUST be user-controllable and MUST persist.
*Acceptance:* a reordered list survives relaunch, and `index.json` reflects the order.

**FR-2.6 — Pad emptying and deletion** *(R1, MUST)*
Emptying a pad's content MUST be available as a single action and MUST be undoable while the panel remains open. Deleting a pad entirely MUST require confirmation, this being the one place where CON-2's prohibition on prompts does not apply, since the action is destructive rather than organisational.
*Acceptance:* emptying then undoing restores the content exactly, including images; deleting prompts once and then removes the pad's directory.

**FR-2.7 — Pinning** *(R1, SHOULD)*
A pad MAY be pinned, which SHOULD cause its panel to reopen at launch.
*Acceptance:* a pinned pad's panel is present after relaunch at its stored frame; an unpinned pad's is not.

**FR-2.8 — Pad mode** *(R1, MUST)*
Each pad MUST carry a mode of *styled* or *plain*, independently of every other pad. There MUST NOT be a global setting that overrides per-pad mode.
*Acceptance:* two pads open simultaneously in different modes behave according to their own modes.

### FR-3 Pad windows

**FR-3.1 — Floating non-activating panel** *(R1, MUST)*
A pad panel MUST float above windows of other applications, MUST NOT activate Itchy as the frontmost application when clicked, MUST remain visible when Itchy is deactivated, and MUST appear over fullscreen spaces.
*Acceptance:* with a fullscreen editor frontmost, a pad panel is visible, accepts clicks, and does not displace the editor as the active application.

**FR-3.2 — Keyboard input to a non-activating panel** *(R1, MUST)*
A pad panel MUST accept typed input, including when it has been summoned over another application.
*Acceptance:* typing after clicking into a panel over a fullscreen application inserts text. This is stated as its own requirement because a non-activating panel does not become key by default and will otherwise appear entirely correct while silently discarding keystrokes.

**FR-3.3 — One window per pad** *(R1, MUST)*
Opening a pad that is already open MUST bring the existing panel forward rather than creating a second window on the same pad.
*Acceptance:* selecting the same pad from the menubar five times yields one panel.

**FR-3.4 — Frame persistence** *(R1, MUST)*
A panel's position and size MUST be recorded against the pad and MUST be restored when the pad is next opened, including across relaunch and across display configuration changes.
*Acceptance:* moving and resizing a panel, closing it, relaunching, and reopening restores the frame; a frame stored for a display that is no longer attached is brought onto an attached display rather than opening offscreen.

**FR-3.5 — Close without consequence** *(R1, MUST)*
Closing a panel MUST put the pad away with no prompt and no loss, and MUST force a save.
*Acceptance:* typing and immediately closing, then killing the process, then relaunching, shows the typed content.

**FR-3.6 — Pad state visible on the pad** *(R1, MUST)*
The panel MUST show the pad's name and mode. From R3 it MUST also show exposure state, and from R4 the routing policy.
*Acceptance:* each state that exists in a given release is legible from the panel without opening settings or a menu.

**FR-3.7 — Panel chrome** *(R1, SHOULD)*
The panel SHOULD be a titled, closable, resizable utility window and SHOULD NOT introduce custom window chrome. The category's differentiation is not in window decoration and the standard chrome carries behaviour we would otherwise reimplement.
*Acceptance:* standard window controls and standard resize behaviour are present.

### FR-4 Editor

**FR-4.1 — Styled text** *(R1, MUST)*
A pad in styled mode MUST retain text attributes through typing, pasting, saving, closing and relaunching. Pasted content MUST retain its structure, including table structure where the source supplies it.
*Acceptance:* content pasted from a browser and from a word processor round-trips through save and relaunch with attributes and structure intact.

**FR-4.2 — Inline images** *(R1, MUST)*
A pad in styled mode MUST accept images by paste and by drag-and-drop, MUST render them inline, and MUST retain them across save and relaunch.
*Acceptance:* a pasted screenshot renders in the panel, survives relaunch, and is present in the stored content. This requirement is the reason the editor is an `NSTextView` rather than SwiftUI's `TextEditor`, which reports attachments present and does not draw them.

**FR-4.3 — Image size control** *(R1, MUST)*
Images above a threshold dimension MUST be downsampled on arrival, and the threshold MUST be chosen so that ordinary Retina screenshots are reduced.
*Acceptance:* pasting a full-screen Retina capture into a pad increases the pad's stored size by an amount within the budget in NFR-1.4.

**FR-4.4 — Plain mode** *(R1, MUST)*
A pad in plain mode MUST hold no attributes: typing MUST use the default font, and pasting MUST insert text without styling or attachments.
*Acceptance:* pasting styled content with an image into a plain pad yields unstyled text and no attachment.

**FR-4.5 — Flatten on mode change** *(R1, MUST)*
Switching a pad from styled to plain MUST flatten existing content to unstyled text in place, and MUST be undoable as one operation.
*Acceptance:* flattening then undoing restores the styled content exactly, including images.

**FR-4.6 — Paste and match style** *(R1, MUST)*
Pasting without styling MUST be available under the standard system keyboard shortcut and menu item.
*Acceptance:* the standard shortcut inserts unstyled text into a styled pad.

**FR-4.7 — Standard editing behaviour** *(R1, MUST)*
The editor MUST provide spell checking, the system find bar, standard Edit and Format menu behaviour, and standard undo, at the fidelity the system text view provides them.
*Acceptance:* each is exercised once by hand per release and behaves as it does in TextEdit.

**FR-4.8 — Undo scope** *(R1, MUST)*
Undo MUST be per-pad. An undo performed in one panel MUST NOT affect another pad.
*Acceptance:* editing pad A, editing pad B, then undoing in B leaves A unchanged.

**FR-4.9 — Copy out as plain text** *(R1, MUST)*
Copying a pad's entire contents as plain text MUST be a single action.
*Acceptance:* the action places the shadow-file equivalent of the content on the pasteboard.

**FR-4.10 — Editor font** *(R1, SHOULD)*
The editor's font family and size SHOULD be settable in settings, and a change SHOULD reach text already in a pad, not only new typing. Text set in the editor's own font follows the setting. Text that arrived in a font of its own keeps it. In a plain pad, all text follows the setting. Added after R1 was feature-complete, at the author's request, for reading comfort (D-19).
*Acceptance:* raising the size enlarges the body text of an open pad immediately, and of a closed pad when it is next opened; bold survives; text pasted from a web page in its own font does not change; the choice persists across relaunch.

**FR-4.11 — Bold, italic and underline** *(R1, SHOULD)*
A styled pad SHOULD offer bold, italic and underline as on-screen controls reflecting the selection and as ⌘B, ⌘I and ⌘U. Each application MUST be one undoable step. The controls MUST NOT be available in a plain pad. Added after R1, at the author's request (D-20).
*Acceptance:* each control and shortcut toggles its trait over a selection and for subsequent typing; undo reverses one toggle; the controls are absent in a plain pad.

### FR-5 Storage and persistence

**FR-5.1 — Indefinite retention** *(R1, MUST)*
Pad content MUST be retained indefinitely without user action. There MUST NOT be any expiry, rotation, or automatic pruning of pad content.
*Acceptance:* content written and left alone is present after a system restart and after an application update.

**FR-5.2 — Transparent on-disk layout** *(R1, MUST)*
Storage MUST be flat files under the application's support directory, one directory per pad, with content, shadow text, and metadata as separate files, plus a top-level index recording order. There MUST NOT be a database.
*Acceptance:* the layout is readable and navigable with `ls` and `cat`, and deleting a pad directory by hand degrades gracefully to that pad being absent.

**FR-5.3 — Content format** *(R1, MUST)*
Styled content MUST be stored in a format that carries inline image attachments natively, without an attachment scheme of our own devising.
*Acceptance:* content written by Itchy opens in TextEdit with images intact.

**FR-5.4 — Shadow text file** *(R1, MUST)*
A derived plain-text shadow file MUST be written on every save, for every pad, regardless of mode and regardless of exposure. It MUST NOT be read back by the application and MUST NOT be treated as authoritative.

The decision to write it unconditionally is taken in preference to writing it only for MCP-exposed pads. Conditional writing would mean that enabling exposure triggers a backfill, that command-line and Spotlight readability varies per pad for reasons the user cannot see, and that the code path exercised by agents is not the one exercised in daily use. The privacy cost is real but small: the styled content sits in the same directory and is hardly less readable to anything with filesystem access. Where the residual concern bites is system-wide search, which NFR-3.4 addresses directly.

*Acceptance:* after any save, the shadow file's contents equal the plain-text extraction of the stored content; deleting the shadow file and editing the pad regenerates it; no read path in the application opens it.

**FR-5.5 — Debounced autosave** *(R1, MUST)*
Content MUST be saved after a short period of typing inactivity, and MUST be force-saved on panel close, on application termination, and on the application losing active status.
*Acceptance:* killing the process after the debounce interval has elapsed loses nothing; killing it mid-typing loses at most the interval's worth of work.

**FR-5.6 — Atomic writes** *(R1, MUST)*
Every write MUST be atomic, by writing to a temporary file in the same directory and replacing. A crash during a save MUST NOT be able to leave a pad truncated or unreadable.
*Acceptance:* a fault injected between the temporary write and the replacement leaves the previous content intact and readable.

**FR-5.7 — Metadata record** *(R1, MUST)*
A pad's metadata MUST comprise at least its identifier, display name, mode, creation and modification timestamps, window frame, pinned flag, and, from the releases that introduce them, its provenance list, exposure flag, and routing policy.
*Acceptance:* the metadata file validates against the documented shape, and an unknown field added by hand is preserved rather than discarded on the next save.

**FR-5.8 — Tolerance of external edits** *(R1, SHOULD)*
The application SHOULD NOT be damaged by a pad file being edited or removed by another process while Itchy is not running. Malformed metadata SHOULD result in that pad being reported as unreadable rather than in a failure to launch.
*Acceptance:* truncated metadata, absent content, and invalid index entries each yield a launch with the remaining pads available.

**FR-5.9 — Pad size visibility** *(R1, MUST)*
A pad's stored size MUST be surfaced to the user once it passes a threshold.
*Acceptance:* a pad grown past the threshold is marked in the menubar listing.

**FR-5.10 — No cloud sync** *(R1, MUST NOT)*
Itchy MUST NOT synchronise pad content to any remote service. The storage location being inside the user's home directory is incidental, and if the user chooses to place it in a synchronised folder that is their decision, not a feature.
*Acceptance:* no network traffic originates from the storage layer, verified by inspection and by observing the process at rest.

### FR-6 Transforms

**FR-6.1 — Uniform transform interface** *(R2, MUST)*
Transforms MUST be invoked through one interface that makes no structural distinction between deterministic and model-backed operations, beyond showing progress and offering cancellation for operations that are not instantaneous. The interface MUST be asynchronous throughout, with deterministic transforms returning immediately.
*Acceptance:* a model-backed transform added in R4 appears in the R2 menu with no change to the menu's construction.

**FR-6.2 — Deterministic transform set** *(R2, MUST)*
The following MUST be present: flatten styling, change case, pretty-print JSON, minify JSON, encode base64, decode base64, encode URL component, decode URL component, trim whitespace, sort lines.
*Acceptance:* each transform has a unit test over representative and malformed input.

**FR-6.3 — Applicability** *(R2, MUST)*
A transform MUST declare what input it applies to, and MUST NOT be offered for input it cannot handle.
*Acceptance:* decode base64 is not offered on content that is not valid base64.

**FR-6.4 — Selection scope** *(R2, MUST)*
A transform MUST operate on the current selection where one exists and on the whole pad otherwise.
*Acceptance:* pretty-printing with a JSON fragment selected leaves surrounding text untouched.

**FR-6.5 — Single-step undo** *(R2, MUST)*
Every transform MUST be applied through the store and pushed onto the pad's undo manager as one grouped operation.
*Acceptance:* one undo after any transform restores the prior content exactly.

**FR-6.6 — Failure behaviour** *(R2, MUST)*
A transform that fails MUST leave the pad unchanged and MUST report why.
*Acceptance:* a transform made to throw leaves content byte-identical and surfaces a message.

**FR-6.7 — Comparison between pads** *(R2, MAY)*
A transform MAY report the differences between two pads. This is listed because it is among the operations a user would otherwise ask a model to perform and it is deterministic, which is the point of the transform menu.

### FR-7 Provenance

**FR-7.1 — Capture on arrival** *(R2, MUST)*
When content arrives by paste or drop, Itchy MUST record the frontmost application immediately prior to the event, any URL present on the pasteboard, and a timestamp.
*Acceptance:* pasting from a browser records the application and the page URL; pasting from an application supplying no URL records the application alone without error.

**FR-7.2 — Provenance stored outside the text** *(R2, MUST)*
Provenance MUST be stored in the pad's metadata and MUST NOT be carried as text attributes.
*Acceptance:* flattening a pad to plain text leaves its provenance list intact. This is the specific reason for the requirement: attributes are what flattening destroys, and provenance whose purpose is to reconstruct what content was for must outlive that operation. **Met September 2026**, and asserted — `ProvenanceTests.survivesFlattening` flattens a styled pad through `ContentCodec` and checks both that the provenance survived and that the flatten actually happened, since the first half proves nothing without the second.

**FR-7.3 — Pad-level presentation** *(R2, MUST)*
Provenance MUST be presented at pad level, as a short list of what has been pasted into the pad and from where. Per-character attribution is explicitly not required.
*Acceptance:* the pad's provenance list is viewable from the panel and reflects the last several arrivals in order. **Met September 2026:** *Where this came from…* in the pad's actions menu, newest first, bounded to `ProvenanceBounds.limit` — "several" rather than all, because `meta.json` is rewritten in full on every save.

**FR-7.4 — Ranges are approximate** *(R2, MUST)*
An insertion range recorded with a provenance entry MUST be treated as approximate and MUST NOT be presented as authoritative. Range drift under editing is accepted rather than corrected.
*Acceptance:* heavy editing after a paste does not produce a visibly wrong claim about which text came from where, because no such claim is made. **Met September 2026** by construction: the range is recorded and never presented. A test asserts that no word in the list or its caption claims a range, position or offset, so honouring this stays deliberate rather than accidental.

**FR-7.5 — Provenance is clearable** *(R2, MUST)*
The user MUST be able to clear a pad's provenance list without altering its content.
*Acceptance:* clearing empties the list and leaves content unchanged. **Met September 2026:** the Clear button in the same sheet, and the sheet says the pad's contents are untouched — a button called Clear on a pad could reasonably be read as clearing the pad.

### FR-8 MCP server

**FR-8.1 — Pads as MCP resources** *(R3, MUST)*
Itchy MUST expose pads over the Model Context Protocol such that an agent can read from and write to them. This is the product's position rather than a feature of it, and the requirements in FR-5 exist substantially to make it possible.
*Acceptance:* a standard MCP client lists, reads and writes pads.

**FR-8.2 — Long-running server, two transports** *(R3, MUST)*
Because Itchy is a long-running application that owns the state, it MUST NOT rely on being launched as a subprocess per session. It MUST serve over a loopback-bound HTTP endpoint, and a stdio shim MUST ship alongside the application for clients that expect to launch a subprocess, doing nothing but proxying to that endpoint.
*Acceptance:* one client connects over HTTP and another over the shim, concurrently, and both see the same pad state. **Demonstrated 19 September 2026** (D-29), in the suite: `Tests/ItchyTests/ShimIntegrationTests.swift` launches the built `itchy-mcp` as a subprocess, speaks MCP to it over its standard input and output, and reads the same pad over HTTP at the same time — two sessions, one store.

**FR-8.3 — Loopback only** *(R3, MUST)*
The endpoint MUST bind to the loopback interface only and MUST NOT be reachable from another host.
*Acceptance:* a connection attempt from another machine on the network fails to establish. **Demonstrated 19 September 2026** for 0.1.1, from a second Mac on the same network with the agent server enabled. The suite covers the mechanism — the listener answers on loopback and on no other local address — but the criterion itself cannot be run from the machine under test.

**FR-8.4 — Authenticated** *(R3, MUST)*
Requests MUST be authenticated with a token held in the Keychain and surfaced in settings. The token MUST be regenerable, and regenerating it MUST invalidate the previous token.
*Acceptance:* an unauthenticated request is refused; a request with the prior token is refused after regeneration.

**FR-8.5 — Exposed surface** *(R3, MUST)*
The exposed operations MUST be limited to: list pads, read pad, append to pad, write pad, and create pad where a slot is free. No operation exposing the styled representation is required.
*Acceptance:* the tool listing contains these and nothing else.

**FR-8.6 — Reads return plain text** *(R3, MUST)*
Reading a pad MUST return plain text sourced from the shadow representation, not styled content.
*Acceptance:* reading a pad containing styled text and an image returns the text with no markup and a stable placeholder or omission for the attachment.

**FR-8.7 — Opt-in exposure per pad** *(R3, MUST)*
Pads MUST be individually opted into exposure and MUST default to not exposed. A pad that is not exposed MUST NOT be listed, readable, or writable over MCP.
*Acceptance:* an unexposed pad is absent from the listing and a direct read of it by identifier is refused.

**FR-8.8 — Writes go through the store** *(R3, MUST)*
An agent write MUST be applied through the same path a transform uses, including undo grouping, so that a write to an open pad is one undo from being reverted. Locking and merge schemes are out of scope.
*Acceptance:* an agent write to an open, focused pad is visible immediately and is reverted by one undo.

**FR-8.9 — External writes are visible** *(R3, MUST)*
A write originating outside the application MUST be indicated on the pad.
*Acceptance:* an agent write while the panel is open produces a visible indication distinguishable from the user's own editing.

**FR-8.10 — Server is optional and off by default** *(R3, MUST)*
The server MUST be disabled until enabled in settings, and its state MUST be visible.
*Acceptance:* on a fresh install nothing is listening; enabling starts the listener and disabling stops it without a relaunch.

### FR-9 Model routing

**FR-9.1 — Per-pad routing policy** *(R4, MUST)*
Each pad MUST carry a routing policy of local-only, remote-permitted, or ask-each-time, defaulting to local-only.
*Acceptance:* a newly created pad reports local-only without configuration.

**FR-9.2 — Enforcement in the service layer** *(R4, MUST)*
The policy MUST be enforced below the view layer, at a single point, so that every path that can run a transform is subject to it rather than each path being made to agree.
*Acceptance:* a remote-requiring transform run against a local-only pad is refused with the policy given as the reason, and the enforcement point is the only call site of `Transform.apply`. **Met September 2026.** Both halves: `TransformRunnerTests.refusalNamesThePolicy` checks the refusal names the policy rather than merely failing, and `Scripts/arch-lint.sh`'s third check holds `Transform.apply` to one call site on every run. This landed with Sprint 6 (D-24), ahead of the sprint that claims it.

*Amended September 2026 (D-30). The clause withdrawn read "such that a transform invoked over MCP is subject to the same restriction as one invoked from the menu", with an acceptance criterion requiring a transform to be invoked over MCP. That contradicts `FR-8.5`, which limits the exposed operations to five and whose acceptance criterion is "the tool listing contains these and nothing else" — the criterion needed a sixth tool and `FR-8.5` forbids one. D-30 declines the sixth tool and gives the reasoning; the half of this requirement that was doing the work, a single enforcement point below the view, is unchanged and already satisfied.*

**FR-9.3 — Policy visible on the pad** *(R4, MUST)*
The pad's current policy MUST be displayed in its panel.
*Acceptance:* the policy is legible without opening settings, and changes immediately when altered.

**FR-9.4 — Local inference target** *(R4, MUST)*
Local inference MUST target a locally running model endpoint, and failure to reach it MUST NOT fall back to a remote service under any policy.
*Acceptance:* with the local endpoint stopped, a local-only transform fails with a clear message and no outbound connection is made.

**FR-9.5 — Remote credentials** *(R4, MUST)*
Remote credentials MUST be held in the Keychain and MUST NOT be written to the support directory or to any log.
*Acceptance:* the support directory and logs contain no credential material after a remote transform.

**FR-9.6 — Model-backed transforms are transforms** *(R4, MUST)*
Model-backed operations MUST implement the transform protocol and MUST appear in the same menu as deterministic ones, with deterministic operations presented first.
*Acceptance:* no separate model panel, chat surface, or conversation view exists. The model is one more transform, which is the position; a chat panel would make it the centre of the product.

## 6. Non-functional requirements

### NFR-1 Responsiveness and resource use

**NFR-1.1 — First two seconds** *(R1, MUST)*
From hotkey press or menubar click to a focused, typeable pad MUST take under 250 ms on the target hardware with pads at realistic size. This is the single most consequential number in the document; the vision document's stated failure mode is friction in the first two seconds of use.
*Acceptance:* measured over twenty trials, including the first after launch, the 95th percentile is under 250 ms.

**NFR-1.2 — Editing latency** *(R1, MUST)*
Typing MUST remain responsive in a pad at the size threshold of FR-5.9, with no perceptible delay attributable to saving.
*Acceptance:* sustained typing in a pad at threshold size drops no keystrokes and shows no visible stall at save boundaries.

**NFR-1.3 — At rest** *(R1, MUST)*
With no panel open, Itchy MUST use negligible CPU and MUST NOT poll.
*Acceptance:* measured CPU over five minutes idle is indistinguishable from zero.

**NFR-1.4 — Growth is bounded and visible** *(R1, MUST)*
Pad storage MUST NOT grow without the user being able to see that it has. A pad accumulating screenshots is the expected case, and FR-4.3 and FR-5.9 together are the mechanism.
*Acceptance:* twenty full-screen Retina pastes into one pad leave it under a documented ceiling, and the pad is marked in the listing before that ceiling is reached.

### NFR-2 Reliability

**NFR-2.1 — No loss on crash** *(R1, MUST)*
An unexpected termination MUST lose at most the debounce interval's worth of typing on the pad being edited, and MUST NOT corrupt any pad.
*Acceptance:* repeated kills during editing, across all pads, produce readable pads on every subsequent launch.

**NFR-2.2 — Degraded rather than absent** *(R1, MUST)*
A fault affecting one pad MUST NOT prevent the application from launching or the other pads from being used.
*Acceptance:* the fault injection described in FR-5.8 yields a usable application.

### NFR-3 Security and privacy

**NFR-3.1 — Local by default** *(R1, MUST)*
In R1 and R2 Itchy MUST make no outbound network connection whatsoever. From R3 the application itself MUST still make none: it listens on loopback and does not dial. Only the stdio shim may open an outbound connection, and only to the loopback endpoint; from R4 the model client may open one, and only to the configured model endpoint.
*Acceptance:* observed over a working session, the process opens no outbound sockets. Enforced continuously by `Scripts/arch-lint.sh`, which confines the APIs that can open one to a named list.

*Amended September 2026. The original was scoped to R1 and R2 and said nothing about R3, which is when the requirement started to matter: the MCP server links `Network.framework` legitimately, and the release build links it into the application. The test that guarded this measured the Debug binary's load commands, where the packages link as separate frameworks and the dependency never appears — so it had been passing vacuously since `ItchyServices` became a package. A source-level rule replaces it, because "which files may dial out" is checkable and "does this binary link a networking stack" stopped being informative.*

**NFR-3.2 — Nothing exposed without opt-in** *(R3, MUST)*
No pad's content leaves the machine or becomes readable to another process as a result of a default setting. Every exposure is per-pad, opt-in, and visible on the pad.
*Acceptance:* a fresh install with the server enabled exposes nothing until pads are individually opted in.

**NFR-3.3 — Secrets in the Keychain** *(R3, MUST)*
The MCP token and any model credentials MUST be stored in the Keychain.
*Acceptance:* the support directory contains no secret material.

**NFR-3.4 — Not in system-wide search** *(R1, MUST)*
Pad contents MUST be excluded from Spotlight indexing, so that they do not surface in unrelated system searches. The mechanism is a `.noindex` directory (D-16); `~/Library/Application Support` is itself indexed, so this is a real exclusion rather than a formality. Command-line and agent readability of the shadow files under FR-5.4 is intended; appearing in a user's search results across the machine is not.
*Acceptance:* content unique to a pad returns no Spotlight hit, while `grep` over the support directory finds it.

**NFR-3.5 — No telemetry** *(R1, MUST NOT)*
Itchy MUST NOT collect or transmit analytics, crash reports, or usage data.
*Acceptance:* by inspection of dependencies and observed traffic.

### NFR-4 Platform, distribution and maintainability

**NFR-4.1 — Deployment target** *(R1, MUST)*
macOS 15 or later, per CON-5.

**NFR-4.2 — Signed and notarised** *(R1, MUST)*
Shipped builds MUST be signed with a Developer ID, MUST use the hardened runtime, and MUST be notarised.
*Acceptance:* a downloaded build launches on a machine that has never seen it, without a Gatekeeper override. **Demonstrated 19 September 2026** for 0.1.1: signed with `Developer ID Application: Timothy Howland (HPJD2255AP)`, hardened runtime, notarised and stapled — both the application and the disk image — and opened on a clean Mac with no override.

**NFR-4.3 — Core is testable in isolation** *(R1, MUST)*
The pad model, the store, and the transform protocol MUST have no dependency on AppKit or SwiftUI and MUST be exercisable from tests and from a command-line harness.
*Acceptance:* the core test target builds and passes without linking a UI framework.

**NFR-4.4 — Updates** *(R2, SHOULD)*
An update mechanism SHOULD be in place before there is any audience beyond the author. Replacing the bundle by hand is adequate until then, and this requirement exists to record that the sequencing is deliberate.

### NFR-5 Accessibility

**NFR-5.1 — Keyboard reachable** *(R1, MUST)*
Every function MUST be reachable from the keyboard.
*Acceptance:* a full session of creating, opening, editing, renaming, reordering and closing pads is completed without the pointer.

**NFR-5.2 — System text settings honoured** *(R1, MUST)*
Dynamic type sizes, increased contrast, and reduced motion MUST be honoured to the degree the system text view and standard controls provide them.
*Acceptance:* the application is usable with each accessibility setting enabled.

**NFR-5.3 — VoiceOver** *(R1, SHOULD)*
Panels, the menubar listing, and settings SHOULD be navigable and labelled under VoiceOver.
*Acceptance:* a pass through each surface reads meaningful labels rather than control class names.

## 7. Traceability

| Build step (architecture §Build order) | Requirements |
|---|---|
| 1. Status item, accessory policy, settings stub | FR-1.1, FR-1.2, FR-1.5, NFR-1.3 |
| 2. Panel subclass, window controller, frame persistence | FR-3.1–FR-3.5, FR-3.7 |
| 3. Text bridge, RTFD, shadow file, debounced atomic saves | FR-4.1–FR-4.3, FR-4.6–FR-4.8, FR-5.1–FR-5.6, NFR-2.1 |
| 4. Store-backed pad list, creation, rename, reorder, modes | FR-2.1–FR-2.8, FR-4.4, FR-4.5, FR-5.7–FR-5.9 |
| — R1 completion items not in the build order | FR-1.3, FR-1.4, FR-1.6, FR-1.7, FR-2.9, FR-3.6, FR-4.9, FR-4.10, FR-4.11, NFR-1.1, NFR-3.4 |
| 5. Transform menu | FR-6.1–FR-6.6 |
| 6. Provenance | FR-7.1–FR-7.5 |
| 7. MCP server and shim | FR-8.1–FR-8.10, NFR-3.2, NFR-3.3 |
| 8. Model routing | FR-9.1–FR-9.6 |

Two R1 requirements sit outside the architecture document's build order and are worth flagging as additions to it: the global hotkey (FR-1.4), which was an open question there and is now required, and the lazy content loading needed to meet the launch budget (FR-1.6).

## 8. Decisions recorded here

Three questions left open by the architecture document are settled by this document, and the reasoning is kept with the requirement rather than summarised here: pad count is a configurable default of nine with a hard ceiling of twenty (FR-2.1), the global hotkey to the last-used pad is in the first release (FR-1.4), and the shadow text file is written for every pad unconditionally, with the residual privacy concern addressed by excluding the support directory from Spotlight (FR-5.4, NFR-3.4).

## 9. Questions still open

Whether the size threshold in FR-5.9 and the downsample dimension in FR-4.3 should be user-visible settings or fixed constants. The inclination is fixed constants, on the grounds that a setting implies the user should have a view about it.

Whether per-pad exposure under FR-8.7 should additionally expire, so that a pad opted in for one session does not remain readable indefinitely. This trades a real risk against a friction cost in exactly the two seconds NFR-1.1 protects.

What FR-8.6 should return in place of an image attachment — a placeholder that tells the agent an image is present, or nothing at all. The former is more truthful and invites the agent to ask for something we do not expose.

Whether a pad should be able to be promoted out of Itchy into whatever system holds permanent content, as an explicit export action, and if so whether that belongs in R2 alongside the transforms. The vision document's position is that Itchy's job at that point is to export cleanly and let go, which is an argument that some such action must exist.

## 10. Definition of success

The requirements above are the means, not the measure. The measure is stated in the vision document and is restated here as the criterion against which the first release is judged: if, a month after the first release is in daily use, working text is still being routed through messages-to-self and untitled editor windows, the release has failed regardless of how many of these requirements it satisfies. NFR-1.1 is the requirement most likely to be the difference, and should be treated as the one not to trade away.
