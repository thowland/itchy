# D-32 — What continuous integration can and cannot decide

*Taken September 2026, on publishing the repository.*

The suite had never run anywhere but the machine it was written on. Publishing
to GitHub ran it on a hosted macOS runner for the first time, and it failed in
two ways that had nothing to do with any defect in Itchy — which is the useful
kind of failure, because both were statements about assumptions the suite had
been making silently.

## A compiler one minor version behind rejected the transport tests

`MCPServerHostTests` and `MCPServerRefusalTests` tear their fixture down in a
`defer`, which cannot `await`, so the teardown runs inside a `Task`. That task's
closure is `sending`, and it was capturing `MCPServerFixture` — a `~Copyable`
struct holding an actor, a store and a URL. Swift 6.4, which is what this Mac
has, accepts it. Swift 6.3, which is what the runner had, rejects it as a data
race risk and the test target does not compile.

The runner was right and the local compiler was being generous. The fix is not
to pin a toolchain: it is to hand the closure something that is obviously safe
to send. `MCPServerTeardown` holds the two things teardown actually touches, an
actor and a URL, both `Sendable`, and the call sites take it before the body
runs. That compiles under either compiler because it is correct under either,
rather than merely permitted by one.

The general point is worth keeping. A suite that has only ever been compiled by
one toolchain has been verified against one toolchain, and strict concurrency
diagnostics are exactly where minor versions differ. CI is the only thing that
was ever going to find this.

## A shared runner cannot measure a perceptual budget

`NFR-1.1` puts 250 ms between the hotkey and a focused, typeable pad, at the
ninety-fifth percentile. `PerformanceTests` measures it by opening a real panel
twenty times. On this Mac the ninety-fifth percentile is around 40 ms. On the
runner it was 476 ms, on identical code.

That is not a regression, and asserting 250 ms there does not defend the
requirement; it just makes the build red whenever the runner is busy.
`NFR-1.1` is a claim about the machine a person is typing on, and a hosted
runner is virtualised, shares its host with other jobs, and composites windows
without a GPU. The number it produces is a measurement of the runner.

Two wrong answers were available. Deleting the test loses the measurement
altogether. Skipping the assertion on CI leaves the one failure mode that would
genuinely break the budget — launch beginning to read pad content eagerly,
against `FR-1.6` — unguarded on the only machine that runs the suite on every
push, and that failure costs seconds rather than milliseconds.

So `MeasurementHost` names where the measurement is being taken and what it is
worth there: 250 ms on real hardware, 1500 ms on a shared runner. The
measurement is always taken and always printed. The loose ceiling is not a
weaker version of `NFR-1.1`; it is a different and much cruder assertion that
happens to be checkable in a place where the real one is not, and it is the
developer's own machine and the manual checklist in §14.6 that continue to
answer for the requirement itself.

## What CI is for here

It follows from both of these that a green CI run is not the sprint exit gate
and does not claim to be. It answers a narrower question: does this code build
and pass its tests on a machine that is not this one. `make gate` on real
hardware remains what G1–G3 mean, and G4 remains manual. Keeping that
distinction explicit matters because a green badge is persuasive out of
proportion to what it actually checked.
