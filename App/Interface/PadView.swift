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
