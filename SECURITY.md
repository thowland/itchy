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

Itchy stores pads as files in the user's Library folder. It opens no network
connection of its own until one is configured, and there are exactly two that
can be: the agent server, which listens on loopback, and a model endpoint, which
Itchy dials. Both are off until switched on. Areas of particular interest:

- Pad content, or backups of deleted pads, becoming readable where they should
  not be, including through Spotlight indexing (`NFR-3.4`).
- The storage layer writing outside `~/Library/Application Support/Itchy/`, or
  following a link it should not.
- The agent server: access to pads without the bearer token, access to pads not
  exposed to agents, a token that survives being regenerated, or the listener
  reachable from anywhere other than `127.0.0.1` (`FR-8.3`, `NFR-3.3`).
- Model routing: pad text reaching a remote service from a pad whose policy
  forbids it, or reaching one as a fallback after the local model failed, which
  `FR-9.4` rules out under every setting.
- Credentials — the agent token and the remote model's API key — appearing
  anywhere other than the Keychain, including in the debug log, a crash report
  or a backup (`NFR-3.3`, `FR-9.5`).

The debug log is off by default and is written to `/tmp/itchy.log`, which is
readable by other users of the same Mac. It records pad names, transform names
and character counts, never pad content; a report that it has captured content
is in scope.

## Supported versions

Only the latest release receives fixes.
