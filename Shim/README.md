# itchy-mcp

The stdio shim, built in Sprint 9 (`FR-8.2`).

It proxies stdio to the loopback endpoint and does nothing else: it holds no
state and implements no protocol logic, reading the port from `endpoint.json` in
the support directory and the token from the Keychain via a shared access group.

If it ever grows a single protocol-aware line, that is a defect — the whole point
of the arrangement is that the protocol surface exists in one place while
remaining compatible with clients on either transport (specification §11.1).
