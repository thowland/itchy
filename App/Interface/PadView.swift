import ItchyCore
import SwiftUI

/// A pad's contents and its status line.
///
/// This file is on the coverage exclusion list, so it may not branch — anything
/// resembling a decision belongs in `StatusBarModel` or `PadTextCoordinator`.
struct PadView: View {
  let coordinator: PadTextCoordinator
  let mode: PadMode
  let initial: NSAttributedString
  let segments: [StatusSegment]

  var body: some View {
    VStack(spacing: 0) {
      PadTextEditor(coordinator: coordinator, mode: mode, initial: initial)
      Divider()
      PadStatusBar(segments: segments)
    }
  }
}

/// The pad's state, legible without opening settings or a menu (`FR-3.6`).
struct PadStatusBar: View {
  let segments: [StatusSegment]

  var body: some View {
    HStack(spacing: 8) {
      ForEach(segments) { segment in
        Text(segment.text)
          .font(.caption)
          .foregroundStyle(StatusSegmentStyle.style(for: segment))
        Text(verbatim: "·")
          .font(.caption)
          .foregroundStyle(.tertiary)
          .opacity(StatusSegmentStyle.separatorOpacity(segment, in: segments))
      }
      Spacer()
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 5)
  }
}

/// How a status segment is drawn. A seam, because deciding that a fault reads in
/// red is a decision and view files do not make decisions (D-11).
enum StatusSegmentStyle {
  static func style(for segment: StatusSegment) -> AnyShapeStyle {
    segment.kind == .fault ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary)
  }

  static func separatorOpacity(_ segment: StatusSegment, in segments: [StatusSegment]) -> Double {
    segment.id == segments.last?.id ? 0 : 1
  }
}
