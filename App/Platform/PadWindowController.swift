import AppKit
import ItchyCore
import SwiftUI

/// Owns one pad's panel.
///
/// Frame changes are written into the pad's metadata on move and resize rather
/// than through `setFrameAutosaveName`, so that the frame travels with the pad
/// record and is readable by the same machinery that reads everything else
/// (`FR-3.4`, specification §8.4).
@MainActor
final class PadWindowController: NSObject, NSWindowDelegate {
  let padID: PadID
  let panel: PadPanel
  private let store: PadStore
  private var frameWriteTask: Task<Void, Never>?

  /// Frame writes are debounced so that a drag does not stage on every frame.
  static let frameDebounce: Duration = .milliseconds(200)

  init(padID: PadID, store: PadStore, contentRect: NSRect, content: some View) {
    self.padID = padID
    self.store = store
    self.panel = PadPanel(contentRect: contentRect)
    super.init()

    panel.contentView = NSHostingView(rootView: content)
    panel.delegate = self
    panel.setFrame(contentRect, display: false)
  }

  /// Brings the panel forward.
  ///
  /// `makingKey` distinguishes the two cases, and the distinction is not
  /// cosmetic. A pad the user asked for should take keyboard focus, because they
  /// are about to type into it. A pad restored at launch because it was pinned
  /// (`FR-2.7`) should appear without taking focus from whatever the user is
  /// actually doing — an application that steals the keyboard on login is an
  /// application that gets quit.
  func show(makingKey: Bool = true) {
    guard makingKey else {
      panel.orderFrontRegardless()
      return
    }
    panel.makeKeyAndOrderFront(nil)
  }

  var isVisible: Bool { panel.isVisible }
  var isKey: Bool { panel.isKeyWindow }

  func windowDidMove(_ notification: Notification) {
    scheduleFrameWrite()
  }

  func windowDidResize(_ notification: Notification) {
    scheduleFrameWrite()
  }

  /// Closing a pad puts it away with no prompt and no loss, and forces a save
  /// (`FR-3.5`).
  func windowWillClose(_ notification: Notification) {
    frameWriteTask?.cancel()
    let frame = currentFrame()
    let store = store
    let padID = padID
    Task {
      await store.setFrame(padID, frame)
      try? await store.flush(padID)
    }
  }

  private func scheduleFrameWrite() {
    frameWriteTask?.cancel()
    let frame = currentFrame()
    let store = store
    let padID = padID
    frameWriteTask = Task {
      try? await Task.sleep(for: Self.frameDebounce)
      guard !Task.isCancelled else { return }
      await store.setFrame(padID, frame)
    }
  }

  private func currentFrame() -> PadFrame {
    let frame = panel.frame
    return PadFrame(
      x: frame.origin.x,
      y: frame.origin.y,
      width: frame.size.width,
      height: frame.size.height,
      displayID: panel.screen.flatMap(ScreenReader.displayID(of:)))
  }
}
