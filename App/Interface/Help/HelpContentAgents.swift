import Foundation
import ItchyCore

/// The agent, backup and privacy topics.
///
/// Split from `HelpContent` because one file of prose per three topics is about
/// as much as stays readable, and these three are the ones somebody arrives at
/// with a specific question.
extension HelpContent {
  static let agents = HelpTopic(
    id: "agents",
    title: "Letting an agent use your pads",
    symbol: "point.3.filled.connected.trianglepath.dotted",
    blurb: "Setting up the agent server, and what an agent can and cannot do once you have.",
    sections: [
      HelpSection(
        heading: "What this is",
        blocks: [
          .text(
            "A coding agent can read and write your pads over the Model Context Protocol. "
              + "This is the thing Itchy exists for: a pad becomes a surface both you and "
              + "an agent can work on, instead of text being carried between you by "
              + "copy and paste."),
          .text(
            "None of it happens until you switch it on, and then only for the pads you "
              + "choose. There are three separate things that must all be true before an "
              + "agent can read a word: the server is on, that pad is exposed, and the "
              + "agent has the token."),
        ]),
      HelpSection(
        heading: "Switching the server on",
        blocks: [
          .steps([
            "Open Settings → Agents.",
            "Turn on “\(MCPSettingsModel.enableLabel)”.",
            "Read the line underneath. It says which port it is listening on, and the "
              + "menubar says so too while it is running.",
          ]),
          .text(
            "It listens on 127.0.0.1 and nothing else. That address means this machine "
              + "and no other — nothing on your network can reach it, and neither can "
              + "anything on the internet. That is a property of how the socket is opened "
              + "rather than a check that could be got wrong."),
          .note(
            "If it says the port is already in use, something else on your Mac has it. "
              + "Change the number; any port will do, and the server restarts on the new "
              + "one by itself."),
        ]),
      HelpSection(
        heading: "The token",
        blocks: [
          .text(
            "Beside the switch is a bearer token. Press Show to read it or Copy to put it "
              + "on the clipboard, and give it to the agent. A request without it is "
              + "refused and told nothing at all about what pads exist."),
          .text(
            "Regenerate makes a new token and stops the old one working straight away, "
              + "including for agents that are already connected. That is what to use if "
              + "you have pasted the token somewhere you should not have."),
        ]),
      HelpSection(
        heading: "Exposing a pad",
        blocks: [
          .text(
            "Every pad is private until you say otherwise, and switching the server on "
              + "does not change that. Open a pad's own settings — the ⋯ button — and turn "
              + "on “\(MCPSettingsModel.exposureLabel)”."),
          .text(
            "An exposed pad says “exposed” in its status line, so you can see at a glance "
              + "which ones are reachable."),
          .text(
            "A pad you have not exposed is not merely hidden. An agent asking for it by "
              + "name is told there is no such pad — the same answer it gets for a pad that "
              + "does not exist — so the tools cannot be used to find out what you have."),
        ]),
      HelpSection(
        heading: "What an agent can do",
        blocks: [
          .text(
            "Five things, and the narrowness is the point: list the exposed pads, read "
              + "one, append to one, replace one, and create a new pad. There is no sixth "
              + "tool and adding one would be a deliberate decision rather than a line "
              + "somebody slipped in."),
          .text(
            "A pad an agent creates is exposed to it, because otherwise it could not read "
              + "back what it had just written. It appears in your menu like any other pad, "
              + "marked exposed, and you can withdraw it or delete it."),
          .note(
            "An agent reads plain text, so a picture in a pad reaches it as a line saying "
              + "[image 1240×820]. It is told something is there rather than quietly given "
              + "a pad with a hole in it."),
        ]),
      HelpSection(
        heading: "Seeing what was written",
        blocks: [
          .text(
            "A pad that something other than you wrote to shows a banner saying who wrote, "
              + "how much, and when."),
          .text(
            "If the pad was open at the time, the banner's Undo reverts that write and "
              + "nothing else, and the Edit menu names it so you can see what you are about "
              + "to undo. If the pad was closed, there is nothing to undo — a pad's undo "
              + "history starts when you open it — so the banner says so rather than "
              + "offering a button that would quietly revert something else. The menubar "
              + "marks the pad until you have looked at it."),
        ]),
      HelpSection(
        heading: "Agents that cannot speak HTTP",
        blocks: [
          .text(
            "Some agents expect to launch a command and talk to it over its input and "
              + "output rather than over a network port. Itchy will ship a small shim for "
              + "that, and it is not finished: it needs both programs signed by the same "
              + "developer certificate in order to share the token, and that certificate is "
              + "the same one the first release is waiting for."),
          .text(
            "Until then, use an agent that can be pointed at an HTTP endpoint."),
        ]),
    ])

