# D-25 — The MCP server: one socket, one session per client, and refusal over loss

*Taken September 2026, during Sprint 8 and the unblocked half of Sprint 9.
Supersedes `docs/mcp-remaining-work.md`, which was a working document and is now
reduced to the one thing still blocked on a person.*

## What was decided

Eight things, taken together because they are one piece of work and several of
them only make sense in the presence of the others.

### The default port is 8899

`§11.1` asked for "8-something in the ephemeral-adjacent range, configurable"
and declined to give a number. 8899 is well clear of 49152–65535, the range
macOS hands out ephemerally, so it cannot collide with a port the system
assigned to something else, and it is neither a registered service nor a common
development default.

It remains configurable. A configured port between 1 and 1023 takes the default
rather than being clamped to 1024, because an accessory application cannot bind
a privileged port and a person who typed 80 wanted a working server rather than
the nearest legal number. Zero is permitted and means "any free port"; it is
what the tests bind.

The *bound* port, not the configured one, is what reaches `endpoint.json` and
what the settings window names when the two differ. Asking for 8899 and getting
8899 is the common case, not a guarantee, and a person reading the field, then
reading the shim's error, otherwise has no way to connect the two.

### HTTP is accepted as a deliberate subset

D-17 divided the labour: `StatefulHTTPServerTransport` owns protocol
conformance, session state and version negotiation, and the socket is ours. Ours
therefore includes an HTTP/1.1 reader, and it reads a subset on purpose: request
line, headers, and a `Content-Length` body. Chunked request bodies are refused
with `411` rather than half-read. An MCP client has no reason to send one, and
accepting a subset deliberately is better than accepting a superset
accidentally.

The framing is a value type — `HTTPRequestParser` in, `HTTPResponseWriter` out —
so that a header block split across two reads, a body arriving after its
headers, two requests in one buffer and a header line without a colon are all
tests that hand it bytes rather than tests that open a socket. That is the
difference between knowing the parser is right and hoping.

`FR-8.3`'s loopback binding is structural rather than checked: the listener sets
`requiredLocalEndpoint` to `127.0.0.1`, so the socket is not reachable on any
other address this machine has. A check in a handler is a check someone can
forget to write; a socket that was never bound elsewhere is not.

### One SDK server and transport per session

`StatefulHTTPServerTransport` holds exactly one session, and `FR-8.2` wants the
shim and a direct HTTP client connected at the same time, both seeing the same
pad state. So the host keeps one `Server` and one transport per session, and
`MCPSessionRouter` decides which a request belongs to: a known identifier routes
to its session, an initialisation with none starts one, an unknown identifier
answers `404` — which tells a client to initialise again rather than retry — and
anything else without one answers `400`.

They do see the same pads, because the state is the store's and not the
session's. The sessions hold protocol state and nothing else.

A re-initialisation naming an existing session goes to that session rather than
starting a second one. Re-initialising is the transport's error to report;
papering over it would hide a client bug and leak a session per attempt.

### `endpoint.json` is written by the store

`CON-4` makes the store the only component that touches disk, and
`Scripts/arch-lint.sh` enforces that textually. The listener is in the services
layer and the settings section is in the app, and neither may open a file — so
the endpoint file needed an owner in the store, and `EndpointStore` is it.

Two things follow from that placement rather than being remembered separately.
It is removed on stop and again at termination, because a stale port outlives
the listener and the shim connects to nothing. And it goes through the same
atomic write as everything else, because a half-written `endpoint.json` read by
a shim starting concurrently is exactly the fault that appears once a month and
is never reproduced.

### The write tools shipped in Sprint 8, and refusal was the interim rule

`append_pad`, `write_pad` and `create_pad` were advertised from the start rather
than held back until the registry-aware writer existed.

The consequence was real and was stated plainly at the time: `StorePadWriter` is
correct whenever the pad's panel is closed and wrong when it is open, because
the panel holds the authoritative text and its next save writes the panel's
version over the agent's — within about 120 ms of the next keystroke, and
unconditionally when the pad closes.

The cheap mitigation was to refuse rather than lose, and that is what
`OpenPadPolicy` does. An honest refusal is something an agent can report; a
success that did nothing is not. Losing a write silently is the one failure mode
this project's storage rules are otherwise written to prevent, and it would have
been odd to introduce it at the MCP boundary alone.

