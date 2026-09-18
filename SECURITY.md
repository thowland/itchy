# Security

## Reporting a vulnerability

Please do not open a public issue for a security problem. Report it privately
through GitHub's **Report a vulnerability** button on the repository's
**Security** tab, or directly at
<https://github.com/thowland/itchy/security/advisories/new>. That opens a private
advisory visible only to the maintainer.

Include what an attacker could do, the steps to reproduce it, and the Itchy and
macOS versions affected. You will get an acknowledgement, and a fix or an
explanation, as promptly as a one-person project allows.

## Scope

Itchy today stores pads as files in the user's Library folder and makes no
network connections. Areas of particular interest:

- Pad content, or backups of deleted pads, becoming readable where they should
  not be, including through Spotlight indexing (`NFR-3.4`).
- The storage layer writing outside `~/Library/Application Support/Itchy/`, or
  following a link it should not.
- Once the MCP server arrives: access to pads without the token, access to pads
  not exposed to agents, and anything reachable beyond the loopback interface.

## Supported versions

Only the latest release receives fixes.
