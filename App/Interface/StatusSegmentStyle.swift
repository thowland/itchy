import SwiftUI

/// How a status segment is drawn. A seam, because deciding that a fault reads in
/// red is a decision and view files do not make decisions (D-11).
///
/// It lived in `PadView.swift` until it needed to distinguish a third kind.
/// That file is on the coverage exclusion list and so may hold no branch at all
/// (§15.3), and the choice the list forces at that point is to widen the
/// exclusion or to move the decision somewhere it can be measured. This is the
/// second.
enum StatusSegmentStyle {
  static func style(for segment: StatusSegment) -> AnyShapeStyle {
    switch segment.kind {
    case .fault, .notice: AnyShapeStyle(.red)
    default: AnyShapeStyle(.secondary)
    }
  }

  static func separatorOpacity(_ segment: StatusSegment, in segments: [StatusSegment]) -> Double {
    segment.id == segments.last?.id ? 0 : 1
  }
}
