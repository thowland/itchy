# D-34 — Rolling a pad up to its title bar

*Taken October 2026.*

The request was for the classic Mac OS WindowShade control panel: click a
window's title bar and the body disappears, leaving the title bar floating where
it was; click again and the body comes back at the size it had. Only for Itchy's
own pads, not as a general window manager. `FR-3.9` states it; this records the
choices made in building it and the two things that were not obvious.

## The gesture is a double-click, and it replaces the system's

WindowShade's default was a triple-click, and the first suggestion was a
double-click to roll up and a triple to unroll. Both were set aside for a
double-click that toggles. A triple-click always contains a double-click, so an
asymmetric gesture means the second press of every triple has already done
something, and an unroll that sometimes needs two clicks and sometimes three is
a gesture nobody learns. A triple-click that toggles both ways avoids that, but
only by holding back every double-click until a third press has failed to
arrive, and the delay can be felt.

The cost of the double-click is that macOS already has a meaning for it. A
double-click on a title bar zooms or minimises the window, according to a
system setting (`AppleActionOnDoubleClick`). For a pad that action is replaced,
not added to: zooming a pad to fill the screen on the gesture meant to make it
smaller is the worst outcome available. Minimising cannot happen anyway, since a
pad has no minimise button.

Counting is exact: two, not two or more. The third press of a triple-click
arrives with a click count of three, and toggling on it would roll the pad
straight back out.

## The title bar acts on the release, which is how this was nearly wrong

The interception is in `PadPanel.sendEvent`, ahead of `super`, because the
title bar is drawn by the system and has no view of Itchy's to put a handler on.
The first version consumed the second press and passed everything else on. It
shaded the pad, and then zoomed it to the full width of the display a moment
later: the title bar's double-click handling runs on the *release* of the
second click, and the release was still being delivered. This was found by
driving the real panel with synthesised events rather than by reasoning about
it, and the log said so plainly — the zoom arrived from `_NSThemeZoomWidget`
after the second mouse-up. The panel now swallows the release that belongs to a
press it consumed. The first click of the pair goes through untouched, which is
what keeps a shaded strip draggable.

## The stored frame is always the open frame

`PadFrame` gains `isShaded`, and the rectangle beside it keeps meaning what it
always meant: where the pad is and how big it is. While a pad is shaded, what is
written is the open frame hung from the strip's top edge, not the strip itself.
The alternative, storing the strip and the open size separately, would have
given `FrameResolver` and every other reader of a stored frame two meanings to
tell apart, and the size the pad unrolls to would have been one field away from
being lost. A shaded strip's own height is a fact about the title bar, not about
the pad.

`isShaded` is decoded with `decodeIfPresent`, because every `meta.json` written
before now has no such field and its absence means open. The field is in
`PadFrame` rather than in `PadMetadata` so that it rides the frame's write path,
which is debounced and does not touch `modified`: rolling a pad up is not an
edit.

## Geometry: the top edge is the anchor

AppKit's origin is bottom-left, so rolling up is not simply a change of height;
done naively, the title bar drops out from under the pointer that just
double-clicked it. Both directions anchor the top edge. Unrolling hangs the
remembered height from wherever the strip now is, and if that would put the
body below the bottom of the screen the pad is lifted rather than shortened:
where a strip was dragged says where the pad is wanted, and the height says how
big it is, and only the first of those was chosen just now. A strip can be
widened while rolled up and unrolls at its new width; it cannot be made taller,
because the minimum and maximum heights are both set to the strip's for as long
as it is shaded.

## The content is clipped, not removed

The SwiftUI content is now hosted inside a plain container view that clips,
rather than being the window's content view itself. When the pad rolls up, the
hosting view keeps its full height, pinned to the top, and the window simply
shows less of it. Resizing the SwiftUI tree to a few points would have squeezed
the editor out of the layout, and removing it would have thrown away the text
view's undo stack and selection, both of which `FR-4.8` depends on. The
hosting view's `sizingOptions` are emptied so that it no longer feeds SwiftUI's
minimum size to the window; `PanelConfiguration.minimumSize` is what governs, as
it always nominally did.

The accent rule (`FR-3.8`) is the top row of that content, so keeping it on the
strip costs nothing beyond making the strip three points taller when a pad has
one. It was kept because a rolled-up pad is exactly the one most in need of a
landmark: its title is dimmed whenever it is not the key window, which D-33
noted is most of the time.

## A shaded pad does not take the keyboard

A key panel with no body would deliver every keystroke to an editor nobody can
see. Rolling up clears the first responder and makes the panel ineligible to
become key; unrolling gives the keyboard back to whatever had it. The hotkey's
"frontmost and focused" test (`HotKeyAction`, §8.6) excludes a shaded pad for
the same reason, so ⌃⌥Space on a pad just rolled up unrolls it rather than
putting it away.

## When a pad comes back

A pad summoned — from the menubar or by the hotkey — always unrolls, because
summoning is what somebody does when they are about to type. A pinned pad
restored at launch is not summoned, and comes back the way it was left; opening
it would undo a choice somebody made on purpose. `WindowShadePlan.onShow`
states this, and is tested rather than left to the order of calls in the
registry.

## What it does not do

There is no menu command and no keyboard equivalent. That was offered and not
taken. The cost is that rolling up is reachable only by pointer; a pad that is
rolled up can still be unrolled by keyboard alone, through the hotkey or the
menubar, so nobody can be left with a pad they cannot reopen.

`CON-3` has nothing to say against this on the ordinary reading. Like the accent
rule, it changes how one window sits on a desktop and lets nobody ask anything
of the collection.
