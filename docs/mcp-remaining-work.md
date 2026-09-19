# What remains before the MCP server can be switched on

*Written September 2026, with Sprint 8 half complete. This is a working
document, not a governing one: when the work described here is done, it is
deleted and what it decided lives in `docs/decisions/`.*

## Where things stand

The decision layer of the MCP server exists and is tested. `MCPToolSurface`
holds the five tools of `FR-8.5`; `PadResolver` turns a `pad` argument into an
identifier, or into an explicit list of candidates when a name is ambiguous;
`ExposurePolicy` narrows the pad list before the router ever sees it, so
`FR-8.7`'s rule that an unexposed pad is indistinguishable from a nonexistent
one holds structurally rather than by remembering to filter; `MCPToken` and
`MCPAuthorization` settle `§11.2`; `MCPService` executes what the router
produced against the store.

None of it is reachable. There is no socket, nothing writes `endpoint.json`, and
there is no setting that turns anything on. The server is off by default in the
strongest possible sense, which is that it does not exist at runtime.

What follows is the remaining work, in the order the dependencies impose.

## Sprint 8, remainder

### 1. The loopback listener

This is the substantial piece and the reason the sprint stopped where it did.

D-17 established the division of labour: `StatefulHTTPServerTransport` exposes
`handleRequest(HTTPRequest) async -> HTTPResponse` and owns protocol
conformance, session state and version negotiation, while the socket is ours.
That is the right split — MCP framing is the part that is 90% correct for a year
and then quietly wrong — but it does mean writing an HTTP/1.1 server.

What the listener has to do:

- Bind an `NWListener` to `127.0.0.1` explicitly, never `0.0.0.0` (`FR-8.3`).
  The bound port is not necessarily the configured one, and the actual value is
  what goes into `endpoint.json`.
- Parse HTTP/1.1 well enough for a single-purpose endpoint: request line,
  headers, and a `Content-Length` body. Not chunked request bodies; an MCP
  client has no reason to send one, and accepting a subset deliberately is
  better than accepting a superset accidentally.
- Build the SDK's `HTTPRequest(method:headers:body:path:)` and hand it over.
- Serialise the `HTTPResponse` back. Four of its five cases are ordinary
  responses. The fifth is not: `.stream(AsyncThrowingStream<Data, Error>)` is
  the server-to-client SSE channel, which means holding the connection open,
  writing `text/event-stream` framing as each `Data` arrives, and closing
  cleanly when the stream finishes or the client disconnects. This is where the
  bugs will be, and it is the reason this was not rushed at the end of a
  session.
- Refuse before the SDK sees anything, when the bearer token is absent or wrong
  (`MCPAuthorization`, already written and tested). The SDK's default validation
  pipeline already includes `OriginValidator.localhost()`, which D-17 found
  covers most of `FR-8.3`'s origin checking — and which refuses an `Origin`
  without a port, a detail that cost the spike an hour and will cost this one
  the same if it is forgotten.

The listener performs; it decides nothing. Whether a request is authorised is
already a decision made elsewhere, and if anything else in the listener turns
out to need deciding, it comes out into a value type before the sprint exits
(D-11).

### 2. `endpoint.json`

The shim reads the port from a small file in the support directory (`§11.1`).
Writing it is constrained: `CON-4` makes the store the only component that
touches disk, and `Scripts/arch-lint.sh` enforces that by grepping for
`FileManager` outside `ItchyCore/Store`. So this is not a file the services
layer writes — it needs a small store API, alongside `PadStorageLayout`'s other
paths, that the app calls when the listener has bound and again when it stops.

Two things follow from that placement. The file must be removed on stop, or a
stale port outlives the listener and the shim connects to nothing. And its write
is not atomic-by-accident: it goes through the same atomic write the store uses
for everything else, because a half-written `endpoint.json` read by a shim
starting concurrently is exactly the sort of fault that appears once a month and
is never reproduced.

