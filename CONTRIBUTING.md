# Contributing

Thank you for looking. Itchy is a personal tool first, built for its author's
daily use, and it is maintained on that basis. Please read this before opening
anything larger than a bug report.

## Bug reports

Welcome. Include the version from **About Itchy**, your macOS version, what you
did, what you expected, and what happened. If a pad reports that its content is
unreadable, say which fault it names.

## Features: the one question

Itchy is for transient content. Every proposed addition has to answer one
question: does it serve content that is passing through, or content that has
earned a permanent place? If the latter, it will be declined, however good the
idea is, because that is how a scratchpad turns into the note-taking application
it was built to avoid.

That rules out, permanently: a document library, folders, tags, search across
every pad, save or title prompts, cloud sync, telemetry, and a chat panel. The
reasoning is in [the vision document](docs/itchy-vision.md), and the constraints
are numbered in [the requirements](docs/itchy-requirements.md) (`CON-1` to
`CON-6`).

Open an issue to discuss a feature before writing code for it.

## Changes

- **Read the documents first**, in the order [CLAUDE.md](CLAUDE.md) lists them.
  Where they disagree, the earlier one governs.
- **Pass the gate.** `make gate` runs lint, the architecture checks, the tests
  and coverage, and a change is not ready until it passes. The UI suite
  (`make test-ui`) is separate; see [development](docs/development.md).
- **Keep decisions out of views.** A view translates and applies; the decision
  goes in a pure, value-typed unit that can be tested without a window server.
  Specification §15 explains the rule and lists the existing seams.
- **Record decisions.** A decision taken while implementing goes in
  [docs/decisions](docs/decisions/), numbered after the last, with its reasoning.
  A decision recorded without its reasoning cannot safely be reversed later.
- **Cite requirement numbers** (`FR-4.2`, `D-18`) in commits and comments.
- **No third-party dependencies** without a decision record that justifies one.
- Documents are written in British English, in prose with the reasoning
  attached.

## Licence

By contributing, you agree that your contribution is licensed under the
[GNU General Public License, version 3](LICENSE), the same as the rest of Itchy.
