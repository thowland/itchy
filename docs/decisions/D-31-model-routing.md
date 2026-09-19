# D-31 — Model routing: local first, no escalation, three transforms

*Taken September 2026, building Sprint 10.*

## Local first, always

`ModelRouter.destination` prefers the local model under every policy, including
`remotePermitted`, and including when a transform says it would rather have a
bigger model. A local model sends nothing anywhere, so no policy has to permit
it and no consent has to be asked for it. The pad's routing policy exists to
govern text leaving the machine; where nothing leaves, it has nothing to govern.

This makes `requiresNetwork` on a model-backed transform a statement about the
*destination it resolved to*, not about it being model-backed. That is why a
pad set to local-only can still use a model.

## No escalation, and it is a function rather than a promise

`FR-9.4` says failure to reach the local endpoint "MUST NOT fall back to a
remote service under any policy". That is a rule about a return value, so it is
written as one: `ModelRouter.afterLocalFailure` takes the settings and the
policy and returns a refusal, and there is no argument for which it returns
`.remote`. A test iterates every policy against every configuration and asserts
it.

Written as a fallback inside a client it would have been a rule about what
somebody remembered not to write, and the failing case — local model down,
remote configured, pad permits remote — is exactly the case where falling back
looks helpful.

The one fallback that is permitted goes the other way: a transform that wanted
remote, on a machine with only a local model, runs locally. Inward is safe.

## Three transforms, and all three transform

`ModelTransforms` offers Tidy Prose, Summarise and To Bullet Points. Each
replaces text with text.

Nothing answers a question about the text. "Summarise this" produces something
that goes in the pad; "what do you think of this" produces a conversation, and
`CON-1` and the vision document both say what happens next — a scratchpad that
answers questions grows a reply field, then a history, then it is a chat window
with a save button. `FR-9.6` says the same thing from the other end: no separate
model panel, no chat surface, the model is one more transform.

They come after every deterministic group in the menu, which `FR-9.6` requires
and which is worth stating as more than ordering: the deterministic ones are
instant and certain, and a menu that puts a model call above `Trim Whitespace`
teaches the person this is a model application with some utilities attached.

## The prompt is defensive in two directions

Models add preambles. A transform's output is written straight into the pad as
one undoable step, so "Here's a clearer version:" becomes the person's content.
Every instruction says to return the text and nothing else, and `ModelAnswer`
strips code fences when they arrive anyway — which they do, often.

The pad's text goes in the request body, never folded into the instruction. A
pad containing the words "ignore previous instructions" is a pad, not a second
set of orders. This is not a claim that the arrangement is proof against a
determined prompt injection; it is the cheap half, and the expensive half —
sandboxing a model's output — is not available at this layer.

## One dependency, still

`D-4` permits the application one third-party dependency and `D-5` spent it on
the MCP SDK. The remote client is therefore `URLSession` and
`JSONSerialization` against an OpenAI-compatible `/v1/chat/completions`, which
is what almost everything speaks, including the local servers somebody might
run instead of Ollama. A provider SDK would have been more pleasant and would
have cost the budget.

## The credential

In the Keychain, through the same `MCPTokenStore` seam the MCP token uses — so
the suite gets an in-memory store here too and `Scripts/arch-lint.sh`'s fifth
check keeps every test off the real Keychain (D-26).

`FR-9.5` also says the key must not reach the support directory or any log. The
support directory has no field for it, and the log cannot say it: `LogEvent`'s
vocabulary is closed (D-26), so no call site can write one. A test puts a key
in, does everything that writes, and then reads every byte of both.

## Consent is the second prompt in the application

`CON-2` prohibits save, title and filing prompts, and pad deletion was the only
exception. `askEachTime` adds one, and it is not the same kind: it is a policy
the person chose, named "ask me each time", and a policy by that name which did
not ask would be a lie in a picker.

The question names the pad, the transform, the destination host and the number
of characters. "Allow this?" with no nouns in it is a question people answer yes
to without reading.

Anything that cannot ask — `itchyctl`, the suite — answers no. Nobody deciding
is not the same as yes.

## What is not done

A live completion has not been run. Ollama is installed and running on this
machine with no models pulled, so the paths that are verified against the real
server are the ones that matter most for correctness — that it is reachable,
and that a model which is not pulled reports itself as a missing model rather
than a missing endpoint. Pulling a model is a gigabyte-scale download and is the
machine owner's decision.