The refusal has now lapsed, because `RegistryPadWriter` reaches open pads — but
it lapsed by the policy answering differently, not by the policy being deleted.
`itchyctl`'s writer still cannot reach an open pad, and still gets the refusal.

### `create_pad` exposes the pad it creates

A pad an agent made and then cannot read reads as a failure of the tool rather
than as a safety property, so the pad is exposed at creation.

This is consistent with `NFR-3.2` rather than an exception to it. The
requirement is that no pad's content becomes readable to another process *as a
result of a default setting*, and a pad that did not exist until the agent asked
for it has no content the person put there. Existing pads remain opt-in, and the
new pad shows "exposed" on itself, so the person can see what was made and
withdraw it.

### An image is `[image 1240×820]` in the shadow text

`FR-8.6` requires that reading a pad with an image returns the text with a
stable placeholder, and `§11.4` fixed the form. Reads return the shadow
representation, so the placeholder has to be in `PadContent.plainText` rather
than applied afterwards: by the time the services layer has the plain text, the
attachment's dimensions are gone.

That put the substitution in `ContentCodec`, at the platform boundary, where the
`NSTextAttachment` and its image are still in hand. The offsets are UTF-16,
because that is what `NSAttributedString` indexes by; walking `Character`s
instead desynchronises at the first emoji, and the symptom is a placeholder
carrying the wrong image's size.

This changes the shadow file on disk for any pad containing an image. That is a
readability improvement — `U+FFFC` means nothing to `grep` or to a person — and
it is a change to something `FR-5.4` calls derived and never read back. No
migration: a pad written by an older build is rewritten on its next save. If a
migration ever turns out to be needed, the derivation is wrong.

For the record, the check the working document asked for: nothing computes
`PadStoreFault.shadowDesynchronised`. The case exists and is presented; there is
no comparison to re-read.

### The banner says when it cannot undo

`BannerModel` decides three things: whether the banner appears, what it says,
and whether undo is offered. The third is the one that had to be decided rather
than assumed.

The text view's undo stack begins when the panel opens, so a write that arrived
while the pad was closed has nothing on it to revert. An Undo button that looked
live would revert the person's own last edit instead. The banner therefore says
that the write arrived while the pad was closed and offers no undo — which is
the compensating control D-9's consequence asked for, stated rather than
implied. The menubar marks the pad as well, because the menu is where the person
will next look at it.

A marker stops being shown after a day. Long enough to survive a lunch break,
which is the point; beyond that it is history rather than news, and the pad's
own text is the record.

## What this cost, and what it bought

The subset HTTP reader is roughly two hundred lines that a framework would have
supplied. In exchange, Itchy ships with one dependency rather than a web server,
the failure modes are ones we wrote down, and the whole of the wire format is
tested without a socket.

One transport per session is more objects than one transport. In exchange,
`FR-8.2` is satisfiable rather than aspirational, and a client that misbehaves
loses its own session rather than everyone's.

## What would reverse it

A second client needing server-initiated messages would make the standalone GET
stream load-bearing, which it is not today — it works, and nothing uses it. If
that changes, the session map becomes the place that has to survive a
reconnection, and it does not try to today.

If the loopback listener ever needs to serve something that is not MCP, the
subset HTTP reader stops being a reasonable place to stand and a real server
becomes the honest answer. Nothing plans to.

## Still blocked on a person

*Superseded in part, later in September 2026: the Developer ID Application
certificate has since been issued — `Timothy Howland (HPJD2255AP)` — so the
shim is no longer blocked, only unwritten. What is still missing for a release
is the `notarytool` credential profile. The rest of this section stands as the
description of the work.*

The stdio shim (`FR-8.2`). Reading the same Keychain item from two binaries
needs a shared access group, which needs both binaries signed by the same team,
which needs the Developer ID certificate R1 is already waiting on.
`MCPTokenKeychain` stores the item under a plain service and account, with no
access-group attribute; adding one moves the item, so it needs a migration or a
regeneration — and regeneration is cheap, because the token is not a secret
anyone has memorised.

`FR-8.3`'s acceptance criterion needs a second machine and is on the manual
checklist in `§14.6`. What is tested here is the mechanism behind it: the port
answers on loopback and on no other local address this machine has.
