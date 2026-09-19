# D-27 — The deployment floor moves to macOS 15

*Taken September 2026, about twenty minutes after the first notarised build was
carried to a second Mac.*

## What happened

The first signed, notarised disk image opened on another machine — Gatekeeper
accepted it, which is what notarisation was for — and then macOS said:

> You can't use this version of the application "Itchy" with this version of
> macOS.

The application declared `LSMinimumSystemVersion = 26.0`, per `CON-5`. The Mac
was older. Nothing was broken; the constraint was working.

## What was decided

`CON-5`'s floor moves from macOS 26 to macOS 15. Its second sentence — no
back-compatibility work — is unchanged, and is the half that was actually doing
the work.

## Why the original reasoning stopped holding

The architecture document argued: "given that macOS 27 ships this month and the
application is initially for our own use, there is nothing to be gained from
supporting Sequoia."

That was true, and it stopped being true at the exact moment the first build
left this machine. "Initially for our own use" is a condition with an expiry
date, and the expiry arrived. The premise expired rather than the reasoning
being wrong — which is the useful distinction, because it means the original
decision does not need defending and the new one does not need apologising for.

## What it cost

Nothing, which is the surprising part and the reason this was worth doing rather
than deferring.

The project builds at macOS 15 with no errors, no `#available` guards, and no
source changes of any kind. It also builds clean at 14, which was tested and not
taken. The MCP Swift SDK supports macOS 13 and up, so it was never the binding
constraint. The floor was set at 26 because 26 was current, not because anything
needed it.

The change is six declarations — `project.yml`, four `Package.swift` files — the
guard test, and the documents that state the floor.

## What it costs that is not visible in a build

This is the part worth writing down, because a clean build is easy to mistake
for a verified one.

Spikes S-1 through S-4 were resolved against macOS 26, and D-15, D-16 and D-17
record them that way. On macOS 15 those behaviours are assumptions again:

- `RegisterEventHotKey` registering without the Accessibility permission (D-17).
- `.noindex` excluding a directory from Spotlight (D-16).
- A `MenuBarExtra` in `.menu` style not instantiating its content until opened,
  which is why startup lives in the app delegate.
- A non-activating panel appearing without disturbing the frontmost application
  (D-14), which is the behaviour most likely to differ and the hardest to
  notice going wrong.

None of these is likely to have changed — they are all older than macOS 26 —
but "unlikely to have changed" is not the same as "verified", and the spikes
exist precisely because that distinction has already caught this project once.

The honest position is that macOS 15 is supported as far as the compiler is
concerned and unverified as far as behaviour is concerned, until somebody runs
it there. `§14.6`'s manual checklist gains a line saying so.

*Verified 19 September 2026.* A notarised 0.1.1 image was opened on a Mac
running macOS 15; the application ran correctly through its smoke tests, and
⌃⌥Space fires there. The floor is observed rather than assumed, and the spike
behaviours listed above — the hotkey registering without the Accessibility
permission in particular — hold below macOS 26 as well as on it.

## What would reverse it

Wanting an API that arrived after 15, and wanting it enough to write the first
availability guard in the codebase. `CON-5`'s second sentence is what should
make that feel expensive, and it should stay that way: the floor is a floor, not
the beginning of a compatibility matrix.