### 3. The attachment placeholder in the shadow text

`FR-8.6` requires that reading a pad with an image returns the text with a
stable placeholder, and `§11.4` fixes the form: a single line reading
`[image 1240×820]`. Reads return the shadow representation, so the placeholder
has to be in `PadContent.plainText` rather than applied afterwards — by the time
the services layer has the plain text, the attachment's dimensions are gone.

That puts the change in `ContentCodec`, at the platform boundary, where the
`NSTextAttachment` and its image are still in hand. Today the extraction is
`attributed.string`, which leaves a bare `U+FFFC` object replacement character
in its place.

Consequences worth stating before doing it, because this changes a file format:

- The shadow file on disk changes for any pad containing an image. That is a
  readability improvement — `U+FFFC` means nothing to `grep` or to a human — but
  it is a change to something `FR-5.4` describes as derived and never read back,
  so nothing should depend on it, and this is the test of whether that is true.
- `PadStoreFault.shadowDesynchronised` compares the shadow against the content's
  plain text. Both derive from the same field, so they stay consistent, but the
  comparison should be re-read rather than assumed.
- A pad written by an older build has a shadow containing `U+FFFC` and will be
  rewritten on the next save. No migration is needed, because the shadow is
  derived; if one turns out to be needed, the derivation is wrong.

### 4. Settings, and visible state

`FR-8.10` requires the server to be off until enabled, and its state to be
visible, and enabling and disabling to take effect without a relaunch. `FR-8.4`
requires the token to be surfaced in settings with regeneration that invalidates
the previous one immediately.

What that needs:

- Fields on `AppSettings`: whether the server is enabled, and the configured
  port. Both go through the same `SettingsModel` validation and clamping the
  other settings use.
- A settings section, alongside the existing archive and editor-font ones, with
  the enable toggle, the port, the token shown with a copy button, and a
  regenerate button. Regeneration replaces the Keychain item and the listener's
  in-memory copy in one step — `MCPTokenKeychain.save` already deletes before
  adding for exactly this reason, so that a failed update cannot leave the old
  token working.
- The listening state shown in the menubar while active (`§11.8`), which means a
  decision about what the status item shows and therefore a row in `MenuModel`
  rather than a branch in a view.
- The per-pad exposure segment already exists in `StatusBarModel` behind a
  `showsExposure` flag that nothing sets yet. Turning it on is part of this, not
  of Sprint 9, because a pad that is exposed must say so on the pad (`NFR-3.2`).

### 5. Wiring

Registering the five tools and the resource list against the SDK's `Server`,
starting and stopping the listener as the setting changes, and tearing it down
at termination alongside the existing flush. The tool handlers convert the SDK's
`Value` arguments into the `[String: String]` the router takes — the router is
deliberately free of SDK types so that it stays testable without one, and the
conversion is the only place that boundary is crossed.

### 6. What the sprint has to demonstrate

`FR-8.1`–`FR-8.6` and `FR-8.10` are claimed here. Most are automatable against a
listener bound to an ephemeral port:

- A real MCP client handshake over HTTP, listing and reading pads.
- An unauthenticated request refused; a request bearing the previous token
  refused after regeneration (`FR-8.4`).
- The tool listing containing the five tools and nothing else (`FR-8.5`).
- A pad with styled text and an image reading back as plain text with the
  placeholder (`FR-8.6`).
- Nothing listening on a fresh store; enabling starts and disabling stops the
  listener without a relaunch (`FR-8.10`).

`FR-8.3`'s acceptance criterion — a connection attempt from another machine
fails — cannot be run from the machine under test and belongs on the manual
checklist in `§14.6`, next to the Gatekeeper check that is there for the same
reason. What *can* be tested here is that the listener refuses a connection to
its port on a non-loopback local address.

## Sprint 9, the write path and the safety that goes with it

