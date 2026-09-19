import Foundation

/// A page of help, and the pieces it is made of.
///
/// The content is Swift values rather than a bundled Markdown file, for a
/// reason that is not stylistic: only the store may read from disk (`CON-4`),
/// so a help view that loaded a resource would have to either break that rule
/// or route documentation through the pad store. Values also mean the text is
/// compiled, so a topic that references a setting that no longer exists is a
/// thing the suite can notice.
struct HelpTopic: Identifiable, Equatable {
  let id: String
  let title: String
  /// An SF Symbol for the sidebar. A name, not an image: `HelpBook` links no UI
  /// framework beyond this string.
  let symbol: String
  /// One sentence, shown under the title.
  let blurb: String
  let sections: [HelpSection]
}

struct HelpSection: Equatable {
  let heading: String
  let blocks: [HelpBlock]
}

/// The kinds of thing a section contains.
enum HelpBlock: Equatable {
  case text(String)
  /// Numbered, because a numbered list is a promise that the order matters.
  case steps([String])
  /// Set apart. For the thing that will otherwise be found out the hard way.
  case note(String)
}

/// One rendered line, with everything the view needs in order to draw it
/// without deciding anything (D-11).
///
/// The help window is a view file, so it may not branch — which means it cannot
/// switch over `HelpBlock` to choose a font. Flattening happens here instead,
/// and the view maps each line straight onto modifiers.
struct HelpLine: Identifiable, Equatable {
  let id: Int
  let text: String
  let style: HelpLineStyle
}

/// How a line is set. Concrete numbers rather than cases the view must
/// interpret: `.foregroundStyle(.secondary)` is a branch when it is
/// conditional, and an opacity is not.
struct HelpLineStyle: Equatable {
  let size: Double
  let isBold: Bool
  let indent: Double
  let opacity: Double
  /// Space above, so that a heading is separated from what precedes it without
  /// the view knowing why.
  let spaceAbove: Double

  static let title = HelpLineStyle(
    size: 22, isBold: true, indent: 0, opacity: 1, spaceAbove: 0)
  static let blurb = HelpLineStyle(
    size: 13, isBold: false, indent: 0, opacity: 0.65, spaceAbove: 2)
  static let heading = HelpLineStyle(
    size: 15, isBold: true, indent: 0, opacity: 1, spaceAbove: 20)
  static let body = HelpLineStyle(
    size: 13, isBold: false, indent: 0, opacity: 0.9, spaceAbove: 8)
  static let step = HelpLineStyle(
    size: 13, isBold: false, indent: 16, opacity: 0.9, spaceAbove: 4)
  static let note = HelpLineStyle(
    size: 12, isBold: false, indent: 12, opacity: 0.7, spaceAbove: 10)
}

/// The help book: which topics exist, and what each one renders to.
enum HelpBook {
  static let topics: [HelpTopic] = [
    HelpContent.gettingStarted,
    HelpContent.pads,
    HelpContent.transforms,
    HelpContent.agents,
    HelpContent.clients,
    HelpContent.backups,
    HelpContent.filesAndPrivacy,
  ]

  /// The topic to open on, when nothing more specific is asked for.
  static let defaultTopic = HelpContent.gettingStarted.id

  static func topic(id: String) -> HelpTopic? {
    topics.first { $0.id == id }
  }

  /// The topic to show, given what was asked for. An unknown identifier — from
  /// a stale deep link, say — opens the first topic rather than an empty page.
  static func resolve(_ requested: String?) -> HelpTopic {
    guard let requested, let found = topic(id: requested) else {
      return topics.first ?? HelpContent.gettingStarted
    }
    return found
  }

  /// The whole of a topic, flattened into lines the view can draw in order.
  static func lines(for topic: HelpTopic) -> [HelpLine] {
    var lines: [HelpLine] = []
    var next = 0
    func add(_ text: String, _ style: HelpLineStyle) {
      lines.append(HelpLine(id: next, text: text, style: style))
      next += 1
    }

    add(topic.title, .title)
    add(topic.blurb, .blurb)
    for section in topic.sections {
      add(section.heading, .heading)
      for block in section.blocks {
        switch block {
        case .text(let text):
          add(text, .body)
        case .steps(let steps):
          for (index, step) in steps.enumerated() {
            add("\(index + 1).  \(step)", .step)
          }
        case .note(let text):
          add(text, .note)
        }
      }
    }
    return lines
  }
}
