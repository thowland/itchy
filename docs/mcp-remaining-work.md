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

**Done**, September 2026. `Shim/itchy-mcp` ships inside the bundle, signed and
notarised with the application, and `FR-8.2`'s acceptance criterion is
demonstrated in the suite rather than described here.

The one thing that did not go as this document predicted is recorded in D-29:
the token comes from `ITCHY_TOKEN` rather than a shared Keychain access group,
because the entitlement that makes an access group work needs a provisioning
profile, and a Developer ID binary carrying it without one is killed at launch.
This document said that "should not" be so, and that "should not is what spikes
are for". It was, and it was.

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
