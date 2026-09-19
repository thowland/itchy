import Foundation
import ItchyCore

/// The external-write banner on a pad's panel (`FR-8.9`, §10, §11.7).
///
/// Decides three things the view then renders: whether it appears at all, what
/// it says, and whether undo is offered. Undo is the one that has to be decided
/// rather than assumed — a write that arrived while the panel was closed has no
/// undo to offer, which is D-9's consequence and the reason this banner exists.
enum BannerState: Equatable, Sendable {
  case hidden
  case shown(text: String, undo: UndoOffer)

  /// Whether the banner's Undo button appears.
  ///
  /// An enumeration rather than a `Bool` because "no" has a reason the person
  /// needs: a button that is simply absent reads as an oversight, and one that
  /// is present and does nothing is worse.
  enum UndoOffer: Equatable, Sendable {
    case available
    case unavailableWrittenWhileClosed
  }

  var isShown: Bool {
    if case .shown = self { return true }
    return false
  }
}

enum BannerModel {
  /// How long a write stays worth mentioning.
  ///
  /// Long enough to survive a lunch break, because the point of the marker is
  /// that the person learns about a write they did not see happen. Beyond a day
  /// it is history rather than news, and the pad's own text is the record.
  static let lifetime: TimeInterval = 24 * 60 * 60

  /// `now` is passed rather than read, so that "a marker from yesterday no
  /// longer shows" is a test and not a wait.
  static func state(for pad: PadMetadata, now: Date, wasOpen: Bool = true) -> BannerState {
    guard let marker = pad.externalWriteMarker else { return .hidden }
    guard now.timeIntervalSince(marker.at) <= lifetime else { return .hidden }
    guard now.timeIntervalSince(marker.at) >= 0 else { return .hidden }
    return .shown(
      text: text(for: marker, now: now),
      undo: wasOpen ? .available : .unavailableWrittenWhileClosed)
  }

  /// What the banner reads. Says what wrote, what it did, and when.
  static func text(for marker: ExternalWriteMarker, now: Date) -> String {
    "\(author(of: marker.origin)) \(change(marker.characterDelta)) \(age(from: marker.at, to: now))."
  }

  /// What the Undo button says, or why there is not one.
  static func undoLabel(_ offer: BannerState.UndoOffer) -> String {
    switch offer {
    case .available: "Undo"
    case .unavailableWrittenWhileClosed: "Written while this pad was closed — no undo for it."
    }
  }

  static let dismissLabel = "Dismiss"

  static func author(of origin: WriteOrigin) -> String {
    switch origin {
    case .user:
      return "You"
    case .transform(let name):
      return "The \(name) transform"
    case .mcp(let client):
      guard let client, !client.isEmpty else { return "An agent" }
      return client
    }
  }

  /// Coarse on purpose. The number exists to say that something changed and
  /// roughly how much, not to be audited.
  static func change(_ characters: Int) -> String {
    guard characters > 0 else { return "emptied this pad" }
    return "wrote \(characters) character\(characters == 1 ? "" : "s")"
  }

  static func age(from written: Date, to now: Date) -> String {
    let seconds = Int(now.timeIntervalSince(written))
    switch seconds {
    case ..<60: return "just now"
    case ..<3_600: return "\(seconds / 60) minute\(seconds / 60 == 1 ? "" : "s") ago"
    default: return "\(seconds / 3_600) hour\(seconds / 3_600 == 1 ? "" : "s") ago"
    }
  }
}
