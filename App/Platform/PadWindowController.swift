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
  private let hosting: NSView

  /// Rolled up or not, and if so to what size it unrolls (`FR-3.9`).
  private(set) var shade: WindowShade = .open

  /// The pad's accent, which decides how much of the content stays showing
  /// under a shaded title bar: the rule is kept, because it is how a rolled-up
  /// pad is told apart from another (`FR-3.8`).
  var accent: PadAccent?

  /// Whoever had the keyboard when the panel was rolled up, given it back when
  /// it is unrolled, so that the caret is where it was.
  private weak var responderBeforeShade: NSResponder?

  /// Frame writes are debounced so that a drag does not stage on every frame.
  static let frameDebounce: Duration = .milliseconds(200)

  init(padID: PadID, store: PadStore, contentRect: NSRect, content: some View) {
    self.padID = padID
    self.store = store
    self.panel = PadPanel(contentRect: contentRect)

    // The content is hosted inside a clipping container rather than being the
    // content view itself, so that rolling up can leave it at its full height
    // and let the window cut it off. Resizing the SwiftUI tree to three points
    // would squeeze the editor out of the layout, and removing it would discard
    // its undo stack and selection (D-34).
    let hostingView = NSHostingView(rootView: content)
    hostingView.sizingOptions = []
    hostingView.autoresizingMask = [.width, .height]
    hosting = hostingView
    super.init()

    let container = NSView()
    container.clipsToBounds = true
    panel.contentView = container
    hostingView.frame = container.bounds
    container.addSubview(hostingView)
    panel.delegate = self
    panel.setFrame(contentRect, display: false)
    panel.onTitleBarClick = { [weak self] clickCount, inTitleBar in
      self?.titleBarClicked(clickCount: clickCount, inTitleBar: inTitleBar) ?? false
    }
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
    if makingKey { setShade(.open, animated: panel.isVisible) }
    guard makingKey else {
      panel.orderFrontRegardless()
      return
    }
    panel.makeKeyAndOrderFront(nil)
  }

  /// Applies the shaded state a pad was stored with, before it is first shown.
  func restore(storedShaded: Bool, isSummoned: Bool) {
    switch WindowShadePlan.onShow(storedShaded: storedShaded, isSummoned: isSummoned) {
    case .shaded: setShade(.shaded(restoring: panel.frame.size), animated: false)
    case .open: break
    }
  }

  private func titleBarClicked(clickCount: Int, inTitleBar: Bool) -> Bool {
    switch WindowShadePlan.response(toClickCount: clickCount, inTitleBar: inTitleBar, shade: shade) {
    case .passThrough:
      return false
    case .shade:
      setShade(.shaded(restoring: panel.frame.size), animated: true)
      return true
    case .unshade:
      setShade(.open, animated: true)
      return true
    }
  }

  /// Rolls the panel up or down (`FR-3.9`).
  ///
  /// While shaded the panel may still be dragged and widened, never heightened:
  /// the minimum and maximum heights are both the strip's, which is how the
  /// resize edge is kept from dragging a body back out without its content.
  private func setShade(_ target: WindowShade, animated: Bool) {
    switch (shade, target) {
    case (.open, .shaded):
      roll(up: target, animated: animated)
    case (.shaded(let size), .open):
      roll(down: size, animated: animated)
    default:
      return
    }
  }

  private func roll(up target: WindowShade, animated: Bool) {
    responderBeforeShade = panel.firstResponder
    panel.makeFirstResponder(nil)
    shade = target
    panel.isShaded = true
    hosting.autoresizingMask = [.width, .minYMargin]
    let accentHeight = accent == nil ? 0 : CGFloat(PadAccentPalette.thickness)
    let strip = panel.stripHeight(showingContent: accentHeight)
    panel.minSize = NSSize(width: PanelConfiguration.standard.minimumSize.width, height: strip)
    panel.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: strip)
    panel.setFrame(
      WindowShadePlan.shadedFrame(from: panel.frame, stripHeight: strip),
      display: true, animate: animated)
  }

  private func roll(down size: CGSize, animated: Bool) {
    panel.minSize = PanelConfiguration.standard.minimumSize
    panel.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
    let open = WindowShadePlan.openFrame(
      from: panel.frame, restoring: size, visible: panel.screen?.visibleFrame)
    panel.setFrame(open, display: true, animate: animated)
    hosting.autoresizingMask = [.width, .height]
    hosting.frame = panel.contentView?.bounds ?? hosting.frame
    shade = .open
    panel.isShaded = false
    scheduleFrameWrite()
    if let responder = responderBeforeShade { panel.makeFirstResponder(responder) }
  }

  var isVisible: Bool { panel.isVisible }
  var isKey: Bool { panel.isKeyWindow }

  /// On screen, holding the keyboard, and open enough to type into.
  var isFocused: Bool { isVisible && isKey && !shade.isShaded }

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

  /// The open frame, even while shaded (`FR-3.9`): what is stored is the pad's
  /// size, and the strip is only how it is being shown.
  private func currentFrame() -> PadFrame {
    let frame = WindowShadePlan.storedFrame(panel: panel.frame, shade: shade)
    return PadFrame(
      x: frame.origin.x,
      y: frame.origin.y,
      width: frame.size.width,
      height: frame.size.height,
      displayID: panel.screen.flatMap(ScreenReader.displayID(of:)),
      isShaded: shade.isShaded)
  }
}
