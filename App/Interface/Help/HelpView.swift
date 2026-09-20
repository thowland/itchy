import SwiftUI

/// The help window's contents.
///
/// This file is on the coverage exclusion list and may not branch. Everything it
/// would otherwise decide — which topic is shown, what the lines are, how each
/// one is set — is `HelpBook`'s, which is why a line carries concrete numbers
/// rather than a style the view would have to interpret.
struct HelpView: View {
  @State private var selection: String

  init(topic: String = HelpBook.defaultTopic) {
    _selection = State(initialValue: topic)
  }

  var body: some View {
    NavigationSplitView {
      List(HelpBook.topics, selection: $selection) { topic in
        Label(topic.title, systemImage: topic.symbol)
          .tag(topic.id)
          .accessibilityIdentifier("help.topic.\(topic.id)")
      }
      // Wide enough for the longest topic title. At 210 three of the eight
      // truncated in their own sidebar, which a screenshot made obvious and
      // daily use never would, because you learn where they are.
      .navigationSplitViewColumnWidth(min: 230, ideal: 265, max: 320)
    } detail: {
      HelpPage(topic: HelpBook.resolve(selection))
    }
    .frame(minWidth: 720, minHeight: 480)
  }
}

/// One topic, drawn in order.
struct HelpPage: View {
  let topic: HelpTopic

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(HelpBook.lines(for: topic)) { line in
          HelpLineText(line: line)
        }
      }
      .frame(maxWidth: 560, alignment: .leading)
      .padding(.horizontal, 28)
      .padding(.vertical, 24)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .accessibilityIdentifier("help.page")
  }
}

/// One line. No conditionals: the numbers arrive already decided.
struct HelpLineText: View {
  let line: HelpLine

  var body: some View {
    Text(line.text)
      .font(.system(size: line.style.size, weight: HelpWeight.of(line.style)))
      .opacity(line.style.opacity)
      .padding(.leading, line.style.indent)
      .padding(.top, line.style.spaceAbove)
      .fixedSize(horizontal: false, vertical: true)
      .textSelection(.enabled)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// The one mapping the view cannot express as a number (D-11).
enum HelpWeight {
  static func of(_ style: HelpLineStyle) -> Font.Weight {
    style.isBold ? .semibold : .regular
  }
}
