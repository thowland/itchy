# D-29 — The shim takes its token from the environment, not the Keychain

*Taken September 2026, immediately after the spike that was supposed to confirm
the opposite.*

## What §11.1 said

> It reads the port and token from the same well-known location the app writes
> them to — the port from a small `endpoint.json` in the support directory, the
> token from the Keychain via a shared access group.

That sentence had been in the specification since it was written, and
`mcp-remaining-work.md` carried the note that whether a shared access group
needed anything beyond a shared signing team was "the first thing to find out
when the shim is written. It should not, for Developer ID signing, but 'should
not' is what spikes are for."

It does. The spike is why this decision exists.

## What the spike found

Two binaries, both signed with the same Developer ID, both carrying
`keychain-access-groups` with the team-prefixed group
`HPJD2255AP.com.wdogsystems.itchy`, reading a generic password from the
data-protection keychain.

| Signing | Result |
|---|---|
| Ad-hoc, no entitlement | runs; `errSecMissingEntitlement` (−34018) |
| Developer ID, no entitlement | runs; `errSecMissingEntitlement` (−34018) |
| Developer ID + entitlement | **killed at launch (SIGKILL)** |
| Developer ID + entitlement, hardened runtime | **killed at launch (SIGKILL)** |
| Developer ID + entitlement, wrapped in an `.app` bundle | **killed at launch (SIGKILL)** |

So the entitlement is genuinely required — without it the keychain refuses the
access group outright — and carrying it without a provisioning profile that
authorises it gets the process killed by AMFI before `main` runs. A shared team
is not enough. It needs an App ID registered with Keychain Sharing and an
`embedded.provisionprofile` in the bundle, which is portal work: another item
blocked on a person, for a convenience.

One thing worth keeping from the spike regardless: the data-protection keychain
(`kSecUseDataProtectionKeychain`) answers with an *error* where the file-based
keychain shows the user a permission dialogue. That is the difference between a
failing shim and a hung one, and it is why the spike could be run at all without
the machine stopping to ask a question.

## What was decided

The shim reads the token from the `ITCHY_TOKEN` environment variable.

This is what every other client already does with this token. Claude Code takes
it as a header in its own configuration; Codex names an environment variable for
it. The shim asking for the same variable is one fewer concept, not one more.

`NFR-3.3` is untouched: the token still *lives* in the Keychain, written and
read by the application. The shim is handed a copy by whoever launches it, which
is the person who copied it out of Settings in the first place.

`§11.1` is amended in the same commit, because it described an arrangement now
known not to work.

## What else the shim turned out to need

**It holds one piece of state.** §11.1 said it "holds no state", and that is one
word too strong. The server issues a session identifier at initialisation and
requires it on every request after; the shim captures it from the response
header and sends it back. It never reads it. The rule that matters — no protocol
logic — is intact: nothing in the shim knows what an MCP message *means*.

**It parses server-sent events.** The server answers a request with an event
stream rather than a plain body, so the shim has to pull the `data:` payloads
out. That is framing, not protocol, and it lives in a value type with the stdio
line framing beside it.

**It reports transport failures as JSON-RPC errors with a null id.** Echoing the
request's identifier would mean parsing the request, and a shim that parses
requests is one change from interpreting them. The client sees an error; the
useful detail goes to standard error, where its log will show it.

**A `--support-root` flag.** `FR-8.2`'s acceptance criterion — two clients, two
transports, one pad — cannot be demonstrated against a throwaway store without
one. An argument rather than an environment variable, deliberately: whoever sets
it decides which server the token is handed to, so it belongs somewhere visible
in a client's configuration and in `ps`.

## What it replaces

`mcp-remote`, which the help recommended for Claude Desktop in the interim. The
shim needs no Node, ships inside the bundle already signed and notarised with
it, and is one fewer third party handling the token.

## What would reverse it

Someone registering an App ID with Keychain Sharing and embedding the profile,
which would let the shim read the token itself and remove the one piece of
configuration a person has to copy. That is a real improvement and a small one;
it is not worth blocking the shim on, which is the whole point of this decision.
