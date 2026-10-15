import CoreGraphics

/// Whether a pad panel is rolled up to its title bar (`FR-3.9`, D-34).
///
/// The shaded case carries the size to unroll to, because that is the one thing
/// a shaded window cannot be asked for: its own frame says only how tall a
/// title bar is.
enum WindowShade: Equatable, Sendable {
  case open
  case shaded(restoring: CGSize)

  var isShaded: Bool {
    if case .shaded = self { return true }
    return false
  }
}

/// What a click on the title bar does (`FR-3.9`).
enum TitleBarClickResponse: Equatable, Sendable {
  /// Not ours: AppKit handles it as it would for any window, which for a single
  /// click is the drag.
  case passThrough
  case shade
  case unshade
}

/// Whether a panel being shown should be open or shaded.
enum ShadeOnShow: Equatable, Sendable {
  case open
  case shaded
}

/// Every decision window shading takes, as values (D-11).
///
/// The panel reports clicks and the controller sets frames; neither decides
/// anything. The geometry is all here because it is where the mistakes would
/// be — a roll that anchors the wrong edge and moves the title bar out from
/// under the pointer, or an unroll that puts the body off the bottom of the
/// screen.
enum WindowShadePlan {
  /// A double-click on the title bar toggles; nothing else is ours.
  ///
  /// Exactly two rather than at least two. A triple-click arrives as a double
  /// and then a third press, and treating the third as another toggle would
  /// roll the pad straight back out again.
  static func response(
    toClickCount clickCount: Int,
    inTitleBar: Bool,
    shade: WindowShade
  ) -> TitleBarClickResponse {
    guard inTitleBar, clickCount == 2 else { return .passThrough }
    return shade.isShaded ? .unshade : .shade
  }

  /// A pad summoned by the person opens; one restored on its own keeps the
  /// state it was left in.
  ///
  /// Summoning — the hotkey, the menubar — is what somebody does when they are
  /// about to type, and a shaded pad has nowhere to type into. A pinned pad
  /// restored at launch is not being summoned, and opening it would undo the
  /// choice somebody made when they rolled it up.
  static func onShow(storedShaded: Bool, isSummoned: Bool) -> ShadeOnShow {
    storedShaded && !isSummoned ? .shaded : .open
  }

  /// The rolled-up frame: the same top edge and width, as tall as the strip.
  ///
  /// The top edge is the anchor because it is where the title bar is, and the
  /// title bar is what was just double-clicked. AppKit's origin is bottom-left,
  /// which is why this is not simply a change of height.
  static func shadedFrame(from open: CGRect, stripHeight: CGFloat) -> CGRect {
    CGRect(
      x: open.minX, y: open.maxY - stripHeight,
      width: open.width, height: stripHeight)
  }

  /// The unrolled frame: hung from the strip's top edge at the remembered
  /// height, then lifted if that would put the body below the screen.
  ///
  /// Lifted rather than shortened, because the height is what was remembered
  /// and the position is what was dragged; a strip left near the bottom of the
  /// screen has said where it is, not how big the pad is. Width is the strip's
  /// own, since a strip can be resized sideways while it is rolled up.
  static func openFrame(
    from shaded: CGRect,
    restoring size: CGSize,
    visible: CGRect?
  ) -> CGRect {
    let hung = CGRect(
      x: shaded.minX, y: shaded.maxY - size.height,
      width: shaded.width, height: size.height)
    guard let visible, hung.minY < visible.minY else { return hung }
    let lifted = min(visible.minY, visible.maxY - hung.height)
    return CGRect(x: hung.minX, y: lifted, width: hung.width, height: hung.height)
  }

  /// What is written to the pad for the panel as it stands.
  ///
  /// Always the open frame, so that `FrameResolver` and everything else that
  /// reads a stored frame keeps meaning the same thing by it. Unclamped,
  /// because the visible area of the moment is not the pad's business.
  static func storedFrame(panel: CGRect, shade: WindowShade) -> CGRect {
    switch shade {
    case .open:
      return panel
    case .shaded(let size):
      return openFrame(from: panel, restoring: size, visible: nil)
    }
  }
}
