import AppKit
import ItchyCore
import ItchyServices
import Testing

@testable import Itchy

/// The help book. Content as values means the suite can hold it to the same
/// standard as the code: that every topic the window offers actually has
/// something in it, and that what it says about a setting is still true.
@Suite("Help book")
struct HelpBookTests {
  // MARK: - Structure

  @Test("The subjects that were asked for all have a topic")
  func coversTheSubjects() {
    let ids = Set(HelpBook.topics.map(\.id))
    #expect(ids.contains("getting-started"))
    #expect(ids.contains("agents"))
    #expect(ids.contains("clients"))
    #expect(ids.contains("backups"))
    #expect(ids.contains("transforms"))
  }

  // MARK: - Connecting a client

  /// The address is the one thing that must be right, and it is assembled from
  /// three values that live in three different places. Interpolated rather than
  /// typed, so a changed port or path changes the instructions.
  @Test("The connection instructions name the address the server actually serves")
  func clientAddressMatchesTheServer() {
    let text = allText(of: HelpContent.clients)
    #expect(text.contains("127.0.0.1:\(MCPBounds.defaultPort)\(MCPServerHost.path)"))
    #expect(text.contains(MCPServerHost.path))
  }

  @Test("Every client is covered, including the one that runs locally for OpenAI")
  func clientsCovered() {
    let headings = HelpContent.clients.sections.map(\.heading)
    #expect(headings.contains("Claude Code"))
    #expect(headings.contains("Codex"))
    #expect(headings.contains("Claude Desktop"))
    #expect(headings.contains("ChatGPT's own connectors"))
  }

  /// Codex runs on the machine and speaks Streamable HTTP, so it reaches a
  /// loopback address directly. It names an environment variable rather than
  /// taking the token, which keeps the token out of the config file.
  @Test("The Codex section gives the loopback URL and the token env var")
  func codexConfiguration() {
    let text = allText(of: HelpContent.clients)
    #expect(text.contains("bearer_token_env_var"))
    #expect(text.contains("~/.codex/config.toml"))
    #expect(text.contains("codex mcp add itchy --url"))
  }

  /// Claude Code's project scope writes the token into a file most people
  /// commit. Saying so is the whole value of that section.
  @Test("The Claude Code section warns about the scope that commits the token")
  func warnsAboutProjectScope() {
    let text = allText(of: HelpContent.clients)
    #expect(text.contains("--scope user"))
    #expect(text.contains("Do not use --scope project"))
    #expect(text.contains(".mcp.json"))
  }

  /// Not a typo, and the one detail that silently breaks the Desktop setup.
  @Test("The Claude Desktop section keeps the no-space header quirk")
  func desktopHeaderQuirk() {
    let text = allText(of: HelpContent.clients)
    #expect(text.contains("Authorization:${AUTH}"))
    #expect(text.contains("--allow-http"))
    #expect(text.contains("no space after"))
  }

  /// "ChatGPT cannot connect" was too broad: its own connectors cannot, and
  /// Codex can. The section has to send people to the thing that works rather
  /// than leave them with a flat no, and still refuse the tunnel.
  @Test("The connector section points at Codex and refuses the tunnel")
  func connectorsCannotReachLoopback() {
    let text = allText(of: HelpContent.clients)
    #expect(text.contains("cannot reach Itchy"))
    #expect(text.contains("Use Codex instead"))
    #expect(text.contains("tunnel"))
    #expect(text.contains("Do not."))
  }

  /// The distinction that decides every case: opened from a server, or opened
  /// from this Mac. It is worth stating once rather than per client.
  @Test("The reason a connector cannot see loopback is stated, not just the fact")
  func explainsWhereTheConnectionIsMadeFrom() {
    let text = allText(of: HelpContent.clients)
    #expect(text.contains("opened by OpenAI's servers"))
    #expect(text.contains("127.0.0.1"))
  }

  @Test("The agents topic hands off to the client topic rather than dead-ending")
  func agentsLinksToClients() {
    #expect(allText(of: HelpContent.agents).contains(HelpContent.clients.title))
  }

  @Test("Every topic has a unique identifier, a title, a blurb and a symbol")
  func topicsAreWellFormed() {
    #expect(Set(HelpBook.topics.map(\.id)).count == HelpBook.topics.count)
    for topic in HelpBook.topics {
      #expect(!topic.title.isEmpty, "\(topic.id) has no title")
      #expect(!topic.blurb.isEmpty, "\(topic.id) has no blurb")
      #expect(!topic.symbol.isEmpty, "\(topic.id) has no symbol")
      #expect(!topic.sections.isEmpty, "\(topic.id) has no sections")
    }
  }

