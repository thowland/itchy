# D-23 — GPL-3.0, and a repository laid out for readers who are not the author

*Taken while preparing to publish the repository.*

## The licence

Itchy is released under the GNU General Public License, version 3.

The author chose it over MIT and Apache-2.0. The effect of GPL-3.0 is that
anyone who distributes a modified Itchy, or something built from its code, must
release their changes under the same terms. For a project whose position is
that pads should be an open surface between a person and their tools, keeping
derivatives open is consistent with the point. The cost is that the code cannot
be folded into a closed-source product, which is a cost only to someone
intending to do that.

Compatibility, checked at the time of the decision: Itchy has no third-party
dependencies (D-4). The MCP Swift SDK adopted in D-17 is not yet a dependency.
When it becomes one, its licence has to be compatible with GPL-3.0. Apache-2.0
and MIT both are.

The application's copyright line (`NSHumanReadableCopyright` in `project.yml`)
now names the licence instead of reserving all rights. Source files do not carry
per-file licence headers. The root `LICENSE` file governs, which is sufficient,
and headers can be added later without changing the terms.

## The documentation layout

The README had become a developer handbook: signing identities, Automation
Mode, notarisation, troubleshooting a hung test run. That is the wrong first
page for someone deciding whether Itchy is for them. It is now split by reader:

| File | Reader |
|---|---|
| `README.md` | Anyone arriving: what it is, status, how to install and build, where everything else is |
| `docs/user-guide.md` | Someone using Itchy. Also destined for the disk image |
| `docs/development.md` | Someone building or changing it |
| `docs/releasing.md` | Whoever cuts a release |
| `CONTRIBUTING.md` | Someone proposing a change: the transient-content question first |
| `SECURITY.md` | Someone who has found a vulnerability |
| `CHANGELOG.md` | Anyone asking what changed |

`CONTRIBUTING.md` leads with `CON-3` because the vision document identifies
accretion as the project's largest risk, and a public repository is where
feature requests arrive.

## Hygiene before publishing

- `App/Info.plist` was committed before it was generated and ignored (D-12), and
  stayed tracked. It is removed from the index.
- An empty `default.profraw` from a coverage run was committed; it is removed,
  and `*.profraw` is ignored.
- The author's certificate common name appeared in tracked documentation and a
  script comment. It is not secret, since it is embedded in every binary the
  certificate signs, but it is personal, so it is replaced with a placeholder.
  One historical commit message still names it. History was deliberately left
  alone: it is not sensitive, and rewriting would change every later commit hash.
- `CLAUDE.md` stays. It is the most concise statement of the project's
  constraints and rules, and it is as useful to a human contributor as to an
  agent.

## The public repository

The repository is <https://github.com/thowland/itchy>. The README's clone
command, `SECURITY.md` and the issue template's security link all name it.

Private vulnerability reporting is to be enabled, and `SECURITY.md` depends on
it. It cannot be switched on before the repository exists and is public, so it
is a step in the publishing checklist in `docs/releasing.md` rather than
something already done.
