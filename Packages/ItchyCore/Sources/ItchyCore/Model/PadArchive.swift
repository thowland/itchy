import Foundation

/// One snapshot of every pad, taken at a moment in time.
///
/// Archives exist because pads are held in a format this application is still
/// actively changing, and a defect in the storage layer would otherwise be
/// unrecoverable. They are insurance against us, not a document history for the
/// user — nothing in the interface browses them, and `CON-1` still holds
/// (D-18).
public struct PadArchive: Sendable, Equatable, Identifiable, Comparable {
  /// The directory name, which is also the sort key.
  public let id: String
  public let taken: Date
  public let padCount: Int
  public let byteCount: Int

  public init(id: String, taken: Date, padCount: Int, byteCount: Int) {
    self.id = id
    self.taken = taken
    self.padCount = padCount
    self.byteCount = byteCount
  }

  /// Newest last, so pruning can take from the front.
  public static func < (lhs: PadArchive, rhs: PadArchive) -> Bool {
    lhs.taken < rhs.taken
  }
}

/// What caused an archive to be considered.
public enum ArchiveTrigger: String, Sendable, Equatable, CaseIterable {
  /// The application started.
  case launch
  /// The application is terminating.
  case quit
  /// A day has passed since the last one.
  case daily
}

/// Limits on how much history is kept.
public enum ArchiveBounds {
  /// Keeping none disables archiving entirely, which is the setting a user who
  /// does not want deleted pads persisting anywhere should choose.
  public static let disabled = 0
  public static let defaultRetention = 10
  /// A ceiling for the same reason the pad count has one: an unbounded setting
  /// erodes into unbounded disk use, and these hold real content.
  public static let maximumRetention = 50

  public static func clamp(_ requested: Int) -> Int {
    min(max(requested, disabled), maximumRetention)
  }
}
