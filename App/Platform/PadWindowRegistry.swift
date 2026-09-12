import AppKit
import ItchyCore
import SwiftUI

/// Every open pad panel, keyed by pad.
///
/// Opening a pad that is already open brings its panel forward rather than
/// creating a second window on the same pad (`FR-3.3`). From Sprint 6 this also
/// holds the grouped appliers a transform or an agent write goes through
/// (specification §8.3).
@MainActor
final class PadWindowRegistry {
  private var controllers: [PadID: PadWindowController] = [:]
  private let store: PadStore

  init(store: PadStore) {
    self.store = store
  }

  var openCount: Int { controllers.count }

  func isOpen(_ padID: PadID) -> Bool { controllers[padID] != nil }

  func controller(for padID: PadID) -> PadWindowController? { controllers[padID] }

  /// Brings an existing panel forward, or creates one.
  @discardableResult
  func show(
    _ pad: PadMetadata,
    content: some View,
    makingKey: Bool = true
  ) -> PadWindowController {
    if let existing = controllers[pad.id] {
      existing.show(makingKey: makingKey)
      recordOpened(pad.id)
      return existing
    }
    let frame = FrameResolver.resolve(
      stored: pad.frame,
      screens: ScreenReader.screens(),
      mouseScreen: ScreenReader.mouseScreen(),
      openPanelCount: controllers.count)

    let controller = PadWindowController(
      padID: pad.id, store: store, contentRect: frame, content: content)
    controller.panel.title = pad.name
    controllers[pad.id] = controller
    observeClosure(of: controller)
    controller.show(makingKey: makingKey)
    recordOpened(pad.id)
    return controller
  }

  func close(_ padID: PadID) {
    controllers[padID]?.panel.performClose(nil)
  }

  /// Whether this pad's panel is frontmost and focused, which is what the global
  /// hotkey's toggle turns on (`FR-1.4`, Sprint 5).
  func isFrontmostAndKey(_ padID: PadID) -> Bool {
    guard let controller = controllers[padID] else { return false }
    return controller.isVisible && controller.isKey
  }

  /// The pad whose panel is frontmost and holds keyboard focus, if any.
  ///
  /// What `FR-1.4`'s toggle turns on, and the reason `HotKeyAction.decide` takes
  /// it as a value rather than reaching for the window server itself.
  func frontmostKeyPad() -> PadID? {
    controllers.first { $0.value.isVisible && $0.value.isKey }?.key
  }

  private func observeClosure(of controller: PadWindowController) {
    NotificationCenter.default.addObserver(
      forName: NSWindow.willCloseNotification,
      object: controller.panel,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.controllers[controller.padID] = nil
      }
    }
  }

  private func recordOpened(_ padID: PadID) {
    let store = store
    Task { await store.markOpened(padID) }
  }
}
