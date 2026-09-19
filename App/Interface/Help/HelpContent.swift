import Foundation
import ItchyCore

/// The text of the help book.
///
/// Separated from `HelpBook` because it is prose and that is structure, and
/// because a file that is mostly sentences should not also be the file somebody
/// edits to change how a heading is set.
///
/// Written in the operational register: plain, with the mechanism before the
/// conclusion, and with the limits stated where somebody is about to hit them.
/// Someone reading help is usually already puzzled, and an explanation that
/// says how a thing works ends the puzzlement where an instruction does not.
enum HelpContent {
  static let gettingStarted = HelpTopic(
    id: "getting-started",
    title: "Getting started",
    symbol: "sparkles",
    blurb: "What Itchy is for, and the three things worth knowing on the first day.",
    sections: [
      HelpSection(
        heading: "What Itchy is for",
        blocks: [
          .text(
            "Itchy holds a small, fixed set of scratchpads for text that is passing "
              + "through — a tracking number, the JSON from a request that failed, a "
              + "paragraph you are still arguing with. Nothing needs a name, nothing needs "
              + "saving, and there is nowhere to file anything, because the whole collection "
              + "is meant to fit in one glance at a menu."),
          .text(
            "The limit is the design. There is no folder tree, no tags and no search across "
              + "everything, and adding them would turn a scratchpad into a filing system "
              + "with worse ergonomics than whichever one you already use."),
        ]),
      HelpSection(
        heading: "Finding Itchy",
        blocks: [
          .text(
            "There is no Dock icon and no main window; Itchy lives as a cat in the menubar, "
              + "and everything starts from there. Your pads are listed at the top, and New "
              + "Pad, Pads…, Settings and this help are underneath."),
          .note(
            "If you cannot find the cat, your menubar is probably full. Quitting another "
              + "menubar application makes room."),
        ]),
      HelpSection(
        heading: "The global hotkey",
        blocks: [
          .text(
            "⌃⌥Space brings back the pad you used last, from inside any application, and "
              + "pressing it again puts the pad away. It is the fastest route back to "
              + "whatever you were in the middle of, and it is the one thing worth learning "
              + "on the first day."),
          .text(
            "You can change the combination in Settings → General. If it does nothing, "
              + "another application has already claimed it, and the setting says so "
              + "underneath the recorder."),
        ]),
      HelpSection(
        heading: "How pads behave on screen",
        blocks: [
          .text(
            "A pad opens over whatever you are doing, including a fullscreen application, "
              + "and stays where you put it. Opening one does not bring Itchy's other "
              + "windows forward and does not disturb the arrangement of what is behind it, "
              + "so summoning a pad mid-task costs you nothing to undo."),
          .text(
            "Close a pad and its contents are still there next time. There is no save step, "
              + "because there is no version of this where you lose something by forgetting "
              + "one."),
        ]),
    ])

  static let pads = HelpTopic(
    id: "pads",
    title: "Working with pads",
    symbol: "square.on.square",
    blurb: "Creating, naming, pinning, emptying and deleting, and what each one costs you.",
    sections: [
      HelpSection(
        heading: "Creating and deleting pads",
        blocks: [
          .text(
            "New Pad, from the menubar or ⌘N, creates a pad and puts the cursor in it "
              + "without asking for anything. You get \(PadBounds.defaultCount) pads by "
              + "default and can have up to \(PadBounds.hardCeiling), which you set in "
              + "Settings → General."),
          .text(
            "Lowering that number deletes nothing and hides nothing; it applies to new pads "
              + "only, and the setting says so when you lower it below the number you "
              + "already have."),
          .note(
            "Deleting a pad is the one action Itchy asks you to confirm, because it is the "
              + "only way to lose content."),
        ]),
      HelpSection(
        heading: "Styled and plain pads",
        blocks: [
          .text(
            "A styled pad keeps formatting and images, so pasting from a browser or a word "
              + "processor brings the formatting and any screenshots with it. ⌘B, ⌘I and ⌘U "
              + "work, and there are buttons at the bottom of the pad."),
          .text(
            "A plain pad holds text and nothing else, which is what you want for code and "
              + "JSON, where smart quotes are never welcome. Switching a styled pad to plain "
              + "strips its formatting in one step, and one undo puts it back."),
        ]),
      HelpSection(
        heading: "A pad's own settings",
        blocks: [
          .text(
            "The ⋯ button at the bottom right of a pad opens that pad's settings: its name, "
              + "its mode, whether it reopens when Itchy starts, whether model work on it "
              + "may reach a remote service, and whether agents may read it. The last two "
              + "are covered in Models and in Letting an agent use your pads."),
          .text(
            "Naming is optional and worth doing for a pad you will ask an agent for by "
              + "name. The settings sheet warns you when two pads share a name, because at "
              + "that point an agent cannot tell them apart."),
          .text(
            "Pinning a pad means its window comes back when Itchy starts, in the place you "
              + "left it, without taking your keyboard focus."),
        ]),
      HelpSection(
        heading: "The status line",
        blocks: [
          .text(
            "Along the bottom of each pad: its name, its mode, how many pastes it has "
              + "recorded, its routing policy once you have a model configured, whether it "
              + "is exposed to agents, and anything that has just gone wrong. It is the "
              + "first place to look when a pad is not behaving.")
        ]),
    ])

  static let transforms = HelpTopic(
    id: "transforms",
    title: "Transforms",
    symbol: "wand.and.sparkles",
    blurb: "Reshaping the text in a pad without leaving it, and always with an undo.",
    sections: [
      HelpSection(
        heading: "Running a transform",
        blocks: [
          .text(
            "The wand button at the bottom of a pad lists what can be done to the text in "
              + "front of you: flatten styling; upper, lower and title case; pretty-print "
              + "and minify JSON; encode and decode base64; encode and decode URL "
              + "components; trim whitespace; and sort lines. If you have set a model up, "
              + "the model-backed transforms are underneath those — see Models."),
          .steps([
            "Select the part you want to change, or select nothing to act on the whole pad.",
            "Choose a transform from the wand menu.",
            "If it was not what you wanted, press ⌘Z. Each transform is a single undo step, "
              + "and the Edit menu names it.",
          ]),
        ]),
      HelpSection(
        heading: "Why some are unavailable",
        blocks: [
          .text(
            "A transform is offered only when it would work on the text in front of you, so "
              + "Decode Base64 is unavailable on text that is not base64 and the JSON "
              + "transforms are unavailable on text that is not JSON. Hovering over a "
              + "disabled entry says why."),
          .text(
            "The alternative would be a menu that offers everything and then fails, which "
              + "teaches you to distrust the menu."),
        ]),
      HelpSection(
        heading: "When a transform fails",
        blocks: [
          .text(
            "Nothing happens to the pad, and the reason appears in the pad's status line for "
              + "a few seconds. Itchy does not stop you with a dialogue for this, because a "
              + "scratchpad that interrupts is a scratchpad that gets in the way."),
          .note(
            "Pretty-printing JSON preserves the order of keys and does not reformat numbers, "
              + "so text that goes through it and comes back is the same document rather "
              + "than an equivalent one."),
        ]),
    ])
}