  /// A named symbol that does not exist renders as a blank in the sidebar,
  /// which looks like a missing icon and is one.
  @Test("Every sidebar symbol exists on this system")
  func symbolsExist() {
    for topic in HelpBook.topics {
      #expect(
        NSImage(systemSymbolName: topic.symbol, accessibilityDescription: nil) != nil,
        "\(topic.id) names a symbol that does not exist: \(topic.symbol)")
    }
  }

  @Test("No section is empty, and no block is blank")
  func sectionsHaveContent() {
    for topic in HelpBook.topics {
      for section in topic.sections {
        #expect(!section.heading.isEmpty, "\(topic.id) has an unheaded section")
        #expect(!section.blocks.isEmpty, "\(topic.id)/\(section.heading) is empty")
        for block in section.blocks {
          #expect(!blockIsBlank(block), "\(topic.id)/\(section.heading) has a blank block")
        }
      }
    }
  }

  // MARK: - Rendering

  @Test("A topic flattens to lines, titled first and blurbed second")
  func lines() {
    let topic = HelpContent.agents
    let lines = HelpBook.lines(for: topic)
    #expect(lines.first?.text == topic.title)
    #expect(lines.first?.style == HelpLineStyle.title)
    #expect(lines.dropFirst().first?.text == topic.blurb)
    #expect(lines.count > 10)
  }

  @Test("Line identifiers are unique, so the list does not reuse a row")
  func lineIdentifiers() {
    for topic in HelpBook.topics {
      let lines = HelpBook.lines(for: topic)
      #expect(Set(lines.map(\.id)).count == lines.count, "\(topic.id) repeats a line id")
    }
  }

  @Test("Steps are numbered in the order they were written")
  func stepsAreNumbered() {
    let topic = HelpTopic(
      id: "x", title: "T", symbol: "star", blurb: "B",
      sections: [HelpSection(heading: "H", blocks: [.steps(["first", "second"])])])
    let steps = HelpBook.lines(for: topic).filter { $0.style == .step }
    #expect(steps.map(\.text) == ["1.  first", "2.  second"])
  }

  @Test("Every kind of block reaches the page with its own setting")
  func everyBlockKindRenders() {
    let topic = HelpTopic(
      id: "x", title: "T", symbol: "star", blurb: "B",
      sections: [
        HelpSection(heading: "H", blocks: [.text("body"), .steps(["one"]), .note("careful")])
      ])
    let styles = HelpBook.lines(for: topic).map(\.style)
    #expect(styles.contains(.heading))
    #expect(styles.contains(.body))
    #expect(styles.contains(.step))
    #expect(styles.contains(.note))
  }

  @Test("A heading is set apart from what comes before it")
  func headingsAreSeparated() {
    #expect(HelpLineStyle.heading.spaceAbove > HelpLineStyle.body.spaceAbove)
    #expect(HelpLineStyle.heading.isBold)
    #expect(HelpLineStyle.step.indent > HelpLineStyle.body.indent)
    #expect(HelpWeight.of(.heading) == .semibold)
    #expect(HelpWeight.of(.body) == .regular)
  }

  // MARK: - Which topic opens

  @Test("An unknown topic opens the book rather than an empty page")
  func resolvesUnknown() {
    #expect(HelpBook.resolve(nil).id == HelpBook.topics.first?.id)
    #expect(HelpBook.resolve("no-such-topic").id == HelpBook.topics.first?.id)
    #expect(HelpBook.resolve("agents").id == "agents")
    #expect(HelpBook.topic(id: "backups")?.title.isEmpty == false)
    #expect(HelpBook.topic(id: "nope") == nil)
  }

  @Test("The default topic is one that exists")
  func defaultTopicExists() {
    #expect(HelpBook.topic(id: HelpBook.defaultTopic) != nil)
  }

  /// The Agents settings section deep-links into the book. A renamed topic
  /// would otherwise open the wrong page, or none, and nothing would say so.
  @Test("The topic the Agents settings link to exists")
  func agentsDeepLinkResolves() {
    #expect(HelpBook.topic(id: HelpText.agentsTopic) != nil)
    #expect(HelpBook.resolve(HelpText.agentsTopic).id == HelpContent.agents.id)
    #expect(HelpText.agentsSetupButton.isEmpty == false)
  }

  // MARK: - Staying true

  /// Help that names a control is help that goes stale silently. These hold the
  /// prose to the values it describes, so that changing one without the other
  /// fails here rather than in front of somebody who is already stuck.
  @Test("What the agents topic says about the port and the tools is still true")
  func agentsTopicIsAccurate() {
    let text = allText(of: HelpContent.agents)
    #expect(text.contains("127.0.0.1"))
    #expect(text.contains("Five things"))
    #expect(text.contains(MCPSettingsModel.enableLabel))
    #expect(text.contains(MCPSettingsModel.exposureLabel))
  }

  @Test("What the backups topic says about retention matches the bounds")
  func backupsTopicIsAccurate() {
    let text = allText(of: HelpContent.backups)
    #expect(text.contains(String(ArchiveBounds.defaultRetention)))
    #expect(text.contains(String(ArchiveBounds.maximumRetention)))
    #expect(text.contains(PadStorageLayout.padsDirectoryName))
  }

  @Test("What the privacy topic says about the log matches where it is written")
  func privacyTopicIsAccurate() {
    let text = allText(of: HelpContent.filesAndPrivacy)
    #expect(text.contains(DebugLog.defaultPath))
    #expect(text.contains(PadStorageLayout.padsDirectoryName))
  }

  @Test("What the pads topic says about the limits matches the bounds")
  func padsTopicIsAccurate() {
    let text = allText(of: HelpContent.pads)
    #expect(text.contains(String(PadBounds.hardCeiling)))
  }

  @Test("Every transform the registry offers is named in the transforms topic")
  func transformsTopicNamesThem() {
    let text = allText(of: HelpContent.transforms).lowercased()
    #expect(text.contains("base64"))
    #expect(text.contains("json"))
    #expect(text.contains("sort lines"))
    #expect(text.contains("⌘z"))
  }

  // MARK: - Helpers

  private func allText(of topic: HelpTopic) -> String {
    HelpBook.lines(for: topic).map(\.text).joined(separator: "\n")
  }

  private func blockIsBlank(_ block: HelpBlock) -> Bool {
    switch block {
    case .text(let text), .note(let text):
      return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    case .steps(let steps):
      return steps.isEmpty || steps.contains { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
  }
}
