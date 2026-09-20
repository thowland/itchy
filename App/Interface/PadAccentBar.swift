import ItchyCore
import SwiftUI

/// The rule under a pad's title bar (`FR-3.8`, D-33).
///
/// Drawn inside the content rather than as window chrome, which is what keeps
/// `FR-3.7` intact: the window's decoration is still entirely the system's. It
/// also means the rule keeps its colour when the panel is not the key window,
/// and a non-activating panel is not the key window most of the time it is
/// being looked for.
///
/// A pad with no accent draws a zero-height bar rather than being absent from
/// the stack, so that switching the accent on and off does not restructure the
/// view tree underneath an editor that is holding a selection.
struct PadAccentBar: View {
  let accent: PadAccent?

  var body: some View {
    Rectangle()
      .fill(fill)
      .frame(height: accent == nil ? 0 : PadAccentPalette.thickness)
      .accessibilityHidden(true)
  }

  private var fill: Color {
    guard let accent else { return .clear }
    return AccentColorCodec.dynamicColor(for: accent)
  }
}
