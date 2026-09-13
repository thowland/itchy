# D-21 — Each pad has its own settings sheet, reached from the pad

*Taken during fit-and-finish, after R1.*

## What was asked

Named pads, so that a pad is easy to find from the menu now and to ask for over
MCP later, with the name controlled from settings belonging to that pad.
Renaming already existed (`FR-2.4`), but only in the Pads window, which is a
list of every pad and not a place one goes from the pad in front of you.
Recorded as `FR-2.9`.

## What was built

"Pad Settings…" at the top of each pad's ⋯ menu opens a sheet on that pad's
panel, holding its name, its mode and whether it is pinned. It is the place per
-pad settings will go as they arrive: MCP exposure in R3, the routing policy in
R4. Renaming in the Pads window stays.

- **The name applies on Return and when the sheet closes**, not on every
  keystroke, so a half-typed name never reaches the menu or an agent. The Pads
  window's inline field still renames per keystroke, as it did before.
- **An empty name keeps the current one.** `FR-2.4` says a pad always has a
  name, so clearing the field is not a way to remove it, and the sheet says so
  where it happens. Surrounding whitespace is trimmed, because a trailing space
  is invisible in a menu and would break asking for the pad by name.
- **A name another pad already has is pointed out, not refused.** `FR-2.4` lets
  names repeat. The only cost is that an agent asking for the pad by name gets
  an ambiguity error (specification §11.5), and the notice says exactly that.
  The comparison ignores case, because §11.5 resolves names that way.
- **Mode and pinning apply as they change**, through the same coordinator calls
  as the ⋯ menu and the Pads window. Switching to plain still flattens as one
  undoable step (`FR-4.5`).

## Activation

A pad panel takes the keyboard without activating Itchy (D-14). A sheet is an
ordinary window and has no such exemption: without activating the application
first, the name field shows a cursor and drops every keystroke. Opening the
sheet therefore activates Itchy, which D-14 already accepts for a pad being
focused deliberately.

## Two stale-state bugs fixed on the way

A panel was built with the pad's metadata as it was when the panel opened, and
never saw it again.

- **The title bar kept the old name** after a rename until the pad was closed and
  reopened. `rename` now retitles an open panel.
- **The status bar, the ⋯ menu's "Switch to…" label, and the choice of editor
  mode** kept the old name and mode. The panel now reads the live metadata
  through `PadCoordinator.metadata(for:)`. D-20 records the consequence for the
  text view's typing attributes, and how that was handled.
