# D-28 — The post-MVP interval is over, and the pads absorbed the traffic

*Taken September 2026, after a week of daily use of the first notarised build.*

## What §9 asked

The plan put an interval between the MVP and the next sprint, and it was not a
cooling-off period. It asked one question, taken from the vision document: does
working text stop being routed through messages-to-self and untitled editor
windows? The vision is explicit that this is the measure — "the application has
failed regardless of how well it is built" if the answer is no — and equally
explicit about what to do in that case, which is to diagnose the friction in the
first two seconds of use rather than to build Sprint 6.

## The answer

The pads absorbed the traffic. That is the first of §9's two branches, so the
sprints sketched after it proceed roughly as written.

## The interval was a week, not a month

Worth recording plainly, because the plan said a month and a week is not one,
and because someone reading this later should be able to tell the difference
between a gate that was met and a gate that was called early.

Two things make the shorter interval defensible rather than merely convenient.
The question §9 asks is behavioural and answers itself quickly in one direction:
"am I still messaging myself" is observable within days, and a week of not doing
it is evidence, where a week of still doing it would have been inconclusive. And
the failure mode the interval exists to prevent — building Sprint 6 on top of a
scratchpad nobody reaches for — is not available to be prevented any more,
because Sprint 6 shipped during the interval rather than after it.

That last point is the honest weakness. The plan intended the interval to gate
the transform work, and the transform work went ahead regardless; §9 is being
closed partly after the fact. It still gates Sprint 7 and Sprint 10, which is
worth something, and the answer it got was the good one.

## What this unlocks

Sprint 7 (provenance) and Sprint 10 (model routing), and the stdio shim that has
been waiting rather than blocked since the Developer ID certificate arrived.

## What would reverse it

A month of use that contradicts the week — working text drifting back to
messages-to-self once the novelty of a new thing wears off. The vision's measure
does not expire because this record says the interval is closed, and if the
behaviour reverts then the correct response is still §9's second branch:
diagnose the friction, do not add features.
