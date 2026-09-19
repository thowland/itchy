import AppKit
import ItchyCore

/// The external-write banner (`FR-8.9`, §11.7).
///
/// The coordinator holds which banners the person has dismissed; whether one
/// appears and what it says is `BannerModel`'s.
extension PadCoordinator {
  /// Whether a write that arrived while the panel was closed can be undone.
  ///
  /// It cannot: the text view's undo stack begins when the panel opens, so
  /// there is nothing on it to revert. Saying so is the compensating control
  /// D-9 asked for — the alternative is a button that looks live and reverts
  /// the person's own last edit instead.
  func bannerState(for pad: PadMetadata) -> BannerState {
    guard dismissedBanners[pad.id] != pad.externalWriteMarker?.at else { return .hidden }
    return BannerModel.state(
      for: pad, now: Date(), wasOpen: panelWasOpenFor[pad.id] == pad.externalWriteMarker?.at)
  }

  /// Dismissed for this write, not for all of them: the next external write
  /// raises it again.
  func dismissBanner(_ padID: PadID) {
    dismissedBanners[padID] = pads.first { $0.id == padID }?.externalWriteMarker?.at
  }

  /// The banner's Undo performs the same undo the keyboard would (§10), so
  /// that there is one undo stack and not two notions of what "undo" means.
  func undoExternalWrite(_ padID: PadID) {
    registry.controller(for: padID)?.panel.undoManager?.undo()
    dismissBanner(padID)
  }

  /// Recorded when a write lands, so that the banner knows whether it has an
  /// undo to offer. Called after the refresh, because the marker's timestamp is
  /// what identifies the write and it arrives with the refreshed metadata.
  func recordExternalWrite(_ padID: PadID, wasOpen: Bool) {
    guard wasOpen else { return }
    panelWasOpenFor[padID] = pads.first { $0.id == padID }?.externalWriteMarker?.at
  }
}

/// Which pad a change concerns, when it is an external write.
///
/// A decision — small, but the alternative is a `case` inside the coordinator's
/// observation loop, and that loop is where every future change event will want
/// one too.
enum ExternalWriteRouting {
  static func pad(in change: PadChange) -> PadID? {
    guard case .contentChangedExternally(let id, _) = change else { return nil }
    return id
  }
}
