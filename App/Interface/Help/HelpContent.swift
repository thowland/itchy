import Foundation
import ItchyCore

/// The text of the help book.
///
/// Separated from `HelpBook` because it is prose and that is structure, and
/// because a file that is mostly sentences should not also be the file somebody
/// edits to change how a heading is set.
///
/// Written the way the rest of this project's documents are: plainly, in
/// British spelling, and with the reason attached wherever the behaviour would
/// otherwise look arbitrary. Someone reading help is usually already puzzled,
/// and "it works this way because" ends the puzzlement where "it works this
/// way" does not.
enum HelpContent {
  static let gettingStarted = HelpTopic(
    id: "getting-started",
    title: "Getting started",
    symbol: "sparkles",
    blurb: "What Itchy is for, and the three things worth knowing on the first day.",
    sections: [
      HelpSection(
        heading: "The idea",
        blocks: [
          .text(
            "Itchy holds a small, fixed set of scratchpads. They are for text that is "
              + "passing through — a tracking number, a failing request's JSON, a paragraph "
              + "you are still arguing with — and not for text you intend to keep and file. "
              + "There is nothing to name, nothing to save, and nowhere to file anything."),
          .text(
            "That is a deliberate limit rather than an unfinished feature. The whole "
              + "collection is meant to fit in one glance at a menu, which is why there is no "
              + "folder tree, no tags, and no search across everything."),
        ]),
      HelpSection(
        heading: "Finding it",
        blocks: [
          .text(
            "Itchy has no Dock icon and no main window. It lives as a cat in the menubar, "
              + "and everything starts from there: your pads are listed at the top, and "
              + "New Pad, Pads…, Settings and this help are underneath."),
          .note(
            "If you cannot find the cat, the menubar is probably full. Quitting another "
              + "menubar application makes room."),
        ]),
      HelpSection(
        heading: "The hotkey",
        blocks: [
          .text(
            "⌃⌥Space brings back the pad you used last, from inside any application. "
              + "Press it again and the pad goes away. It is the fastest route back to "
              + "whatever you were in the middle of, and it is the one thing worth learning "
              + "on the first day."),
          .text(
            "You can change the combination in Settings → General. If it does nothing, "
              + "another application has already claimed it; the setting says so underneath "
              + "the recorder."),
        ]),
      HelpSection(
        heading: "Pads float, and do not interrupt",
        blocks: [
          .text(
            "A pad opens over whatever you are doing, including a fullscreen application, "
              + "and stays where you put it. Opening one does not bring Itchy's other "
              + "windows forward and does not disturb the arrangement of what is behind it."),
          .text(
            "Close a pad and its contents are still there next time. There is no save "
              + "step, because there is no version of this where you lose something by "
              + "forgetting one."),
        ]),
    ])

  static let pads = HelpTopic(
    id: "pads",
    title: "Working with pads",
    symbol: "square.on.square",
    blurb: "Creating, naming, pinning, emptying and deleting — and what each one costs you.",
    sections: [
      HelpSection(
        heading: "Making and removing",
        blocks: [
          .text(
            "New Pad, from the menubar or ⌘N, creates a pad and puts the cursor in it. "
              + "It asks for nothing. \(PadBounds.defaultCount) pads exist by default and "
              + "you can have up to \(PadBounds.hardCeiling), in Settings → General."),
          .text(
            "Lowering the number does not delete or hide anything. It applies to new pads "
              + "only, and the setting says so when you lower it below the number you have."),
          .note(
            "Deleting a pad is the one action Itchy asks you to confirm. It is also the "
              + "only way to lose content, which is why it is the one exception to a rule "
              + "against prompts."),
        ]),
      HelpSection(
        heading: "Styled and plain",
        blocks: [
          .text(
            "A styled pad keeps formatting and images: paste from a browser or a word "
              + "processor and it survives, screenshots included. ⌘B, ⌘I and ⌘U work, and "
              + "there are buttons at the bottom of the pad."),
          .text(
            "A plain pad is text and nothing else, which is what you want for code and "
              + "JSON, where smart quotes are never welcome. Switching a styled pad to "
              + "plain strips its formatting in one step, and one undo puts it back."),
        ]),
      HelpSection(
        heading: "A pad's own settings",
        blocks: [
          .text(
            "The ⋯ button at the bottom right of a pad opens that pad's settings: its "
              + "name, its mode, whether it reopens when Itchy starts, and whether agents "
              + "may read it."),
          .text(
            "Naming is optional. It is worth doing for a pad you will ask an agent for by "
              + "name, and the settings sheet warns you when two pads share a name, because "
              + "at that point an agent cannot tell them apart."),
          .text(
            "Pinning a pad means its window comes back when Itchy starts, where it was, "
              + "without taking your keyboard focus."),
        ]),
      HelpSection(
        heading: "The status line",
        blocks: [
          .text(
            "Along the bottom of each pad: its name, its mode, how many pastes it has "
              + "recorded, whether it is exposed to agents, and anything that has just gone "
              + "wrong. It is the first place to look when a pad is not behaving.")
        ]),
    ])

  static let transforms = HelpTopic(
    id: "transforms",
    title: "Transforms",
    symbol: "wand.and.sparkles",
    blurb: "Reshaping the text in a pad without leaving it, and always with an undo.",
    sections: [
      HelpSection(
        heading: "Using one",
        blocks: [
          .text(
            "The wand button at the bottom of a pad lists what can be done to the text in "
              + "front of you: flatten styling; upper, lower and title case; pretty-print "
              + "and minify JSON; encode and decode base64; encode and decode URL "
              + "components; trim whitespace; and sort lines."),
          .steps([
            "Select the part you want to change, or select nothing to act on the whole pad.",
            "Choose a transform from the wand menu.",
            "If it was not what you wanted, press ⌘Z. It is a single undo step, and the "
              + "Edit menu names it.",
          ]),
        ]),
      HelpSection(
        heading: "Why some are greyed out",
        blocks: [
          .text(
            "A transform is offered only when it would work on what is actually there. "
              + "Decode base64 is unavailable on text that is not base64, and the JSON "
              + "transforms are unavailable on text that is not JSON. Hovering over a "
              + "disabled entry says why."),
          .text(
            "This is on purpose. A menu that offers everything and then fails is a menu "
              + "that teaches you to distrust it."),
        ]),
      HelpSection(
        heading: "When one fails",
        blocks: [
          .text(
            "Nothing happens to the pad, and the reason appears in the pad's status line "
              + "for a few seconds. Itchy does not stop you with a dialogue for this: a "
              + "scratchpad that interrupts is a scratchpad that gets in the way."),
          .note(
            "Pretty-printing JSON preserves the order of keys and does not reformat "
              + "numbers. Text that goes through it and comes back is the same document, "
              + "not an equivalent one."),
        ]),
    ])
}
