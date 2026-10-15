import CoreGraphics
import Testing

@testable import Itchy

/// `FR-3.9`. Rolling a pad up to its title bar is a gesture, a geometry and a
/// persistence rule, and all three are decided in `WindowShadePlan` so that
/// none of them needs a window server to check (D-11, D-34).
@Suite("Window shade plan")
struct WindowShadePlanTests {
  private let size = CGSize(width: 420, height: 520)
  private let visible = CGRect(x: 0, y: 0, width: 1_920, height: 1_080)

  @Test("A double-click on the title bar of an open pad shades it")
  func doubleClickShades() {
    #expect(WindowShadePlan.response(toClickCount: 2, inTitleBar: true, shade: .open) == .shade)
  }

  @Test("A double-click on the title bar of a shaded pad unshades it")
  func doubleClickUnshades() {
    let shaded = WindowShade.shaded(restoring: size)
    #expect(WindowShadePlan.response(toClickCount: 2, inTitleBar: true, shade: shaded) == .unshade)
  }

  /// The single press is the drag, and the drag must survive shading.
  @Test("A single click is left to AppKit")
  func singleClickPassesThrough() {
    #expect(WindowShadePlan.response(toClickCount: 1, inTitleBar: true, shade: .open) == .passThrough)
  }

  /// A triple-click is a double and then a third press. Toggling on the third
  /// would roll the pad straight back out.
  @Test("The third press of a triple-click does not toggle again")
  func tripleClickPassesThrough() {
    let shaded = WindowShade.shaded(restoring: size)
    #expect(WindowShadePlan.response(toClickCount: 3, inTitleBar: true, shade: shaded) == .passThrough)
  }

  @Test("A double-click in the text is the editor's, not ours")
  func doubleClickInContentPassesThrough() {
    #expect(WindowShadePlan.response(toClickCount: 2, inTitleBar: false, shade: .open) == .passThrough)
  }

  @Test("A summoned pad opens, whatever it was left as")
  func summonedOpens() {
    #expect(WindowShadePlan.onShow(storedShaded: true, isSummoned: true) == .open)
    #expect(WindowShadePlan.onShow(storedShaded: false, isSummoned: true) == .open)
  }

  /// `FR-2.7`'s pinned restore is not a summons, and keeps the state the pad
  /// was left in.
  @Test("A pad restored without being summoned keeps its shade")
  func restoredKeepsShade() {
    #expect(WindowShadePlan.onShow(storedShaded: true, isSummoned: false) == .shaded)
    #expect(WindowShadePlan.onShow(storedShaded: false, isSummoned: false) == .open)
  }

  /// AppKit's origin is bottom-left, so a roll that only changed the height
  /// would drop the title bar out from under the pointer.
  @Test("Shading keeps the top edge where it was")
  func shadingAnchorsTop() {
    let open = CGRect(x: 100, y: 200, width: 420, height: 520)
    let shaded = WindowShadePlan.shadedFrame(from: open, stripHeight: 31)
    #expect(shaded == CGRect(x: 100, y: 689, width: 420, height: 31))
    #expect(shaded.maxY == open.maxY)
  }

  @Test("Unshading hangs the remembered height from the strip's top edge")
  func unshadingRestoresSize() {
    let strip = CGRect(x: 300, y: 689, width: 420, height: 31)
    let open = WindowShadePlan.openFrame(from: strip, restoring: size, visible: visible)
    #expect(open == CGRect(x: 300, y: 200, width: 420, height: 520))
  }

  @Test("A shade then an unshade in place is the frame it started as")
  func roundTrip() {
    let start = CGRect(x: 100, y: 200, width: 420, height: 520)
    let strip = WindowShadePlan.shadedFrame(from: start, stripHeight: 31)
    #expect(WindowShadePlan.openFrame(from: strip, restoring: start.size, visible: visible) == start)
  }

  /// A strip dragged to the bottom of the screen has said where it is, not how
  /// big the pad is: the body is lifted on screen rather than shortened.
  @Test("Unshading near the bottom of the screen lifts the pad rather than shrinking it")
  func unshadingLiftsOntoScreen() {
    let strip = CGRect(x: 300, y: 20, width: 420, height: 31)
    let open = WindowShadePlan.openFrame(from: strip, restoring: size, visible: visible)
    #expect(open.size == size)
    #expect(open.minY == visible.minY)
  }

  @Test("A strip widened while shaded unrolls at its new width")
  func widthFollowsStrip() {
    let strip = CGRect(x: 300, y: 689, width: 600, height: 31)
    let open = WindowShadePlan.openFrame(from: strip, restoring: size, visible: visible)
    #expect(open.width == 600)
    #expect(open.height == size.height)
  }

  /// What is stored is always the open frame, so `FrameResolver` keeps meaning
  /// the same thing by a stored frame whether or not the pad was shaded.
  @Test("The stored frame of a shaded pad is its open frame")
  func storedFrameIsOpen() {
    let strip = CGRect(x: 300, y: 20, width: 420, height: 31)
    let stored = WindowShadePlan.storedFrame(panel: strip, shade: .shaded(restoring: size))
    #expect(stored == CGRect(x: 300, y: -469, width: 420, height: 520))
  }

  @Test("The stored frame of an open pad is the panel's frame")
  func storedFrameOpen() {
    let frame = CGRect(x: 1, y: 2, width: 3, height: 4)
    #expect(WindowShadePlan.storedFrame(panel: frame, shade: .open) == frame)
  }

  @Test("Shade state reports whether it is shaded")
  func isShaded() {
    #expect(!WindowShade.open.isShaded)
    #expect(WindowShade.shaded(restoring: size).isShaded)
  }
}
