# D-14 — A pad appearing does not activate; a pad focused necessarily does

*Taken in Sprint 2.*

## What was found

`FR-3.1` says a pad panel "MUST NOT activate Itchy as the frontmost application
when clicked". `FR-3.2` says the panel "MUST accept typed input". Sprint 2's UI
suite asserted both, and the first one failed: after clicking into the panel,
`NSApp.isActive` is true.

This is not a configuration mistake. It was checked directly: a panel with
`.nonactivatingPanel`, `canBecomeMain = false`, `isFloatingPanel = true` and
`level = .floating` still leaves the application active once the panel is key.
An application cannot receive keystrokes without holding keyboard focus, and an
application holding keyboard focus is the active one. The two requirements, read
literally, cannot both hold.

## Decision

`FR-3.1`'s non-activation criterion is taken to mean **a panel appearing must not
activate the application**, not that a panel the user has deliberately clicked
into stays unfocused. What `.nonactivatingPanel` actually buys is that the panel
does not drag the rest of the application forward with it: no other Itchy window
is ordered front, no Dock icon appears, and nothing about the user's window
arrangement changes beyond the pad itself.

The code now distinguishes the two cases:

- `show(makingKey: true)` — the user asked for this pad and is about to type into
  it. Takes keyboard focus.
- `show(makingKey: false)` — the pad is being restored, because it is pinned
  (`FR-2.7`) or because a later release reopened it. Appears without taking
  focus.

The distinction is not cosmetic. An application that steals the keyboard at
login is an application that gets quit, and pinned pads reopen at launch.

## What is asserted, and what is not

`testPanelAppearsWithoutActivatingTheApplication` covers the half that can be
tested: a panel that appears leaves the application in the background.

The other half — that a genuine mouse click on the title bar to *drag* a pad does
not activate — cannot be asserted through XCUITest, because its synthesised click
activates the target application as part of its own mechanics. It moves to the
manual checklist.

## What should change in the requirements

`FR-3.1`'s wording should be amended to say "a panel appearing must not activate
the application, and interacting with a panel must not bring other application
windows forward". That is what the requirement was reaching for, and it is
testable. Left for the author to decide rather than edited unilaterally, because
it narrows a requirement rather than clarifying one.
