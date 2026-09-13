# D-20 — Styled pads get bold, italic and underline, on screen and on the keyboard

*Taken during fit-and-finish, after R1.*

## What was asked

Minimal font controls on styled pads: bold, italic and underline. `FR-4.7`
already promised the standard Format menu behaviour at the fidelity the system
text view provides. In practice there was none, because Itchy is an accessory
application (`FR-1.1`) with no menu bar, and so no Format menu for ⌘B to arrive
through. The request is recorded as `FR-4.11`.

## What was built

Three buttons in the pad's bottom bar, between the status segments and the ⋯
menu, and ⌘B, ⌘I and ⌘U. The buttons show which traits the selection carries,
and they collapse to nothing in a plain pad, where formatting cannot exist
(`FR-4.4`).

Three traits and no more. Size, colour and lists were not asked for, and each
one moves a scratchpad closer to the word processor the vision document warns
about.

## How the pieces divide

- `FormattingPlan` decides. A trait reads as on only when every run in the
  selection has it, and toggling applies a trait when any run lacks it and
  removes it when all have it, as TextEdit does. It also maps a key chord to a
  trait, refuses in plain mode, and ignores Caps Lock while refusing any further
  modifier, so ⌘⇧U stays free for whatever else wants it.
- `TextFormatter` carries the decision out. It goes through
  `shouldChangeText(inRanges:replacementStrings:)` and `didChangeText()`, so
  that each toggle is one undo step named for its trait, and the pad stages
  exactly as it does for a keystroke. With nothing selected it changes the
  typing attributes instead.
- `PadTextView` answers the shortcuts in `performKeyEquivalent`, and only when
  it is the first responder, so a pad without focus leaves the chord for others.
  It also answers them in `keyDown`. The UI suite showed that in a live
  non-activating panel of an inactive application, ⌘B is not offered as a key
  equivalent at all. It arrives as an ordinary key press, and the unit tests,
  which call `performKeyEquivalent` directly, had passed regardless.
- `PadTextCoordinator` owns an observable `FormattingState`, refreshed on
  selection change, edit and toggle, which the buttons read.

## A bug the controls exposed

Panels now observe the pad list, so that a rename or a mode change reaches an
open pad (see D-21). That made SwiftUI call `updateNSView` on every refresh,
and `updateNSView` reconfigured the text view each time, which reset the typing
attributes. ⌘B with nothing selected would have lasted until the next save.
`ModeConfigurationPlan` reconfigures only when the mode actually changes.
Applying a new editor font (D-19) still reconfigures unconditionally, because
that is a real change.

## Demonstrated in a real panel

`LaunchUITests` selects text in a live pad and clicks B, then continues typing,
which fails if the click took keyboard focus away. It also presses ⌘B in the
panel. Neither can be reached from a unit test. Separately, the UI-test store
now uses one directory per launch, because text typed by these cases was
leaking into `testPanelAcceptsTypedInput`.

## Font traits and the built-in font

Bold is carried as `NSFontTraitMask.boldFontMask`, and `NSFontManager` converts
the system monospaced font's regular weight to semibold for it, which is how
D-19's restyle preserves bold across a font change. Italic is converted the same
way, and a test holds that it works in the built-in font as well as in a font
chosen for the purpose.
