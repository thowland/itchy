import AppKit
import ItchyCore
import ItchyServices
import Testing

@testable import Itchy

/// `FR-8.8` and §11.6: an agent's write to a pad whose panel is open goes
/// *into* the panel, so it is one undo from reverted — rather than past it into
/// the store, where the panel's next save would overwrite it and the agent
/// would be told it succeeded.
@MainActor
@Suite("Agent writes into an open panel")
final class AgentWriteIntegrationTests {
  /// Held for the lifetime of the suite: `NSTextView.undoManager` is the
  /// window's, so a view with no window has none and every undo call quietly
  /// does nothing. The windows are never shown.
  private var windows: [NSWindow] = []

  private func makeEditor(text: String = "typed by hand")
    -> (PadTextCoordinator, PadTextView, PadID, URL) {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("itchy-agentwrite-\(UUID().uuidString)")
    let store = PadStore(layout: PadStorageLayout(root: root))
    let padID = PadID()
    let coordinator = PadTextCoordinator(padID: padID, store: store)
    let textView = PadTextView()
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
      styleMask: [.titled], backing: .buffered, defer: true)
    window.contentView = textView
    textView.allowsUndo = true
    textView.configure(for: .styled)
    textView.textStorage?.setAttributedString(
      NSAttributedString(string: text, attributes: [.font: textView.bodyFont]))
    coordinator.attach(textView)
    windows.append(window)
    return (coordinator, textView, padID, root)
  }

  @Test("write_pad replaces the panel's text")
  func writeReplaces() async {
    let (coordinator, textView, _, root) = makeEditor()
    defer { try? FileManager.default.removeItem(at: root) }

    let applied = await coordinator.applyAgentWrite(
      .replaceAll, text: "from the agent", origin: .mcp(client: "claude"))

    #expect(applied)
    #expect(textView.string == "from the agent")
  }

  @Test("append_pad adds to the end and leaves what was there")
  func appendAdds() async {
    let (coordinator, textView, _, root) = makeEditor()
    defer { try? FileManager.default.removeItem(at: root) }

    let applied = await coordinator.applyAgentWrite(
      .append, text: " and more", origin: .mcp(client: "claude"))

    #expect(applied)
    #expect(textView.string == "typed by hand and more")
  }

  /// The requirement itself: one undo, and the Edit menu names what it will
  /// revert.
  @Test("One undo reverts the agent's write exactly, and the step is named")
  func oneUndo() async {
    let (coordinator, textView, _, root) = makeEditor()
    defer { try? FileManager.default.removeItem(at: root) }

    _ = await coordinator.applyAgentWrite(
      .replaceAll, text: "from the agent", origin: .mcp(client: "claude"))
    #expect(textView.undoManager?.undoActionName == "Write from claude")

    textView.undoManager?.undo()

    #expect(textView.string == "typed by hand")
  }

  /// The applier replaces the range rather than merging into it, so an agent
  /// write lands as written rather than inheriting whatever styling happened to
  /// be at the insertion point.
  @Test("An agent write does not inherit the styling it replaced")
  func doesNotInheritStyling() async {
    let (coordinator, textView, _, root) = makeEditor()
    defer { try? FileManager.default.removeItem(at: root) }
    textView.textStorage?.setAttributedString(
      NSAttributedString(
        string: "bold", attributes: [.font: NSFont.boldSystemFont(ofSize: 24)]))

    _ = await coordinator.applyAgentWrite(
      .replaceAll, text: "plain", origin: .mcp(client: "claude"))

    let font = textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    #expect(font == textView.bodyFont)
  }

  /// The gate is the registry, not the editor cache: an editor outlives its
  /// panel, so a write routed by "is there an editor" would land in a text view
  /// nobody can see and no undo can reach.
  @Test("A write to a pad with no panel is not applied here")
  func noPanel() async {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("itchy-agentwrite-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let layout = PadStorageLayout(root: root)
    let coordinator = PadCoordinator(
      store: PadStore(layout: layout), layout: layout, launchOptions: LaunchOptions())

    let applied = await coordinator.applyAgentWrite(
      .replaceAll, text: "x", to: PadID(), origin: .mcp(client: "claude"))

    #expect(applied == false)
  }

  /// And because the writer can now reach an open pad, Sprint 8's refusal stops
  /// applying — which is the whole point of the flag rather than deleting the
  /// policy.
  @Test("The registry-aware writer claims open pads, so the refusal lapses")
  func refusalLapses() {
    #expect(OpenPadPolicy.admit(isOpen: true, writerReachesOpenPads: true) == .proceed)
  }
}
