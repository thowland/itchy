# D-24 — The transform layer

*Taken during Sprint 6, September 2026. Implements specification §7 and
`FR-6.1`–`FR-6.6`.*

Five decisions were taken while building the deterministic transform set. None
of them contradicts the specification; three of them settle questions §7 left
open, and two correct things that turned out to be wrong in practice.

## JSON is reformatted at the token level, not through a model

§7.2 requires that `json.pretty` preserves key order. Neither of the obvious
implementations can do that. `JSONSerialization` holds an object in an
`NSDictionary` and `JSONValue` — the store's own type, which exists for
unknown-field preservation — holds one in a Swift dictionary; both are
unordered, and both would hand back keys in whatever order the hash produced.

Both also round-trip numbers through `Double`, which is worse than it sounds.
`1.0` comes back as `1`, `1.230` as `1.23`, and an identifier past 2^53 comes
back as a different number entirely. Someone pretty-printing a payload in a
scratchpad wants their own bytes back, more legibly arranged; they do not want a
re-encoding that has quietly altered a value.

`JSONFormatter` therefore walks the source text, validates the grammar as it
goes, copies every scalar through verbatim, and changes only the whitespace
between tokens. The same walk answers "is this JSON?", so the applicability
predicate and `apply` cannot disagree about what parses — which they could if
one used a validator and the other a parser.

The number grammar is checked explicitly rather than deferred to `Double(_:)`,
which accepts `+1`, `0x10`, `inf` and `nan`, none of which are JSON.

## A transform failure is shown in the pad's status bar

`FR-6.6` requires that a failure reports why, and the application had no
mechanism for saying anything to anyone: there is no alert anywhere in it.

A modal alert was the obvious candidate and is the wrong one. A scratchpad whose
whole claim is that it does not interrupt should not stop and demand to be
dismissed because a menu item declined. The status bar already carries the one
other thing that can go wrong with a pad — its fault — so a transform notice
takes a segment there, in the same red, and clears itself after six seconds or
as soon as a transform succeeds.

This is the first transient message in the application. If a second kind
arrives, the segment generalises; it is deliberately not a notification system
today.

## The grouped applier replaces the run rather than inserting text

Specification §7.3 step 4 requires that every non-keystroke mutation goes
through one grouped applier. It did, and the applier used
`insertText(_:replacementRange:)` — which merges attributes into what it
replaces rather than replacing them.

The consequence was invisible until `flatten` went through it, because flatten
is the one operation whose entire purpose is to change attributes while leaving
the characters alone: applied through `insertText`, it did nothing at all. The
same merging had already been noticed in a smaller form — a test for `FR-4.5`
recorded that flattening kept the old point size and asserted only the family,
attributing it to the text view rather than to this code.

The applier now calls `shouldChangeText`, replaces the range in the text storage
directly, and calls `didChangeText` — the pair `insertText` calls internally, so
undo registration is unchanged. Flattening now drops styling through the view as
well as in the codec, and the point size follows the editor font. The `FR-4.5`
test asserts both.

The action name is set after the change rather than before it, because the text
view registers its own undo during the edit and names it "Typing", which is what
the Edit menu would otherwise show.

## Predicates decline input they would not change

§7.2 gives several transforms the predicate "any text". Any text still means
some text: offering "Sort lines" on an empty pad, or "Decode URL component" on
text holding no percent-encoding, produces a menu item that does nothing. Each
such transform declines instead, with a reason.

`whitespace.trim` is the deliberate exception to the whitespace-only rule, since
whitespace is exactly what it has something to do with; it declines only when
there is no stray whitespace to remove.

## Routing is enforced now, not in R4

§7.3 step 2 introduces the routing check "from R4". It is implemented now, as
`RoutingGate`, because the entire reason `Transform.apply` has one call site is
that routing is enforced there — and a runner written without it is a runner
that has to be remembered later, at the point where the MCP path also depends on
it.

Nothing reaches the interesting cases yet: every transform in the deterministic
set answers `false` to `requiresNetwork`. The gate is tested with a stub that
answers `true`. `askEachTime` returns `.needsConsent`, which the runner treats
as a refusal, because the consent prompt is R4's work and assuming a yes in its
absence is the one answer that cannot be undone.

## What Sprint 6 did not deliver

- **Sparkle (`NFR-4.4`)**, which the plan puts in this sprint. It is entangled
  with signing: an update framework needs a Developer ID to verify updates
  against, and that certificate is the thing R1 is already blocked on. Building
  it now would mean building it untested.
- **The progress and cancel affordance** of §7.3 step 3, which shows after 150
  ms. Every transform in the deterministic set returns immediately, so there is
  nothing that can trigger it and nothing that could test it. It belongs with
  the first transform that can be slow, in Sprint 10.
- **`pads.diff` (`FR-6.7`)**, a MAY, and the only transform that returns
  `.report`. The `report` case exists and is unused.
