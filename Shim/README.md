# itchy-mcp

The stdio shim (`FR-8.2`). It proxies stdio to the loopback endpoint and does
nothing else, for clients that expect to launch a subprocess rather than connect
to an address — Claude Desktop, principally.

It reads the port from `endpoint.json` in the support directory, through the
store's own API, and the token from the `ITCHY_TOKEN` environment variable. It
was to have read the token from the Keychain via a shared access group; D-29
records the measurements that ruled that out, the short version being that the
entitlement needs a provisioning profile and a Developer ID binary carrying it
without one is killed before `main` runs.

## The rule

No protocol logic. If it ever grows a line that knows what an MCP message
*means*, that is a defect — the point of the arrangement is one protocol surface
serving both transports (specification §11.1).

Two things it does hold, both framing rather than protocol:

- the session identifier the server issues at initialisation and requires
  afterwards, which it stores and never reads;
- enough of `text/event-stream` to pull out the `data:` payloads, because the
  server answers a request with a stream rather than a body.

## Layout

`ItchyMCPShimCore` is the library — configuration, framing, the proxy — and
`itchy-mcp` is a one-file executable over it. The split exists so the parts
worth testing can be imported, by this package's tests and by the application's
suite, which launches the binary to demonstrate `FR-8.2`.

It depends on `ItchyCore` alone. It must not acquire the MCP SDK: a shim that
can parse the protocol is a shim that will end up interpreting it.

## Running it by hand

```bash
ITCHY_TOKEN="$(: paste from Settings → Agents)" \
  build/Itchy.app/Contents/MacOS/itchy-mcp
```

`--support-root PATH` points it at a support directory other than the standard
one. It exists so `FR-8.2` can be demonstrated against a throwaway store, and it
is an argument rather than an environment variable on purpose: whoever sets it
decides which server the token is handed to.

## Where it ships

`Contents/MacOS/itchy-mcp`, inside the application bundle, universal and signed
with the same Developer ID. `make app` builds and seals it; `Scripts/release.sh`
signs it before the bundle so the outer seal covers it, and refuses to call a
build releasable if it is missing.
