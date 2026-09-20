# D-33 — Making a pad recognisable on a crowded desktop

*Taken September 2026, after a week of daily use.*

Two complaints, one problem behind them: a pad panel among a dozen other
windows does not read as a pad. The title is hard to see, and the window as a
whole looks like any floating text palette. Both are fixable, but only one of
them is the fix.

## The title was small because the panel was a utility window

`PanelConfiguration.standard` carried `.utilityWindow` in its style mask, and
that flag is what draws the short title bar with the small, light title. It is
AppKit drawing it, and there is no supported API for setting the font or the
weight of a system-drawn window title. So the options were to draw the chrome
ourselves or to stop asking for the utility variant.

`FR-3.7` already rules out the first, and for a better reason than this one:
standard chrome carries resize, drag, window-button and accessibility behaviour
that a custom title bar has to reimplement and will reimplement incompletely.
That left dropping the flag, which the specification's §8.2 table did not permit
without being amended, since it says in terms that a deviation from it is a bug.
So the table is amended and `FR-3.7` no longer says "utility window". Nothing in
`FR-3.1` was resting on the flag: floating and non-activating come from
`.nonactivatingPanel`, `isFloatingPanel` and `level`. The visible cost is about
six points of title bar height, taken out of the content area.

## Something was resting on the flag, and it was not in the table

The table was right to call a deviation a bug, and it caught one. A titled
`NSPanel` that is not a utility window reports its accessibility subrole as
`AXDialog` rather than `AXFloatingWindow`. Nothing about the window changes —
it opens, it floats, it takes keystrokes, and it is 420×520 exactly where it was
— but every `app.windows` query in the UI suite stopped matching at once, and
the symptom was the screenshot run reporting "no pad opened" about a pad that
was plainly open on the screen.

The test failure was the cheap half. A pad is not a dialog: nothing is waiting
on it, it takes no answer, and it does not go away when you have dealt with it.
VoiceOver reads the subrole out, so the change would have quietly told anyone
using it that a scratchpad was a modal prompt. That is a worse defect than the
small title was, and it would not have been noticed by looking.

So `PadPanel` states its subrole as `.floatingWindow` rather than inheriting
whatever the style mask implies, and `PanelConfigurationTests` asserts it. The
assertion exists because the value is now set in one place and depended on in
another, which is exactly the arrangement that decays.

## A bold title does not solve the problem that was actually described

Worth being honest about, because it is the reason the second half of this
exists. A non-activating panel is not the key window for most of its life —
that is the whole point of it — and a window that is not key draws its title
bar dimmed. The moment somebody is scanning a desktop looking for their pad is
precisely the moment the title is greyed out. A bolder title helps when you are
already looking at the pad. It helps much less with finding it.

Anything drawn inside the content area is not subject to that, because the
application draws it and the window server does not dim it. That is why the
accent rule is the load-bearing half, and why it is a row in the hosted content
rather than a band added to the chrome.

## The rule, and the line it must not cross

`FR-3.8` gives a pad an optional coloured rule between the title bar and the
text, three points tall, from a palette of six or from a colour the user picks.
It is absent by default: the request was for a way to mark particular pads, not
for every pad to acquire a stripe.

The palette carries a light and a dark value for each name, because a colour
dark enough to read against a white pad disappears against a dark one. A custom
colour carries one value and is used unchanged in both. That is a real
limitation and it is stated in the control rather than left to be found at dusk;
the alternative — deriving a dark variant from an arbitrary colour — produces
results nobody asked for and cannot be predicted from the well.

The colour is stored as one string, `"sky"` or `"#4a90d9"`. `FR-5.7` makes
`meta.json` hand-editable and promises unrecognised fields survive a save, so a
field somebody may reasonably edit should be legible when they open the file.
A synthesised `Codable` on an enum with associated values would have written
`{"named":{"_0":"sky"}}`. The reader is correspondingly tolerant: case,
surrounding space and a missing `#` are all accepted, because somebody copying a
colour out of a design tool gets it without the hash about half the time.

Now the part that matters more than any of it. A per-pad colour is one step away
from a tag, and `CON-1` forbids tagging. The distinction `FR-3.8` draws, and
states as a MUST NOT rather than as a note, is between a landmark and a
category: the colour exists to help find one window among many on a desktop, and
must never become something the collection can be queried by. A filter, a sort,
a "group by colour" in the Pads window, or an MCP tool that takes a colour would
each turn this into the tagging system the project was built to avoid, and each
would look like a small and reasonable addition on the day it was proposed. It
is in the requirement so that the answer is already written down.

`CON-3` is satisfied on the ordinary reading: a rule under the title bar says
nothing about how long the text beneath it lives, and adds no library, no
hierarchy and no search.
