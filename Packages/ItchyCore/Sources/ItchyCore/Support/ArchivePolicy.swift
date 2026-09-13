import Foundation

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

  /// A cheap summary of the pads' state: how many there are and when the most
  /// recent was modified. Content is not read (`FR-1.6` applies here too).
  public static func fingerprint(padCount: Int, latestModification: Date?) -> String {
    let stamp = latestModification.map { String(Int($0.timeIntervalSince1970)) } ?? "none"
    return "\(padCount):\(stamp)"
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
