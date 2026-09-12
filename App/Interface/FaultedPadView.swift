import SwiftUI

/// What a pad shows when its content could not be read.
///
/// Not an editor. Specification §6.7 prohibits presenting an empty editable pad
/// over unreadable content, because the next save would destroy what is there.
struct FaultedPadView: View {
  let presentation: FaultPresentation.Presentation
  let onReveal: () -> Void

  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.largeTitle)
        .foregroundStyle(.orange)
      Text(presentation.headline)
        .font(.headline)
        .multilineTextAlignment(.center)
      Text(presentation.detail)
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .textSelection(.enabled)
      Button("Reveal in Finder", action: onReveal)
        .opacity(presentation.offersRevealInFinder ? 1 : 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(24)
    .accessibilityIdentifier("pad.fault")
    .accessibilityElement(children: .contain)
    .accessibilityLabel(presentation.headline)
  }
}
