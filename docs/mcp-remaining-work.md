# What remains before the MCP server is finished

*Rewritten September 2026. This is a working document, not a governing one:
when the work described here is done, it is deleted. Everything it used to
describe has been built, and what it decided lives in
[`decisions/D-25-mcp-server.md`](decisions/D-25-mcp-server.md).*

## Where things stand

The server runs. It binds `127.0.0.1`, serves the five tools of `FR-8.5` and the
resource list of `FR-8.1` over HTTP to a real MCP client, refuses an
unauthenticated request before the SDK sees it, writes and removes
`endpoint.json`, and is off until somebody switches it on. Per-pad exposure has
a toggle, an exposed pad says so on itself, an agent's write into an open panel
is one undo from reverted, and a write the person did not see is marked on the
pad and in the menubar.

`FR-8.1`, `FR-8.3`–`FR-8.10` are demonstrated by the suite. What follows is what
is not.

## The stdio shim (`FR-8.2`)

**Blocked on a person, and it is the same person the release is already waiting
on.**

`Shim/itchy-mcp` proxies stdio to the loopback endpoint and holds no protocol
logic. It reads the port from `endpoint.json` — which now exists and is written
atomically — and the token from the Keychain.

The Keychain is the blocker. Reading the same item from two binaries needs a
shared access group, which needs both binaries signed by the same team, which
needs the Developer ID Application certificate `NFR-4.2` is already waiting for.
`MCPTokenKeychain` therefore stores the item under a plain service and account
with no access-group attribute, and adding one is a change to where the item
lives: the old item is not found under the new query, so it needs a migration or
a regeneration. Regeneration is the right answer, because the token is not a
secret anyone has memorised.

Until then, `FR-8.2`'s acceptance criterion — one client over HTTP and another
over the shim, concurrently, both seeing the same pad state — cannot be
demonstrated. Half of it can: two HTTP clients are connected concurrently in the
suite and do see the same pad, because the state is the store's rather than the
session's. What is untested is the shim, not the concurrency.

## What needs a second machine

`FR-8.3`'s acceptance criterion is that a connection attempt from another
machine fails. It cannot be run from the machine under test and is on the manual
checklist in specification `§14.6`, next to the Gatekeeper check that is there
for the same reason.

What is tested here is the mechanism behind it: the listener pins its local
endpoint to `127.0.0.1`, and the suite confirms the port answers there and on no
other local address this machine has.

## What is worth doing and is not required

Nothing blocks a release. These are noted so that they are decisions rather than
omissions:

- **The standalone GET stream works and nothing uses it.** Itchy sends no
  server-initiated messages, so the SSE channel carries responses and nothing
  else. If a notification is ever wanted — a pad changed under the agent's feet
  — the session map becomes the thing that has to survive a reconnection, and it
  does not try to today.
- **A tool call's text is the whole result.** `CallTool.Result` carries a
  `structuredContent` the five tools do not use. `list_pads` in particular could
  return rows rather than lines. It would be a better answer for a client that
  wanted to sort them, and no client has asked.
