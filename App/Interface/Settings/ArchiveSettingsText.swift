import Foundation
import ItchyCore

/// What the backups pane says. A seam, because the wording changes with the
/// values and a view file may not branch (D-11).
enum ArchiveSettingsText {
  static func retentionLabel(_ retention: Int) -> String {
    retention == ArchiveBounds.disabled ? "Backups: off" : "Backups to keep: \(retention)"
  }

  /// States the privacy cost plainly. A backup holds a copy of every pad,
  /// including ones since deleted, and a user who does not want that should be
  /// told how to stop it rather than have to work it out.
  static func retentionCaption(_ retention: Int) -> String {
    guard retention > ArchiveBounds.disabled else {
      return "No copies are kept. Nothing can be recovered if a pad is lost."
    }
    return "A copy of every pad is saved when Itchy starts and quits, and kept "
      + "until \(retention) newer ones exist. Copies include pads you have since "
      + "deleted. Set this to zero to keep none."
  }

  static func summary(count: Int, bytes: Int) -> String {
    guard count > 0 else { return "None" }
    return "\(count) \(count == 1 ? "backup" : "backups"), \(size(bytes))"
  }

  /// Deliberately coarse; the number exists to make growth noticeable.
  static func size(_ bytes: Int) -> String {
    let megabytes = Double(bytes) / 1_048_576
    if megabytes < 1 { return "under 1 MB" }
    if megabytes >= 1_024 { return String(format: "%.1f GB", megabytes / 1_024) }
    return "\(Int(megabytes.rounded())) MB"
  }
}
