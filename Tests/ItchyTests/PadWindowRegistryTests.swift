import AppKit
import ItchyCore
import SwiftUI
import Testing

@testable import Itchy

/// These run against a real window server, which the test host provides. What
/// they cover is the registry's bookkeeping — the decisions that would otherwise
/// only be observable by opening pads and counting windows.
@MainActor
@Suite("Pad window registry")
struct PadWindowRegistryTests {
  private func makeStore() -> (PadStore, URL) {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("itchy-registry-\(UUID().uuidString)")
    return (PadStore(layout: PadStorageLayout(root: root)), root)
  }

  private func pad(_ name: String = "scratch") -> PadMetadata {
    PadMetadata(name: name, created: .distantPast, modified: .distantPast)
  }

  private func content(store: PadStore) -> some View {
    PadTextEditor(
      coordinator: PadTextCoordinator(padID: PadID(), store: store),
      mode: PadMode.styled,
      initial: NSAttributedString(string: "scratch"),
      font: ContentCodec.defaultFont)
  }

  /// `FR-3.3`: opening a pad that is already open brings the existing panel
  /// forward rather than creating a second window on the same pad.
  @Test("Opening the same pad five times yields one window")
  func oneWindowPerPad() async {
    let (store, root) = makeStore()
    defer { try? FileManager.default.removeItem(at: root) }
    let registry = PadWindowRegistry(store: store)
    let target = pad()

    var controllers: [PadWindowController] = []
    for _ in 0..<5 {
      controllers.append(registry.show(target, content: content(store: store), makingKey: false))
    }

    #expect(registry.openCount == 1)
    #expect(controllers.allSatisfy { $0 === controllers[0] })
    registry.close(target.id)
  }

  @Test("Different pads get different windows")
  func onePanelEach() async {
    let (store, root) = makeStore()
    defer { try? FileManager.default.removeItem(at: root) }
    let registry = PadWindowRegistry(store: store)
    let first = pad("a")
    let second = pad("b")

    registry.show(first, content: content(store: store), makingKey: false)
    registry.show(second, content: content(store: store), makingKey: false)

    #expect(registry.openCount == 2)
    #expect(registry.isOpen(first.id))
    #expect(registry.isOpen(second.id))
    registry.close(first.id)
    registry.close(second.id)
  }

  @Test("A pad that was never opened is not open")
  func unopened() async {
    let (store, root) = makeStore()
    defer { try? FileManager.default.removeItem(at: root) }
    let registry = PadWindowRegistry(store: store)
    #expect(!registry.isOpen(PadID()))
    #expect(registry.controller(for: PadID()) == nil)
    #expect(!registry.isFrontmostAndKey(PadID()))
  }

  /// The panel is positioned by `FrameResolver`, so a pad with a stored frame
  /// opens where it was left (`FR-3.4`).
  @Test("A stored frame is applied to the panel")
  func storedFrameIsApplied() async {
    let (store, root) = makeStore()
    defer { try? FileManager.default.removeItem(at: root) }
    let registry = PadWindowRegistry(store: store)
    var target = pad()
    let screen = try? #require(NSScreen.main)
    let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1_440, height: 900)
    target.frame = PadFrame(
      x: visible.minX + 120, y: visible.minY + 120, width: 400, height: 480)

    let controller = registry.show(target, content: content(store: store), makingKey: false)

    #expect(controller.panel.frame.width == 400)
    #expect(controller.panel.frame.height == 480)
    registry.close(target.id)
  }

  @Test("The panel takes the pad's name as its title")
  func title() async {
    let (store, root) = makeStore()
    defer { try? FileManager.default.removeItem(at: root) }
    let registry = PadWindowRegistry(store: store)
    let target = pad("json dump")

    let controller = registry.show(target, content: content(store: store), makingKey: false)

    #expect(controller.panel.title == "json dump")
    registry.close(target.id)
  }

  /// D-14: a pad appearing must not take keyboard focus, because pinned pads
  /// reopen at launch and an application that steals the keyboard on login is an
  /// application that gets quit.
  @Test("Showing without making key leaves the panel unfocused")
  func showWithoutFocus() async {
    let (store, root) = makeStore()
    defer { try? FileManager.default.removeItem(at: root) }
    let registry = PadWindowRegistry(store: store)
    let target = pad()

    let controller = registry.show(target, content: content(store: store), makingKey: false)

    #expect(controller.isVisible)
    #expect(!controller.isKey)
    registry.close(target.id)
  }
}
