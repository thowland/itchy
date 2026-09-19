# D-30 — Transforms are not part of the agent surface

*Taken September 2026, before Sprint 10 opened, because the sprint could not
have satisfied both of the requirements it inherited.*

## The contradiction

`FR-9.2` required that "a transform invoked over MCP is subject to the same
restriction as one invoked from the menu", and its acceptance criterion asked
for a remote-requiring transform to be *invoked over MCP* against a local-only
pad and refused.

`FR-8.5` limits the exposed operations to five — list, read, append, write,
create — and its acceptance criterion is "the tool listing contains these and
nothing else". `MCPToolSurfaceTests` asserts the count.

`FR-9.2`'s criterion needs a sixth tool. `FR-8.5`'s forbids one. Both were
written before either was built, and nothing had forced them together until
Sprint 10 was about to.

## What was decided

`FR-9.2`'s MCP clause is withdrawn. The requirement keeps its valuable half —
that the policy is enforced below the view layer, in one place — which is
already satisfied by `RoutingGate` inside `TransformRunner`, at the single
`Transform.apply` call site `Scripts/arch-lint.sh` holds to one.

No sixth tool. `FR-8.5` stands unchanged.

## Why that way round

**`FR-8.5`'s narrowness is a position, not an oversight.** The tool surface is
written down in one place with a comment saying a sixth tool is a decision
somebody has to take deliberately, and a test asserts the count. That machinery
exists precisely so this question gets asked rather than answered by whoever is
holding the keyboard. Asked, the answer is no.

**The transforms worth routing are the model-backed ones, and an agent asking
Itchy to ask a model is a strange loop.** The deterministic transforms —
upper-case, trim, pretty-print JSON — are things an agent can do to text it has
already read, faster and without a round trip. The model-backed ones would mean
an agent spending a tool call to have Itchy spend an inference call. The only
party for whom a model-backed transform is a genuine convenience is the person,
which is who the menu is for.

**It would have moved the routing policy out from under the person who set it.**
`FR-9.1` makes routing a per-pad choice with a local-only default, and `NFR-3.2`
makes exposure a per-pad choice with an off default. A transform tool would let
an agent — itself already remote, in the ordinary case — ask a pad to do
remote-permitted work. The refusal would be correct and the shape would be
wrong: the person's answer to "may this pad reach the network" is not meant to
be a thing another network service asks about.

## What this costs

An agent cannot ask Itchy to transform a pad. It can read the pad, transform the
text itself, and write it back, which is three calls where one might have done
and is the honest arrangement: the agent does the work, Itchy holds the text.

## What would reverse it

A transform that Itchy can do and an agent genuinely cannot — one that needs
something only the application holds, rather than the text it already handed
over. None of the twelve in `TransformRegistry` is that, and the model-backed
ones planned for Sprint 10 are not either. If one ever is, this is the argument
to re-read, and `FR-8.5` is the requirement to amend first.
