import ItchyCore
import SwiftUI

/// A pad's contents and its status line.
///
/// Sprint 2 shows the status line over a placeholder; the text view arrives in
/// Sprint 3 (`FR-4.1`). This file is on the coverage exclusion list, so it may
/// not branch — anything resembling a decision belongs in `StatusBarModel`.
struct PadView: View {
  let segments: [StatusSegment]

  var body: some View {
    VStack(spacing: 0) {
      PadPlaceholderView()
      Divider()
      PadStatusBar(segments: segments)
    }
  }
}

/// Stands in for the text view until Sprint 3.
///
/// It is a real editable field rather than a label, and deliberately so: Sprint
/// 2's exit gate is that a panel summoned over another application accepts typed
/// input (`FR-3.2`), and that cannot be demonstrated against static text. The
/// `NSTextView` bridge replaces this in Sprint 3.
struct PadPlaceholderView: View {
  @State private var draft = ""

  var body: some View {
    TextField("The editor arrives in Sprint 3", text: $draft, axis: .vertical)
      .textFieldStyle(.plain)
      .font(.body)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .padding(8)
      .accessibilityIdentifier("pad.placeholder.input")
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
          .foregroundStyle(segment.kind == .fault ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
        Text(verbatim: "·")
          .font(.caption)
          .foregroundStyle(.tertiary)
          .opacity(segment.id == segments.last?.id ? 0 : 1)
      }
      Spacer()
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 5)
  }
}
