import Foundation

/// What an archive fingerprint is computed from, one per pad directory.
public struct PadSnapshot: Sendable, Equatable {
  public enum Metadata: Sendable, Equatable {
    case readable(name: String, mode: String, isPinned: Bool)
    /// The raw bytes, so that any change to an unreadable file still registers.
    case unreadable(Data)
  }

  public var id: String
  public var document: Data
  public var attachments: [String: Int]
  public var metadata: Metadata

  public init(id: String, document: Data, attachments: [String: Int], metadata: Metadata) {
    self.id = id
    self.document = document
    self.attachments = attachments
    self.metadata = metadata
  }
}

/// How the save at quit ended.
public enum FlushOutcome: Equatable, Sendable {
  case completed
  case timedOut
}

public enum QuitArchive: Equatable, Sendable {
  case take
  case skip
}

/// Decides when to archive and what to discard (D-11, D-18).
///
/// Separated from the copying because the rules are where the surprises are:
/// archiving on every launch and quit, unchanged, would fill a disk with
/// identical copies, and retention that kept the wrong end would discard the
/// only snapshot worth having.
public enum ArchivePolicy {
  /// How old the previous archive must be before a daily one is taken.
  public static let dailyInterval: TimeInterval = 24 * 60 * 60

  /// Whether to take an archive now.
  public static func shouldArchive(
    trigger: ArchiveTrigger,
    retention: Int,
    lastArchive: Date?,
    now: Date
  ) -> Bool {
    guard ArchiveBounds.clamp(retention) > ArchiveBounds.disabled else { return false }
    switch trigger {
    case .launch, .quit:
      return true
    case .daily:
      guard let lastArchive else { return true }
      return now.timeIntervalSince(lastArchive) >= dailyInterval
    }
  }

  /// Which archives to remove, oldest first, to stay within the limit.
  ///
  /// Returns what to delete rather than what to keep: the caller is removing
  /// directories that hold the user's content, and a function that says "delete
  /// these" is harder to misread than one that says "keep these".
  public static func pruning(_ archives: [PadArchive], retention: Int) -> [PadArchive] {
    let limit = ArchiveBounds.clamp(retention)
    let ordered = archives.sorted()
    guard ordered.count > limit else { return [] }
    return Array(ordered.prefix(ordered.count - limit))
  }

  /// Whether the pads have changed since the last archive was taken.
  ///
  /// Without this, a launch-and-quit cycle takes two identical snapshots, and a
  /// day of restarts leaves nothing but copies of the same thing — pushing the
  /// one archive that mattered off the end of the retention limit.
  public static func hasChanged(
    since fingerprint: String?,
    current: String
  ) -> Bool {
    fingerprint != current
  }

  /// A summary of what an archive would preserve: which pads exist, what they
  /// say, and their name, mode and pinning.
  ///
  /// Deliberately not modification times. Opening a pad records when it was
  /// opened and moving one records its frame, and each rewrites the pad's files,
  /// so a time-based fingerprint counted both as changes and took identical
  /// backups. Neither is worth preserving.
  ///
  /// The document is hashed in full because RTFD serialisation is deterministic
  /// — re-saving unchanged text produces identical bytes — and it is small
  /// beside the images, which are summarised by name and size instead.
  public static func fingerprint(of pads: [PadSnapshot]) -> String {
    var hash = StableHash()
    for pad in pads.sorted(by: { $0.id < $1.id }) {
      hash.combine(pad.id)
      hash.combine(pad.document)
      for (name, size) in pad.attachments.sorted(by: { $0.key < $1.key }) {
        hash.combine(name)
        hash.combine(size)
      }
      switch pad.metadata {
      case .readable(let name, let mode, let isPinned):
        hash.combine(name)
        hash.combine(mode)
        hash.combine(isPinned ? 1 : 0)
      case .unreadable(let bytes):
        hash.combine(bytes)
      }
    }
    return "2:\(pads.count):\(hash.hex)"
  }

  /// Whether to archive at quit, given how the final save went.
  ///
  /// A save that did not finish in time may still be writing, and a copy taken
  /// then could hold a pad half-saved. The next launch archives instead.
  public static func quitArchive(after outcome: FlushOutcome) -> QuitArchive {
    switch outcome {
    case .completed: .take
    case .timedOut: .skip
    }
  }

  /// Directory name for an archive: sortable, and legal on every filesystem.
  ///
  /// Colons are what ISO 8601 would use and what Finder renders as a slash, so
  /// the time is written without them.
  public static func directoryName(for date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd-HHmmss'Z'"
    return formatter.string(from: date)
  }

  public static func date(fromDirectoryName name: String) -> Date? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd-HHmmss'Z'"
    return formatter.date(from: name)
  }
}