  static let backups = HelpTopic(
    id: "backups",
    title: "Backups",
    symbol: "clock.arrow.circlepath",
    blurb: "What Itchy keeps a copy of, how long for, and how to get something back.",
    sections: [
      HelpSection(
        heading: "What they are",
        blocks: [
          .text(
            "Itchy takes a copy of all your pads when it starts, when it quits, and once "
              + "a day if you leave it running. They exist because pads are held in a "
              + "format this application is still changing, and a defect in that layer "
              + "would otherwise be unrecoverable."),
          .text(
            "A copy is only taken when something has actually changed. Without that, a "
              + "day of starting and quitting would fill the limit with identical copies "
              + "and push out the one snapshot that mattered."),
        ]),
      HelpSection(
        heading: "Setting them up",
        blocks: [
          .steps([
            "Open Settings → Backups.",
            "Choose how many to keep. \(ArchiveBounds.defaultRetention) is the default and "
              + "\(ArchiveBounds.maximumRetention) is the most.",
            "Leave “once a day” on if Itchy stays running for days at a time; turn it off "
              + "if you quit it often, in which case start and quit already cover you.",
          ]),
          .text(
            "Zero is one of the choices, and it switches backups off entirely. That is "
              + "deliberate: a backup holds a copy of every pad, including ones you have "
              + "since deleted, so whether they exist at all is your decision and not "
              + "Itchy's."),
        ]),
      HelpSection(
        heading: "Getting something back",
        blocks: [
          .text(
            "Settings → Backups lists what exists, with when it was taken and how large "
              + "it is, and Show in Finder opens the folder. Each backup is an ordinary "
              + "directory of ordinary files — one folder per pad, with the styled content "
              + "and a plain-text copy alongside it."),
          .steps([
            "Quit Itchy.",
            "Open the backups folder and find the one from before the problem.",
            "Copy the pad folders you want out of it.",
            "Put them in ~/Library/Application Support/Itchy/"
              + "\(PadStorageLayout.padsDirectoryName)/, replacing what is there.",
            "Start Itchy again.",
          ]),
          .note(
            "Remove All Backups deletes every copy, including copies of pads you have "
              + "already deleted. It is there for exactly that reason, and it cannot be "
              + "undone."),
        ]),
      HelpSection(
        heading: "Why there is no backup",
        blocks: [
          .text(
            "There are four reasons and they look the same from outside: backups are "
              + "switched off, the daily one is not due yet, nothing has changed since the "
              + "last one, or the copy failed. If you need to tell them apart, switch on "
              + "the diagnostic log in Settings → General; it records every attempt and "
              + "which of the four it was.")
        ]),
    ])

  static let filesAndPrivacy = HelpTopic(
    id: "files",
    title: "Your files, and what leaves them",
    symbol: "lock.doc",
    blurb: "Where pads live, what is kept out of them, and the diagnostic log.",
    sections: [
      HelpSection(
        heading: "Where pads are",
        blocks: [
          .text(
            "In ~/Library/Application Support/Itchy/"
              + "\(PadStorageLayout.padsDirectoryName)/, one folder per pad. "
              + "Each holds the styled content, a plain-text copy of the same thing, and a "
              + "small file of settings. They are ordinary files and you can read them with "
              + "anything."),
          .note(
            "The .noindex on that folder is load-bearing: it is what keeps every pad out "
              + "of Spotlight. Renaming the folder without it would quietly put the "
              + "contents of all your pads back into the search index."),
        ]),
      HelpSection(
        heading: "What Itchy sends",
        blocks: [
          .text(
            "Nothing. Itchy makes no network connections of its own, has no telemetry and "
              + "no accounts, and the agent server — when you switch it on — listens on "
              + "this machine only and never dials out.")
        ]),
      HelpSection(
        heading: "The diagnostic log",
        blocks: [
          .text(
            "Settings → General has a switch for a diagnostic log. It is off by default "
              + "and is worth switching on when something is misbehaving and you want to "
              + "see what Itchy thought it was doing — a backup that decided not to happen, "
              + "an agent request that was refused, a transform that declined."),
          .text(
            "It is written to \(DebugLog.defaultPath) and it records what happened, to "
              + "which pad by "
              + "name, and how many characters were involved. It does not contain the text "
              + "of your pads, anything an agent wrote, or the agent token — not as a "
              + "policy but because there is no way for it to: the log can only say the "
              + "things it has words for."),
          .note(
            "/tmp can be read by anyone with an account on this Mac, so pad names do end "
              + "up somewhere slightly more public than usual. Switch the log off and "
              + "delete the file when you are finished with it."),
        ]),
    ])
}
