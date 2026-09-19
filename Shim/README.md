# itchy-mcp

The stdio shim, built in Sprint 9 (`FR-8.2`).

It proxies stdio to the loopback endpoint and does nothing else: it holds no
state and implements no protocol logic, reading the port from `endpoint.json` in
the support directory and the token from the Keychain via a shared access group.

If it ever grows a single protocol-aware line, that is a defect — the whole point
of the arrangement is that the protocol surface exists in one place while
remaining compatible with clients on either transport (specification §11.1).

**Not started, and no longer blocked.** It waited on a Developer ID certificate,
because reading one Keychain item from two binaries needs a shared access group
and that needs both binaries signed by the same team. The certificate arrived in
September 2026, so this is now ordinary work that has not been done.

Three things are known before it starts, and one is not:

- The port comes from `endpoint.json`, which the store writes atomically when the
  listener binds and removes when it stops (D-25). A file that is present is not
  proof a server is listening — it carries the process identifier so a stale one
  left by a crash can be recognised.
- `MCPTokenKeychain` currently stores the token under a plain service and account
  with no access-group attribute. Adding one moves the item, so the old one is
  not found under the new query. Regenerate rather than migrate: the token is not
  a secret anybody has memorised, and `FR-8.4` already makes regeneration a
  supported act.
- The shim holds no protocol logic. If it ever grows a single protocol-aware
  line, that is a defect — the point of the arrangement is one protocol surface
  serving both transports (specification §11.1).
- **Unknown:** whether `keychain-access-groups` needs anything beyond a shared
  team for a directly-distributed, non-sandboxed build. It should not. "Should
  not" is what spikes are for, and this one is an afternoon.

Until it exists, `mcp-remote` bridges stdio to the loopback endpoint for clients
that need it; the in-application help says how. The shim replaces that with
something that needs no Node, ships in the same bundle, and reads the token
itself rather than having it pasted into a configuration file.

See `../docs/mcp-remaining-work.md`.
