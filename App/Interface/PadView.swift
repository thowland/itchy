import ItchyCore
import SwiftUI

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
