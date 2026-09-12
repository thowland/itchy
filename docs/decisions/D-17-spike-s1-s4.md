# D-17 — Spikes S-1 and S-4 resolved

*Run before Sprint 5, alongside S-3.*

## S-1 — Carbon `RegisterEventHotKey` on macOS 26

D-6 chose `RegisterEventHotKey` over `NSEvent.addGlobalMonitorForEvents` because
the monitor requires the Accessibility permission — a system prompt, a trip to
System Settings, and a support surface, all to read one key combination. The
`[VERIFY]` mark asked whether the Carbon API still works.

**It registers.** `InstallEventHandler` returns `noErr`, `RegisterEventHotKey`
returns `noErr` with a non-nil `EventHotKeyRef` for ⌃⌥Space, and
`AXIsProcessTrusted()` is `false` throughout — which is the decisive point. The
API is available and needs no permission, so D-6 stands and `FR-1.4` does not
drag a permission prompt into the first release.

**Live firing was not confirmed programmatically.** Synthesised events posted
through `CGEvent.post` on all three tap locations were dropped, because posting
events is itself gated by a permission this process does not hold. That is a
limitation of the test, not evidence against the API: registration succeeding is
what registration means. Confirming a real keypress needs a human, and it is on
the Sprint 5 manual checklist rather than pretended to here.

## S-4 — Does the official MCP Swift SDK fit a long-running host?

D-5 defaulted to the SDK if its HTTP server transport suits an application that
owns the state and cannot be launched per session, with Hummingbird plus a
hand-written protocol layer as the fallback.

**The SDK fits, and in exactly the shape §11.1 describes.** Resolved at 0.12.1
and built against Swift 6.2. `StatefulHTTPServerTransport` owns no socket: it
exposes `handleRequest(HTTPRequest) async -> HTTPResponse`, so the host binds the
listener and the SDK owns protocol conformance and session state. That is the
right division — the socket is the easy part, and MCP framing, session handling
and protocol versioning are the parts that are 90% correct for a year and then
silently wrong.

Demonstrated end to end: a `Server` with a `list_pads` tool, started against the
transport, answering a synthetic `initialize` with `200`.

Two findings worth carrying into Sprint 8:

- The default validation pipeline already includes `OriginValidator.localhost()`,
  which is most of `FR-8.3`. It matches `http://127.0.0.1:<port>` and requires
  the port: an origin without one is refused with `403`. The spike hit that and
  it looked like a failure until the validator was read.
- The `MCP` product pulls only `swift-system`, `swift-log` and `eventsource`.
  NIO and atomics appear in the resolved graph but belong to the SDK's own
  conformance and test targets, not to the library we would link.

D-5's fallback is not needed. An HTTP listener is still ours to write, and the
choice between `NWListener` and a NIO-based server is now a much smaller question
than it was, because it no longer carries the protocol with it.