The plan separates these from Sprint 8 deliberately, because exposure and
write-conflict policy are the two questions the architecture document says must
be answered before the feature ships, and bundling them with transport work is
how they get answered in a hurry. That reasoning still holds.

### The registry-aware writer

`PadContentWriter` is already a seam, and `StorePadWriter` already implements
the closed-pad case. What Sprint 9 adds is the open-pad case: when the pad's
panel is on screen, the write goes through `PadTextCoordinator`'s grouped
applier so that it is one undo from reverted (`FR-8.8`), and when it is not, it
goes to the store. The registry knows which, which is why `PadWindowRegistry`
exists and why the applier was registered with it in Sprint 3.

Note what the applier's recent correction means here: it now replaces the range
rather than merging attributes into it, so an agent write lands as written
rather than inheriting whatever styling happened to be at the insertion point.

### Per-pad exposure

The model has `isExposedToMCP` and the store has `setExposedToMCP`; what is
missing is the toggle in the pad settings sheet and the confirmation that the
default is off end to end (`NFR-3.2`). `MCPService.create` currently exposes a
pad it creates, on the reasoning that a pad an agent made and then cannot read
reads as a failure. That is a decision, it is not in the specification, and it
should either be recorded or reversed before it ships.

### External-write visibility

`ExternalWriteMarker` is in the model and the store sets it on every non-user
write — the tests for that are in place and one of them was the flaky test fixed
this sprint. What is missing is the presentation: `BannerModel.state(for:now:)`
has had a row in the seams table since the specification was written and does
not exist yet. It decides whether the banner is visible, its wording, and
whether undo is offered. The menubar indicator for a pad written while closed
belongs with it (`FR-8.9`, `§11.7`).

### The stdio shim

`Shim/itchy-mcp` proxies stdio to the loopback endpoint and holds no protocol
logic (`FR-8.2`). It reads the port from `endpoint.json` and the token from the
Keychain.

**This one is blocked on a person.** Reading the same Keychain item from two
binaries needs a shared access group, which needs both binaries signed by the
same team — so the shim cannot be finished before the Developer ID certificate
that R1 is already waiting on. `MCPTokenKeychain` therefore stores the item
under a plain service and account today, with no access-group attribute, and
adding one is a change to where the item lives: the old item is not found under
the new query, so it needs a migration or a regeneration, and regeneration is
cheap because the token is not a secret anyone has memorised.

`FR-8.2`'s acceptance criterion — one client over HTTP and another over the
shim, concurrently, both seeing the same pad state — cannot be demonstrated
until then.

## Decisions still open

**The default port.** `§11.1` says "8-something in the ephemeral-adjacent
range, configurable", which is not a number. It wants to be memorable, unlikely
to collide with a development server, and outside the range macOS hands out
ephemerally. It needs choosing and recording.

**Whether the write tools ship in Sprint 8.** `append_pad`, `write_pad` and
`create_pad` are routed and tested, and they work through `StorePadWriter`,
which is correct whenever the pad's panel is closed. Against an *open* pad it is
not: the panel holds the authoritative text and would overwrite the agent's
write on its next save. Nothing is at risk today because the server does not
listen and no pad is exposed. The options are to keep the three write tools out
of the advertised tool list until the registry-aware writer exists, or to ship
them and accept that an agent writing to an open pad loses the write. The first
is the default unless someone argues for the second, and it costs one line in
`MCPToolSurface.all` plus a test asserting the list is two tools rather than
five while the flag is off.

**Whether `create_pad` exposes what it creates.** Described above; currently
yes, and undocumented.

## Blocked on a person, in summary

| What | Why |
|---|---|
| The stdio shim (`FR-8.2`) | Shared Keychain access group needs both binaries signed by the same team |
| `FR-8.3`'s acceptance criterion | Needs a second machine on the network |
| `FR-8.2`'s acceptance criterion | Needs the shim |

Everything else in this document can be done from here.
