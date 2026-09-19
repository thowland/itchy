import SwiftUI

/// The banner's contents, once `BannerModel` has decided there is one.
///
/// Split from `ExternalWriteBanner` so that the unwrapping of the shown case
/// happens in one place with nothing else in it, which is what keeps both files
/// inside the complexity cap.
struct BannerBody: View {
  let state: BannerState
  let onUndo: () -> Void
  let onDismiss: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "sparkles")
      Text(BannerText.message(state))
        .font(.caption)
        .accessibilityIdentifier("pad.banner")
      Spacer()
      BannerUndoButton(offer: BannerText.offer(state), action: onUndo)
      Button(BannerModel.dismissLabel, action: onDismiss)
        .buttonStyle(.plain)
        .font(.caption)
        .accessibilityIdentifier("pad.banner.dismiss")
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(.yellow.opacity(0.18))
  }
}

/// Offered, or explained. `BannerModel.undoLabel` supplies both wordings.
struct BannerUndoButton: View {
  let offer: BannerState.UndoOffer
  let action: () -> Void

  var body: some View {
    Button(BannerModel.undoLabel(offer), action: action)
      .buttonStyle(.plain)
      .font(.caption)
      .disabled(offer != .available)
      .accessibilityIdentifier("pad.banner.undo")
  }
}

/// The unwrapping, out of the view bodies (D-11).
enum BannerText {
  static func message(_ state: BannerState) -> String {
    guard case .shown(let text, _) = state else { return "" }
    return text
  }

  static func offer(_ state: BannerState) -> BannerState.UndoOffer {
    guard case .shown(_, let offer) = state else { return .unavailableWrittenWhileClosed }
    return offer
  }
}
